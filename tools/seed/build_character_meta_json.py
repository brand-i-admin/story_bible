#!/usr/bin/env python3
"""Build tools/seed/character_meta.json from assets/200_stories JSON files.

Rules:
- Expand group codes: disciples/apostles/brothers -> individual character codes.
- Remove non-individual codes (groups/placeholders like mysterious_man, babel_people).
- Include EVERY individual character, regardless of mention_count.
  Visibility in the app is controlled at runtime by ``characters.is_active``.
- Each character carries an ``is_active_default`` hint for the characters-seed
  builder: people with mention_count >= ACTIVE_DEFAULT_THRESHOLD start
  active, single-mention newcomers start inactive (admin opts them in later).
- Reuse existing prompt metadata only when prompt_source=manual.
- If no manual style exists, use built-in default style/palette config.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

EVENT_NO_RE = re.compile(r"^(\d{3})\s+.*$")

DISCIPLES_WITH_JUDAS = [
    "peter",
    "andrew",
    "james_zebedee",
    "john",
    "philip",
    "bartholomew",
    "matthew",
    "thomas",
    "james_alphaeus",
    "thaddaeus",
    "simon_zealot",
    "judas",
]
DISCIPLES_NO_JUDAS = [code for code in DISCIPLES_WITH_JUDAS if code != "judas"]
APOSTLES_AFTER_MATTHIAS = DISCIPLES_NO_JUDAS + ["matthias"]
BROTHERS_ALL = [
    "reuben",
    "simeon",
    "levi",
    "judah",
    "dan",
    "naphtali",
    "gad",
    "asher",
    "issachar",
    "zebulun",
    "benjamin",
]
BROTHERS_WITHOUT_BENJAMIN = [code for code in BROTHERS_ALL if code != "benjamin"]
# Explicit roster exclusions for codes that are technically character names
# but should not appear as selectable characters in the app.
ROSTER_EXCLUDED_CODES = {"dan", "lot_wife"}

DEFAULT_STYLE_SOURCE: dict[str, Any] = {
    "common_style": (
        "stylized geometric biblical character illustration, "
        "blocky low-poly faceted planes, angular polygon face and hair, "
        "flat matte vector shading with subtle cut-paper facets, "
        "strict canonical body proportions, head:torso:legs = 1:1:1 exactly, "
        "head section one-third of total height, torso section one-third, legs section one-third, "
        "same body ratio template across all human characters, compact adult proportions, not chibi, "
        "simple small eyes and nose, mature friendly expression, "
        "minimal clean outline, exactly one character only, solo single subject, "
        "full body visible from head to toe, both feet visible, whole figure fits inside frame, "
        "centered, plain white background, "
        "high resolution, consistent design system across the full cast, "
        "distinct silhouette and face geometry for each character, "
        "distinct hairstyle and story-inspired accessory for each character, "
        "no text, no watermark"
    ),
    "negative_prompt": (
        "realistic, photoreal, anime, manga, glossy 3D render, clay, pixel art, "
        "chibi, super-deformed, giant head, baby proportions, oversized eyes, "
        "long legs, short legs, tiny torso, oversized torso, tiny body, stretched body, "
        "uneven body ratio, inconsistent body proportions, head larger than torso, legs longer than torso, "
        "same-face clones, duplicate character, multiple people, crowd, group shot, "
        "companions, side characters, extra faces, extra bodies, twin, mirrored figure, "
        "close-up, portrait crop, bust shot, half body, cropped head, cropped feet, "
        "marshmallow body, gritty, dark, horror, "
        "complex background, text, logo, watermark"
    ),
    "palettes": {
        "primeval": "soft beige + olive + sky blue accents",
        "patriarch": "warm sand + cream + muted teal accents",
        "exodus_wilderness": "teal + desert tan + bronze accents",
        "judges": "olive green + clay brown + muted gold accents",
        "monarchy": "royal purple + navy + muted gold accents",
        "prophets_exile": "muted indigo + gray + parchment cream accents",
        "post_exile_return": "stone gray + sage green + parchment cream accents",
        "gospels": "cream + sky blue + soft rose accents",
        "early_church": "teal + sea blue + warm brown accents",
    },
    "generation_defaults": {
        "sampleCount": 1,
        "aspectRatio": "1:1",
        "enhancePrompt": False,
        "personGeneration": "allow_adult",
        "outputMimeType": "image/png",
    },
}

# Known group/non-individual/noise codes in story JSON.
NON_INDIVIDUAL_CODES = {
    "abraham_servant",
    "angels",
    "apostles",
    "babel_people",
    "beasts",
    "believers",
    "bleeding_woman",
    "brothers",
    "builders",
    "chief_baker",
    "chief_cupbearer",
    "chief_priests",
    "church_of_antioch",
    "crowd",
    "danites",
    "disciples",
    "dragon",
    "egyptian_taskmaster",
    "ephesus_elders",
    "ethiopian_eunuch",
    "father",
    "gibeonites",
    "good_samaritan",
    "heavenly_beings",
    "heavenly_voice",
    "islanders",
    "israelites",
    "jerusalem_crowd",
    "jerusalem_people",
    "judge",
    "lamb",
    "lame_man",
    "lawyer",
    "leaders",
    "magi",
    "moneychangers",
    "moses_mother",
    "mysterious_man",
    "older_brother",
    "people",
    "pharaoh_daughter",
    "potiphar_wife",
    "prodigal_son",
    "prophets_of_baal",
    "queen_of_sheba",
    "remnant_people",
    "returnees",
    "saints",
    "samaritans",
    "shepherds",
    "ship_crew",
    "tempter",
}

ERA_CODE_TO_STYLE = {
    "era_primeval": "primeval",
    "era_patriarch": "patriarch",
    "era_exodus": "exodus_wilderness",
    "era_judges": "judges",
    "era_monarchy": "monarchy",
    "era_exile_return": "post_exile_return",
    "era_nt_public_ministry": "gospels",
    "era_nt_apostolic": "early_church",
    "era_nt_post_apostolic": "early_church",
    "era_nt_consummation": "early_church",
}

KO_NAME_OVERRIDES = {
    "jesus": "예수님",
    "moses": "모세",
    "paul": "바울",
    "john": "요한",
    "peter": "베드로",
    "joseph": "요셉",
    "jacob": "야곱",
    "abraham": "아브라함",
    "philip": "빌립",
    "andrew": "안드레",
    "david": "다윗",
    "matthew": "마태",
    "thomas": "도마",
    "saul": "사울",
    "joshua": "여호수아",
    "judas": "유다",
    "sarah": "사라",
    "aaron": "아론",
    "samuel": "사무엘",
    "elijah": "엘리야",
    "esther": "에스더",
    "mary": "마리아",
    "nehemiah": "느헤미야",
    "isaac": "이삭",
    "mordecai": "모르드개",
    "solomon": "솔로몬",
    "adam": "아담",
    "daniel": "다니엘",
    "eve": "하와",
    "james": "야고보",
    "lot": "롯",
    "noah": "노아",
    "rachel": "라헬",
    "ruth": "룻",
    "abimelech": "아비멜렉",
    "ahab": "아합",
    "boaz": "보아스",
    "elisha": "엘리사",
    "ezra": "에스라",
    "gideon": "기드온",
    "hagar": "하갈",
    "haman": "하만",
    "isaiah": "이사야",
    "jeremiah": "예레미야",
    "leah": "레아",
    "naomi": "나오미",
    "rebekah": "리브가",
    "dan": "단",
    "ananias": "아나니아",
    "asher": "아셀",
    "barnabas": "바나바",
    "bartholomew": "바돌로매",
    "benjamin": "베냐민",
    "elizabeth": "엘리사벳",
    "esau": "에서",
    "ezekiel": "에스겔",
    "gad": "갓",
    "gabriel": "가브리엘",
    "god": "하나님",
    "hezekiah": "히스기야",
    "ishmael": "이스마엘",
    "issachar": "잇사갈",
    "james_alphaeus": "야고보(알패오의 아들)",
    "james_zebedee": "야고보(세베대의 아들)",
    "judah": "유다",
    "laban": "라반",
    "levi": "레위",
    "matthias": "맛디아",
    "naphtali": "납달리",
    "nathan": "나단",
    "pharaoh": "바로",
    "reuben": "르우벤",
    "silas": "실라",
    "simeon": "시므온",
    "simon_zealot": "시몬(셀롯)",
    "thaddaeus": "다대오(유다)",
    "timothy": "디모데",
    "zebulun": "스불론",
    "jonathan": "요나단",
    "abel": "아벨",
    "abihu": "아비후",
    "achan": "아간",
    "agrippa": "아그립바",
    "aquila": "아굴라",
    "cain": "가인",
    "caleb": "갈렙",
    "cornelius": "고넬료",
    "cyrus": "고레스",
    "delilah": "들릴라",
    "dinah": "디나",
    "eglon": "에글론",
    "ehud": "에훗",
    "eli": "엘리",
    "festus": "베스도",
    "goliath": "골리앗",
    "hannah": "한나",
    "herod": "헤롯",
    "jairus": "야이로",
    "jehoiachin": "여호야긴",
    "jehu": "예후",
    "jephthah": "입다",
    "jesse": "이새",
    "john_mark": "마가 요한",
    "john_the_baptist": "세례 요한",
    "josiah": "요시야",
    "korah": "고라",
    "lazarus": "나사로",
    "lydia": "루디아",
    "martha": "마르다",
    "mary_magdalene": "막달라 마리아",
    "melchizedek": "멜기세덱",
    "micah": "미가",
    "miriam": "미리암",
    "naaman": "나아만",
    "nadab": "나답",
    "phinehas": "비느하스",
    "pilate": "빌라도",
    "potiphar": "보디발",
    "samson": "삼손",
    "sapphira": "삽비라",
    "seth": "셋",
    "stephen": "스데반",
    "zechariah": "사가랴",
    "zedekiah": "시드기야",
}

AUTO_PROMPT_SOURCE = "auto_story_v2"
ACTIVE_DEFAULT_THRESHOLD = 2
GOD_NEGATIVE_PROMPT_EXTRA = (
    "symbol, emblem, icon, badge, seal, sigil, logo, crest, heraldic mark, "
    "religious symbol, abstract symbol, decorative motif, ornamental geometry, mandala, "
    "compass rose, trident-like symbol, monogram, glyph, letters, runes, "
    "secondary emblem, extra emblem, extra icon, detached symbol, lower symbol, "
    "bottom mark, floating mark below, small logo below, framed icon, geometric badge"
)
GABRIEL_NEGATIVE_PROMPT_EXTRA = (
    "ordinary human priest, ordinary human man, elderly man, beard, warrior, armor, "
    "multiple people, crowd, group, duo, pair, two people, extra character, background character, "
    "second angel, angel choir, heavenly host, attendants"
)
RUTH_NEGATIVE_PROMPT_EXTRA = (
    "male, man, masculine face, broad male jaw, beard, mustache, warrior, armor"
)
HAMAN_NEGATIVE_PROMPT_EXTRA = (
    "multiple people, crowd, group, duo, pair, two people, extra character, background character, "
    "king, queen, banquet crowd, attendants, throne scene"
)
DANIEL_NEGATIVE_PROMPT_EXTRA = "multiple people, crowd, group, duo, pair, two people, extra character, background character"
DAN_NEGATIVE_PROMPT_EXTRA = "multiple people, crowd, group, duo, pair, two people, extra character, background character"

# Codes that the model tends to draw as multiple/symbolic figures.
# Force them to render as exactly one solo character.
SOLO_NEGATIVE_PROMPT_EXTRA = (
    "multiple people, crowd, group, duo, pair, two people, extra character, "
    "background character, twin, mirrored figure, second character, secondary figure, "
    "scene with brother, scene with father, scene with attendants"
)
SOLO_FORCED_CODES = {"cyrus"}

# potiphar 는 solo 강제 + 헤브루 족장처럼 묘사되지 않도록 추가 차단.
POTIPHAR_NEGATIVE_PROMPT_EXTRA = (
    "multiple people, crowd, group, duo, pair, two people, extra character, "
    "background character, twin, mirrored figure, second character, "
    "Hebrew patriarch, Hebrew nomad, desert traveler robe, full-length flowing robe, "
    "long beard, wrapped turban, long staff, sandals only outfit, biblical patriarch costume"
)

# cain 은 형제 아벨/부모와 함께 그려지는 경향이 강해 강한 solo 차단 필요.
# 주의: 그림체가 다른 인물과 일치하도록 표현 묘사 단어는 가볍게 유지.
CAIN_NEGATIVE_PROMPT_EXTRA = (
    "multiple people, crowd, group, duo, pair, two people, three people, extra character, "
    "background character, twin, mirrored figure, second character, "
    "scene with brother, scene with sibling, brother nearby, abel, "
    "scene with parents, family scene, mother, father, child, "
    "shepherd staff, sheep, lamb, flock"
)

# achan 은 죄인/도둑 캐릭터라 영웅적/멋진 묘사를 차단해야 톤이 맞는다.
ACHAN_NEGATIVE_PROMPT_EXTRA = (
    "heroic posture, proud stance, noble bearing, kingly presence, regal aura, "
    "shining bright armor, polished cuirass, golden crown, royal robe, royal sash, "
    "elegant features, glamorous beautiful face, model-like proportions, idealized hero, "
    "warrior champion silhouette, victorious pose, raised sword pose, commander baton"
)

# delilah 가 자꾸 남성형으로 나와서 명시적 차단 필요.
DELILAH_NEGATIVE_PROMPT_EXTRA = (
    "male, man, masculine face, broad male jaw, square male shoulders, "
    "beard, mustache, facial hair, "
    "warrior, armor, soldier, samson, second character, multiple people, scene with samson"
)

# lydia 도 같은 이유로 여성형 강제. 빌립보 자색 옷감 장수.
LYDIA_NEGATIVE_PROMPT_EXTRA = (
    "male, man, masculine face, broad male jaw, square male shoulders, "
    "beard, mustache, facial hair, "
    "warrior, armor, soldier, slave, prisoner, jailer, second character, multiple people"
)

# mary_magdalene 도 자꾸 수염 있는 남성으로 그려져서 강한 여성 강제 필요.
MARY_MAGDALENE_NEGATIVE_PROMPT_EXTRA = (
    "male, man, masculine face, broad male jaw, square male shoulders, "
    "beard, mustache, facial hair, stubble, "
    "warrior, armor, disciple man, peter, paul, second character, multiple people, "
    "extra hands, three hands, multiple hands, extra arms, third arm, "
    "deformed hands, fused fingers, extra fingers, too many fingers, "
    "oil flask, alabaster jar, perfume bottle, ointment container, anointing vessel"
)

# naomi 는 노년 강제. 어린/청년 묘사 차단.
NAOMI_NEGATIVE_PROMPT_EXTRA = (
    "young woman, youthful face, smooth skin, child, teenager, glamorous beauty, "
    "model-like proportions, dark hair without gray, "
    "male, man, masculine face, broad male jaw, beard, mustache, "
    "second character, multiple people, scene with ruth"
)

GOLIATH_NEGATIVE_PROMPT_EXTRA = (
    "kind smile, friendly expression, gentle posture, peaceful aura, warm welcoming gesture, "
    "slim build, delicate features, child, teenager, slim shoulders, small stature, "
    "unarmed, empty hands"
)

FEMALE_CODES = {
    "bathsheba",
    "bilhah",
    "deborah",
    "delilah",
    "elizabeth",
    "esther",
    "eve",
    "hagar",
    "jezebel",
    "leah",
    "lydia",
    "martha",
    "mary",
    "mary_magdalene",
    "miriam",
    "naomi",
    "priscilla",
    "rachel",
    "rebekah",
    "ruth",
    "sarah",
}

ANGELIC_CODES = {
    "gabriel",
}

FACE_SHAPE_VARIANTS = [
    "square jaw with broad brow planes",
    "long wedge-shaped face",
    "hexagonal face with strong cheek angles",
    "diamond-shaped face with a sharp chin",
    "rectangular face with flat cheek planes",
    "soft angular oval face",
]

BODY_VARIANTS = [
    "lean traveler build",
    "compact sturdy build",
    "tall narrow build",
    "square-shouldered build",
    "broad stable build",
    "light agile build",
]

MALE_HAIR_VARIANTS = [
    "short blocky curls",
    "medium wavy hair in angular chunks",
    "straight shoulder-length hair with polygon strands",
    "closely cropped faceted hair",
    "wrapped geometric headcloth framing the face",
    "layered hood-like head covering",
]

FEMALE_HAIR_VARIANTS = [
    "wrapped angular headscarf",
    "shoulder-length straight hair in polygon sheets",
    "soft wavy bob with faceted planes",
    "braided geometric hair",
    "layered veil framing the face",
    "tucked-back long hair with blocky edges",
]

CHARACTER_VISUAL_OVERRIDES = {
    "esther": [
        "slender graceful build",
        "soft elegant oval face with refined feminine beauty",
        "long dark hair under a royal veil with geometric jewel accents",
    ],
    "eve": [
        "slender graceful build",
        "soft delicate face with gentle feminine features",
        "long flowing hair with soft faceted strands",
    ],
    "gabriel": [
        "tall luminous figure with graceful proportions",
        "smooth serene face with gentle heavenly features",
        "soft radiant hair framed by simple glowing planes",
    ],
    "rachel": [
        "slender graceful build",
        "soft luminous oval face with striking beautiful feminine features",
        "long dark hair under a graceful layered veil",
    ],
    "leah": [
        "modest average build",
        "soft plain oval face with simple gentle features",
        "dark hair tucked under a practical layered veil",
    ],
    "ruth": [
        "slender graceful build",
        "soft feminine oval face with gentle features",
        "soft layered veil framing the face",
    ],
    "goliath": [
        "towering oversized warrior build, clearly larger than other characters in the cast",
        "wide square jaw with strong heavy brow planes and deep-set narrow eyes",
        "short cropped dark hair under a polished bronze helmet with cheek plates",
    ],
    "potiphar": [
        "broad-shouldered authoritative ancient Egyptian officer build",
        "angular Egyptian profile with straight strong nose and clean shaven trimmed jaw",
        "kohl-lined dark eyes characteristic of ancient Egyptian art style",
        "short blunt black hair under a striped Egyptian nemes headcloth",
    ],
    "cain": [
        "lean compact farmer build",
        "long narrow face with sharp angular jaw and heavy brow",
        "medium-length dark hair pulled loosely back",
        "short trimmed beard",
    ],
    "naaman": [
        "tall straight-backed commander build with broad shoulders",
        "sharp angular face with strong straight nose and trimmed jawline",
        "short well-groomed dark hair and trimmed beard befitting an officer",
    ],
    "achan": [
        "lean ordinary build, no commanding presence",
        "narrow uneasy face with sunken anxious eyes",
        "tangled medium-length dark hair with plain look",
        "short scruffy uneven beard",
    ],
    "delilah": [
        "slender feminine build with soft graceful proportions",
        "soft elegant oval face with refined alluring feminine features",
        "long flowing wavy dark hair partly draped over one shoulder",
    ],
    "lydia": [
        "slender feminine build with poised graceful proportions",
        "soft elegant oval face with warm intelligent features",
        "long dark hair partly covered by a soft shawl or simple veil",
    ],
    "mary_magdalene": [
        "slender feminine build with graceful proportions",
        "soft oval face with gentle devout feminine features",
        "long dark hair partly covered by a soft head veil",
    ],
    "naomi": [
        "modest elderly feminine build with slightly stooped slim shoulders",
        "soft elderly face with kind weathered features and gentle wrinkles",
        "gray streaked hair tucked under a layered widow's veil",
    ],
}

CHARACTER_MOOD_OVERRIDES = {
    "esther": ["gentle confident smile and poised posture"],
    "eve": ["gentle relaxed posture"],
    "gabriel": ["gentle descending messenger posture"],
    "rachel": ["warm radiant smile and elegant tender posture"],
    "leah": ["quiet modest smile and gentle reserved posture"],
    "ruth": ["warm humble smile and gentle posture"],
    "goliath": [
        "menacing forward-leaning stance, intimidating fierce expression with stern brow",
    ],
    "potiphar": [
        "stern authoritative officer's posture with formal upright bearing, arms held with disciplined command",
    ],
    "cain": [
        "brooding upright posture with downcast resentful gaze",
    ],
    "naaman": [
        "proud upright commander's posture, chin held with disciplined dignity",
    ],
    "achan": [
        "shrinking nervous posture with shoulders hunched, guilty downcast expression",
    ],
    "delilah": [
        "alluring graceful posture with subtle sly smile, charming and confident",
    ],
    "lydia": [
        "warm welcoming posture with quiet faithful smile, dignified and gracious",
    ],
    "josiah": [
        "earnest determined royal posture, scroll held to the heart, devout reformer's bearing",
    ],
    "mary_magdalene": [
        "reverent devout posture with hopeful upward gaze, gentle hands clasped",
    ],
    "naomi": [
        "weathered patient posture, gentle wise expression of an older mother figure",
    ],
}

BEARD_VARIANTS = [
    "",
    "short angular beard",
    "trimmed faceted beard",
    "full blocky beard",
    "mustache with a short beard",
]

ERA_ROLE_FALLBACKS = {
    "primeval": "mythic early-world silhouette",
    "patriarch": "nomadic patriarch silhouette",
    "exodus_wilderness": "weathered desert-traveler silhouette",
    "judges": "rugged tribal-era silhouette",
    "monarchy": "structured royal-era silhouette",
    "prophets_exile": "solemn exile-era silhouette",
    "post_exile_return": "rebuilder-era silhouette",
    "gospels": "traveling teacher silhouette",
    "early_church": "mission-era silhouette",
}

CODE_SIGNATURE_HINTS = {
    "abraham": ["nomadic patriarch silhouette", "travel-worn layered robe"],
    "aaron": ["ceremonial leader silhouette", "priestly layered sash"],
    "daniel": [
        "court-wise exile silhouette",
        "calm dignified bearing",
        "rolled scroll accent",
    ],
    "david": [
        "shepherd-king silhouette",
        "bold agile bearing",
        "sling and small stone pouch",
    ],
    "elijah": ["storm-like prophet silhouette", "rough mantle energy"],
    "esther": [
        "beautiful queenly silhouette",
        "elegant regal beauty",
        "refined royal poise",
        "jeweled geometric crown band and rich royal robe accents",
    ],
    "gabriel": [
        "radiant angelic messenger silhouette",
        "single angel only",
        "soft luminous wings made of simple faceted shapes",
        "heavenly messenger presence with clean flowing robes",
    ],
    "eve": [
        "graceful first-woman silhouette",
        "warm gentle expression",
        "soft feminine presence",
    ],
    "ezra": [
        "scribe-teacher silhouette",
        "measured studious bearing",
        "rolled scroll accent",
    ],
    "jesus": [
        "calm teacher-and-healer silhouette",
        "deep red outer robe over a light inner tunic",
        "both arms gently opened outward in a welcoming gesture",
    ],
    "john": [
        "young fisherman-apostle turned reflective writer silhouette",
        "small net bundle and rolled scroll satchel",
        "quiet witness-like presence",
    ],
    "joseph": [
        "dream-marked survivor silhouette",
        "protected-yet-resilient bearing",
        "patterned robe accent",
    ],
    "mary": [
        "humble courageous mother silhouette",
        "calm grounded presence",
        "layered travel veil",
    ],
    "haman": [
        "scheming court-official silhouette",
        "sealed decree scroll and signet ring",
        "single arrogant court-villain presence",
    ],
    "moses": [
        "liberator silhouette shaped by wilderness",
        "steady leader's presence",
        "wooden staff",
    ],
    "nehemiah": [
        "wall-rebuilder silhouette",
        "focused civic resolve",
        "builder's belt with wooden tools",
    ],
    "noah": [
        "ark-builder silhouette",
        "weathered survivor presence",
        "builder's belt with wooden tools",
    ],
    "paul": [
        "road-worn missionary silhouette",
        "intense teacher's focus",
        "rolled scroll or letter satchel",
    ],
    "rachel": [
        "radiant beautiful beloved matriarch silhouette",
        "elegant luminous presence",
    ],
    "leah": [
        "plain modest matriarch silhouette",
        "simple gentle presence",
    ],
    "saul": [
        "first king silhouette",
        "simple geometric crown band or royal sash",
        "tall commanding presence",
    ],
    "peter": [
        "sturdy fisherman-apostle silhouette",
        "broad dependable presence",
        "shoulder-draped fishing net and rope details",
    ],
    "andrew": [
        "rope-belt fisherman-apostle silhouette",
        "hand net and rope-belt details",
        "weathered fisherman's focus",
    ],
    "james_zebedee": [
        "boat-working fisherman-apostle silhouette",
        "coiled rope, short oar, and fish basket",
        "bold energetic worker's presence",
    ],
    "philip": [
        "road-guide messenger disciple silhouette",
        "travel satchel and route scroll",
        "practical alert presence",
    ],
    "bartholomew": [
        "scripture scholar disciple silhouette",
        "scroll bundle held like a student",
        "measured thoughtful presence",
    ],
    "matthew": [
        "tax-collector record-keeper disciple silhouette",
        "coin pouch, wax tablet, and stylus",
        "precise record-keeper presence",
    ],
    "thomas": [
        "builder-craftsman disciple silhouette",
        "measuring cord and carpenter tool pouch",
        "solid thoughtful presence",
    ],
    "james_alphaeus": [
        "village artisan disciple silhouette",
        "simple work sash and cloth tool wrap",
        "quiet steady presence",
    ],
    "thaddaeus": [
        "courier-messenger disciple silhouette",
        "letter satchel with a sealed scroll",
        "warm approachable presence",
    ],
    "simon_zealot": [
        "zealot organizer disciple silhouette",
        "belted travel cloak with gathered folds",
        "lean vigilant presence",
    ],
    "judas": [
        "treasurer disciple silhouette",
        "money pouch and small account bag",
        "guarded calculating presence",
    ],
    "ruth": [
        "beautiful loyal field-worker silhouette",
        "gentle resilient presence",
        "gathered grain bundle accent",
    ],
    "samuel": ["listening prophet silhouette", "quiet spiritual alertness"],
    "solomon": [
        "wise royal silhouette",
        "measured judicial calm",
        "simple geometric crown band or royal sash",
    ],
    "goliath": [
        "towering Philistine giant warrior silhouette",
        "thick bronze scale armor over a heavy padded tunic, bronze greaves on shins",
        "massive oversized iron sword held high in one hand",
        "large rectangular shield slung at the back",
        "imposing intimidating presence with heavy brow",
    ],
    "potiphar": [
        "ancient Egyptian captain of Pharaoh's guard silhouette",
        "white linen wrapped kilt (shendyt) with broad gold-banded usekh collar over bare chest",
        "wide leather officer's belt with a bronze short sword (khopesh) at the hip",
        "striped Egyptian nemes headcloth or short blunt black wig framing the face",
        "stern disciplined officer presence, distinctly Egyptian rather than Hebrew nomad",
    ],
    "cain": [
        "first farmer silhouette from the primeval era",
        "simple sleeveless tunic in earthy tones, bare arms",
        "wooden farming implement in one hand: simple short hoe or hand sickle",
        "subtle small dark mark on the forehead (mark of Cain)",
        "brooding exiled wanderer presence",
    ],
    "naaman": [
        "Aramean (Syrian) army commander silhouette from the divided-kingdom era",
        "polished bronze scale armor cuirass over a tunic, decorative shoulder plates",
        "richly trimmed military cloak fastened at one shoulder",
        "short bronze sword at the belt and a small commander's baton in one hand",
        "proud authoritative officer presence, distinctly a general not a priest",
    ],
    "achan": [
        "guilty Israelite soldier silhouette caught in shame",
        "plain dusty Israelite tunic and simple leather belt, no special armor",
        "one hand clutching a hidden cloth bundle (stolen spoils) close to the chest",
        "furtive uneasy stance with downcast nervous eyes",
        "ordinary plain look, not heroic",
    ],
    "delilah": [
        "Philistine seductress silhouette from the era of judges, distinctly female",
        "richly draped long dress with decorative jeweled neckline and waist sash",
        "subtle gold ornaments and bangles, distinctly Philistine cultural look",
        "alluring captivating presence, distinctly feminine",
    ],
    "lydia": [
        "Greco-Roman era merchant woman silhouette, distinctly female",
        "rich purple dyed long dress with neat sash, modest gold ornaments at neckline",
        "small bolt of purple cloth tucked under one arm (purple-cloth dealer)",
        "dignified faithful host presence",
    ],
    "josiah": [
        "young righteous king of Judah silhouette, devout reformer",
        "geometric royal crown band on the head and embroidered royal robe with sash",
        "rolled scroll of the Law held close to the chest with one hand",
        "earnest reverent royal presence",
    ],
    "mary_magdalene": [
        "devout female disciple silhouette from the gospels era, distinctly female",
        "long modest robe in cream and soft rose with gentle layered shawl",
        "hands gently clasped at chest level, clearly two hands total and no object in hand",
        "reverent resurrection-witness presence at dawn",
    ],
    "naomi": [
        "elderly Moabite-returning widow silhouette, distinctly older woman",
        "long modest layered widow's robe in earthen tones with simple sash",
        "soft layered head veil framing a kind aged face",
        "patient wise matriarch presence, distinctly elderly not young",
    ],
}

STORY_ROLE_RULES = [
    {
        "phrase": "shepherd-inspired outdoor silhouette",
        "patterns": ["목자", "양떼", "들판", "초장", "목동", "양을 치"],
    },
    {
        "phrase": "fisherman-apostle silhouette with rope-belt layers",
        "patterns": ["그물", "어부", "바다", "갈릴리", "고기잡", "배를 타"],
    },
    {
        "phrase": "weathered desert-leader silhouette",
        "patterns": ["광야", "출애굽", "홍해", "떨기나무", "시내산", "재앙"],
    },
    {
        "phrase": "regal angular silhouette",
        "patterns": ["왕위", "궁전", "왕비", "보좌", "즉위", "왕이 되"],
    },
    {
        "phrase": "prophetic visionary silhouette",
        "patterns": ["선지", "예언", "환상", "계시", "하늘이 열리", "말씀이 임"],
    },
    {
        "phrase": "ceremonial temple-robe silhouette",
        "patterns": ["제사장", "성전", "제단", "향", "언약궤"],
    },
    {
        "phrase": "sturdy rebuilder silhouette",
        "patterns": ["성벽", "재건", "귀환", "문을 세우", "돌을 쌓"],
    },
    {
        "phrase": "road-worn traveler silhouette",
        "patterns": ["선교", "여행", "항해", "파송", "도시", "로마", "길을 떠"],
    },
    {
        "phrase": "protective caregiver silhouette",
        "patterns": ["아기", "어머니", "품에 안", "태어나", "낳", "피신"],
    },
    {
        "phrase": "bold warrior silhouette",
        "patterns": ["전쟁", "군대", "용사", "싸우", "거인", "무장"],
    },
    {
        "phrase": "dream-marked survivor silhouette",
        "patterns": ["꿈", "구덩이", "감옥", "누명", "해석"],
    },
]

STORY_PROP_RULES = [
    {
        "phrase": "wooden staff",
        "patterns": ["지팡이", "막대기", "홍해", "떨기나무", "시내산"],
    },
    {
        "phrase": "rolled scroll or letter satchel",
        "patterns": [
            "두루마리",
            "편지",
            "율법",
            "설교",
            "가르치",
            "회당",
            "서신",
            "계시",
        ],
    },
    {
        "phrase": "sling and small stone pouch",
        "patterns": ["물매", "거인", "시냇가", "골리앗"],
    },
    {
        "phrase": "simple geometric crown band or royal sash",
        "patterns": ["왕위", "왕비", "보좌", "즉위", "왕관"],
    },
    {
        "phrase": "net weights and rope details",
        "patterns": ["그물", "어부", "바다", "고기잡", "배를 타"],
    },
    {
        "phrase": "oil-flask accent",
        "patterns": ["기름", "향유", "단지", "항아리"],
    },
    {
        "phrase": "builder's belt with wooden tools",
        "patterns": ["성벽", "건축", "방주", "재건", "목수"],
    },
]

STORY_MOOD_RULES = [
    {
        "phrase": "brave forward-leaning stance",
        "patterns": ["믿음", "담대", "맞서", "용기", "담대히"],
    },
    {
        "phrase": "open-handed compassionate posture",
        "patterns": ["치유", "고치", "불쌍히", "위로", "눈물"],
    },
    {
        "phrase": "thoughtful calm expression",
        "patterns": ["기도", "묵상", "환상", "계시", "지혜", "생각"],
    },
    {
        "phrase": "light celebratory posture",
        "patterns": ["기쁨", "찬양", "춤", "감사", "축제"],
    },
    {
        "phrase": "resolute steady posture",
        "patterns": ["순종", "떠나라", "파송", "견디", "도망", "회개"],
    },
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build character meta JSON (codes, names, avatar prompts) from assets/200_stories data."
    )
    parser.add_argument(
        "--stories-dir",
        default="assets/200_stories",
        help="Directory containing 200 story JSON files.",
    )
    parser.add_argument(
        "--base-meta-json",
        default="tools/seed/person_meta_51.json",
        help="Deprecated. Ignored (kept only for CLI backward compatibility).",
    )
    parser.add_argument(
        "--output",
        default="tools/seed/character_meta.json",
        help="Output character meta JSON path.",
    )
    parser.add_argument(
        "--min-mentions",
        type=int,
        default=1,
        help=(
            "Minimum mention count to include. Defaults to 1 so every "
            "individual character is generated; runtime visibility is controlled "
            "by characters.is_active in the database."
        ),
    )
    parser.add_argument(
        "--active-threshold",
        type=int,
        default=ACTIVE_DEFAULT_THRESHOLD,
        help=(
            "Mention count at or above which is_active_default=true. "
            "Below this threshold, is_active_default=false (admin opts in)."
        ),
    )
    return parser.parse_args()


def parse_event_number(raw_title: str) -> int:
    match = EVENT_NO_RE.match(raw_title.strip())
    if match is None:
        raise ValueError(f"Title does not start with 3-digit index: {raw_title!r}")
    return int(match.group(1))


def load_story_rows(stories_dir: Path) -> list[dict[str, Any]]:
    if not stories_dir.exists():
        raise FileNotFoundError(f"Stories dir not found: {stories_dir}")
    rows: list[dict[str, Any]] = []
    for path in sorted(stories_dir.glob("*.json"), key=lambda p: p.name):
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise ValueError(f"JSON root must be a list: {path}")
        for item in data:
            if not isinstance(item, dict):
                raise ValueError(f"Story row must be object in {path}: {item!r}")
            rows.append(item)
    rows.sort(key=lambda row: parse_event_number(str(row.get("title", ""))))
    return rows


def dedupe_preserve_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def expand_person_codes(number: int, characters: list[str]) -> list[str]:
    expanded: list[str] = []
    persons_set = {code for code in characters}
    for code in characters:
        if code == "disciples":
            if "judas" in persons_set or number >= 175:
                expanded.extend(DISCIPLES_NO_JUDAS)
            else:
                expanded.extend(DISCIPLES_WITH_JUDAS)
            continue
        if code == "apostles":
            expanded.extend(APOSTLES_AFTER_MATTHIAS)
            continue
        if code == "brothers":
            if number in {38, 43, 44, 45}:
                expanded.extend(BROTHERS_WITHOUT_BENJAMIN)
            else:
                expanded.extend(BROTHERS_ALL)
            continue
        expanded.append(code)
    return dedupe_preserve_order(expanded)


def is_individual_code(code: str) -> bool:
    if code in NON_INDIVIDUAL_CODES:
        return False
    if code in ROSTER_EXCLUDED_CODES:
        return False
    if not code:
        return False
    return True


def normalize_style_era(era: str) -> str:
    raw = era.strip()
    if raw in {
        "primeval",
        "patriarch",
        "exodus_wilderness",
        "judges",
        "monarchy",
        "prophets_exile",
        "post_exile_return",
        "gospels",
        "early_church",
    }:
        return raw
    return ERA_CODE_TO_STYLE.get(raw, "patriarch")


def prettify_name_en(code: str) -> str:
    return " ".join(part.capitalize() for part in code.split("_") if part)


def has_hangul(text: str) -> bool:
    return any("가" <= ch <= "힣" for ch in text)


def stable_pick(code: str, salt: str, options: list[str]) -> str:
    if not options:
        return ""
    token = f"{salt}:{code}"
    score = sum((idx + 1) * ord(ch) for idx, ch in enumerate(token))
    return options[score % len(options)]


def build_story_text(rows: list[dict[str, Any]]) -> str:
    parts: list[str] = []
    for row in rows:
        for key in ("title", "summary"):
            value = str(row.get(key, "")).strip()
            if value:
                parts.append(value)
        for scene in row.get("story_scenes", []):
            value = str(scene).strip()
            if value:
                parts.append(value)
    return " ".join(parts).lower()


def count_pattern_hits(text: str, patterns: list[str]) -> int:
    return sum(text.count(pattern.lower()) for pattern in patterns if pattern)


def select_story_fragments(
    text: str, rules: list[dict[str, Any]], *, limit: int
) -> list[str]:
    scored: list[tuple[int, int, str]] = []
    for idx, rule in enumerate(rules):
        phrase = str(rule.get("phrase", "")).strip()
        patterns = [str(pattern).strip() for pattern in rule.get("patterns", [])]
        score = count_pattern_hits(text, patterns)
        if phrase and score > 0:
            scored.append((-score, idx, phrase))
    scored.sort()
    return [phrase for _, _, phrase in scored[:limit]]


def build_story_prompt_fragments(
    code: str,
    era_style: str,
    story_rows: list[dict[str, Any]],
) -> list[str]:
    text = build_story_text(story_rows)
    code_hints = CODE_SIGNATURE_HINTS.get(code, [])
    role_fragments = (
        []
        if code_hints
        else select_story_fragments(
            text,
            STORY_ROLE_RULES,
            limit=1,
        )
    )
    prop_fragments = (
        [] if code_hints else select_story_fragments(text, STORY_PROP_RULES, limit=1)
    )
    if code in CHARACTER_MOOD_OVERRIDES:
        mood_fragments = CHARACTER_MOOD_OVERRIDES[code]
    else:
        mood_fragments = select_story_fragments(text, STORY_MOOD_RULES, limit=1)

    fragments: list[str] = []
    fragments.extend(code_hints)
    if role_fragments:
        fragments.extend(role_fragments)
    elif not code_hints:
        fragments.append(
            ERA_ROLE_FALLBACKS.get(era_style, ERA_ROLE_FALLBACKS["patriarch"])
        )
    fragments.extend(prop_fragments)
    fragments.extend(mood_fragments)
    return dedupe_preserve_order([fragment for fragment in fragments if fragment])


def build_visual_variation_fragments(code: str) -> list[str]:
    if code in CHARACTER_VISUAL_OVERRIDES:
        return dedupe_preserve_order(
            [fragment for fragment in CHARACTER_VISUAL_OVERRIDES[code] if fragment]
        )

    hair_variants = FEMALE_HAIR_VARIANTS if code in FEMALE_CODES else MALE_HAIR_VARIANTS
    fragments = [
        stable_pick(code, "body", BODY_VARIANTS),
        stable_pick(code, "face", FACE_SHAPE_VARIANTS),
        stable_pick(code, "hair", hair_variants),
    ]
    if code not in FEMALE_CODES:
        beard = stable_pick(code, "beard", BEARD_VARIANTS)
        if beard:
            fragments.append(beard)
    return dedupe_preserve_order([fragment for fragment in fragments if fragment])


def build_character_prompt(
    code: str,
    name_en: str,
    palette_text: str,
    era_style: str,
    story_rows: list[dict[str, Any]],
) -> str:
    if code in ANGELIC_CODES:
        identity_text = "angelic heavenly messenger"
    else:
        identity_text = (
            "adult biblical woman (age 25+)"
            if code in FEMALE_CODES
            else "adult biblical man (age 25+)"
        )
    prompt_parts = [
        "COMMON_STYLE",
        f"palette: {palette_text}",
        name_en,
        identity_text,
        *build_story_prompt_fragments(
            code=code, era_style=era_style, story_rows=story_rows
        ),
        *build_visual_variation_fragments(code=code),
        "ancient Near Eastern inspired clothing",
        "clean iconic silhouette",
        "distinctive story-driven accessory",
        "single character only",
        "no other people",
        "full body visible head to toe",
    ]
    return ", ".join(part for part in prompt_parts if part)


def build_god_prompt(palette_text: str) -> str:
    return (
        f"palette: {palette_text}, simple faceted form of light in the same blocky low-poly "
        "biblical illustration style as the cast, "
        "just a soft glowing light shape, not a symbol, not an emblem, not an icon, "
        "one centered light form only, simple vertical tapered silhouette made of a few large "
        "geometric planes, flat matte vector shading with subtle faceted edges, "
        "gentle warm glow, a few short attached glow rays only, large clean empty white space around it, "
        "plain white background, minimal clean composition, "
        "no character, no human figure, no face, no eyes, no mouth, no hands, no body, "
        "no wings, no sun disk, no text, no letters, no ornament, no decorative symmetry, "
        "sacred non-anthropomorphic presence"
    )


def load_prompt_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def has_style_keys(data: dict[str, Any]) -> bool:
    return all(
        key in data
        for key in [
            "common_style",
            "negative_prompt",
            "palettes",
            "generation_defaults",
        ]
    )


def should_reuse_style_source(data: dict[str, Any]) -> bool:
    meta = data.get("meta", {})
    if not isinstance(meta, dict):
        return False
    return str(meta.get("style_source", "")).strip().lower() == "manual"


def build_template_map(*json_paths: Path) -> dict[str, dict[str, Any]]:
    templates: dict[str, dict[str, Any]] = {}
    for path in json_paths:
        if not path.exists():
            continue
        data = load_prompt_json(path)
        for character in data.get("characters", []):
            if not isinstance(character, dict):
                continue
            code = str(character.get("code", "")).strip()
            if not code:
                continue
            if code in templates:
                continue
            templates[code] = character
    return templates


def build_person_meta(
    rows: list[dict[str, Any]],
    style_source: dict[str, Any],
    template_map: dict[str, dict[str, Any]],
    min_mentions: int,
    active_threshold: int,
) -> dict[str, Any]:
    mention_counts: Counter[str] = Counter()
    era_votes: dict[str, Counter[str]] = defaultdict(Counter)
    story_profiles: dict[str, dict[str, list[dict[str, Any]]]] = defaultdict(
        lambda: defaultdict(list)
    )

    for row in rows:
        number = parse_event_number(str(row.get("title", "")))
        era_style = normalize_style_era(str(row.get("era", "")))
        raw_persons = [
            str(code).strip() for code in row.get("characters", []) if str(code).strip()
        ]
        characters = expand_person_codes(number, raw_persons)
        for code in characters:
            if not is_individual_code(code):
                continue
            mention_counts[code] += 1
            era_votes[code][era_style] += 1
            story_profiles[code][era_style].append(row)

    selected_codes = sorted(
        [code for code, count in mention_counts.items() if count >= min_mentions],
        key=lambda code: (-mention_counts[code], code),
    )

    palettes = style_source["palettes"]
    default_style = "patriarch"

    characters: list[dict[str, Any]] = []
    for idx, code in enumerate(selected_codes, start=1):
        template = template_map.get(code, {})

        voted_style = default_style
        if era_votes.get(code):
            voted_style = sorted(
                era_votes[code].items(), key=lambda item: (-item[1], item[0])
            )[0][0]

        era_style = normalize_style_era(str(template.get("era", voted_style)))
        if era_style not in palettes:
            era_style = voted_style if voted_style in palettes else default_style

        name_en = str(template.get("name_en", "")).strip() or prettify_name_en(code)
        template_name_ko = str(template.get("name_ko", "")).strip()
        if has_hangul(template_name_ko):
            name_ko = template_name_ko
        elif code in KO_NAME_OVERRIDES:
            name_ko = KO_NAME_OVERRIDES[code]
        elif template_name_ko:
            name_ko = template_name_ko
        else:
            name_ko = name_en

        palette_text = str(palettes.get(era_style, palettes[default_style]))
        template_prompt_source = str(template.get("prompt_source", "")).strip().lower()
        prompt = ""
        if template_prompt_source == "manual":
            prompt = str(template.get("prompt", "")).strip()
        use_common_style = bool(template.get("use_common_style", True))
        disable_adult_guardrail = bool(template.get("disable_adult_guardrail", False))
        person_generation = str(template.get("person_generation", "")).strip()
        prompt_source = (
            template_prompt_source
            if template_prompt_source == "manual"
            else AUTO_PROMPT_SOURCE
        )

        story_rows = list(story_profiles.get(code, {}).get(era_style, []))
        if not story_rows:
            story_rows = [
                row
                for rows_by_era in story_profiles.get(code, {}).values()
                for row in rows_by_era
            ]

        if code == "god":
            prompt = build_god_prompt(palette_text=palette_text)
            use_common_style = False
            disable_adult_guardrail = True
            person_generation = "dont_allow"
            prompt_source = AUTO_PROMPT_SOURCE

        if not prompt:
            prompt = build_character_prompt(
                code=code,
                name_en=name_en,
                palette_text=palette_text,
                era_style=era_style,
                story_rows=story_rows,
            )

        character = {
            "index": idx,
            "code": code,
            "name_ko": name_ko,
            "name_en": name_en,
            "era": era_style,
            "prompt": prompt,
            "prompt_source": prompt_source,
            "mention_count": mention_counts[code],
            "is_active_default": mention_counts[code] >= active_threshold,
        }
        if not use_common_style:
            character["use_common_style"] = False
        if disable_adult_guardrail:
            character["disable_adult_guardrail"] = True
        if person_generation:
            character["person_generation"] = person_generation
        if code == "god":
            character["negative_prompt_extra"] = GOD_NEGATIVE_PROMPT_EXTRA
        if code == "gabriel":
            character["negative_prompt_extra"] = GABRIEL_NEGATIVE_PROMPT_EXTRA
        if code == "haman":
            character["negative_prompt_extra"] = HAMAN_NEGATIVE_PROMPT_EXTRA
        if code == "daniel":
            character["negative_prompt_extra"] = DANIEL_NEGATIVE_PROMPT_EXTRA
        if code == "ruth":
            character["negative_prompt_extra"] = RUTH_NEGATIVE_PROMPT_EXTRA
        if code == "goliath":
            character["negative_prompt_extra"] = GOLIATH_NEGATIVE_PROMPT_EXTRA
        if code == "potiphar":
            character["negative_prompt_extra"] = POTIPHAR_NEGATIVE_PROMPT_EXTRA
        if code == "cain":
            character["negative_prompt_extra"] = CAIN_NEGATIVE_PROMPT_EXTRA
        if code == "achan":
            character["negative_prompt_extra"] = ACHAN_NEGATIVE_PROMPT_EXTRA
        if code == "delilah":
            character["negative_prompt_extra"] = DELILAH_NEGATIVE_PROMPT_EXTRA
        if code == "lydia":
            character["negative_prompt_extra"] = LYDIA_NEGATIVE_PROMPT_EXTRA
        if code == "mary_magdalene":
            character["negative_prompt_extra"] = MARY_MAGDALENE_NEGATIVE_PROMPT_EXTRA
        if code == "naomi":
            character["negative_prompt_extra"] = NAOMI_NEGATIVE_PROMPT_EXTRA
        if code in SOLO_FORCED_CODES:
            character["negative_prompt_extra"] = SOLO_NEGATIVE_PROMPT_EXTRA
        characters.append(character)

    output = {
        "meta": {
            "title": "Bible avatar prompts (all individuals from 200 stories)",
            "version": "3.0",
            "count": len(characters),
            "style_source": AUTO_PROMPT_SOURCE,
            "active_threshold": active_threshold,
            "note": (
                "Generated from assets/200_stories with "
                "disciples/apostles/brothers expanded to individuals. "
                f"All characters with mention_count >= {min_mentions} are emitted; "
                f"is_active_default=true when mention_count >= {active_threshold}. "
                "Runtime visibility is controlled by characters.is_active in DB."
            ),
        },
        "common_style": style_source["common_style"],
        "negative_prompt": style_source["negative_prompt"],
        "palettes": style_source["palettes"],
        "generation_defaults": style_source["generation_defaults"],
        "characters": characters,
    }
    return output


def main() -> int:
    args = parse_args()
    stories_dir = Path(args.stories_dir)
    output_path = Path(args.output)

    template_paths: list[Path] = []
    if output_path.exists():
        template_paths.append(output_path)

    style_source: dict[str, Any] = DEFAULT_STYLE_SOURCE
    style_source_path = "<built-in defaults>"
    for path in template_paths:
        data = load_prompt_json(path)
        if has_style_keys(data) and should_reuse_style_source(data):
            style_source = data
            style_source_path = str(path)
            break

    rows = load_story_rows(stories_dir)
    template_map = build_template_map(*template_paths)

    output = build_person_meta(
        rows=rows,
        style_source=style_source,
        template_map=template_map,
        min_mentions=max(1, int(args.min_mentions)),
        active_threshold=max(1, int(args.active_threshold)),
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(f"stories dir   : {stories_dir}")
    print(f"template base : {style_source_path}")
    print(f"output        : {output_path}")
    print(f"count         : {output['meta']['count']}")
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
