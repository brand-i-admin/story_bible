#!/usr/bin/env python3
"""Build tools/seed/character_meta.json from assets/events JSON files.

Rules:
- Expand group codes: disciples/apostles/brothers -> individual character codes.
- Remove non-individual codes (groups/placeholders like mysterious_man, babel_people).
- Include EVERY individual character, regardless of mention_count.
  Visibility in the app is controlled at runtime by ``characters.is_active``.
- Each character carries an ``is_active_default`` hint for the characters-seed
  builder: people with mention_count >= ACTIVE_DEFAULT_THRESHOLD start
  active; Judges-era story characters also start active even with one
  appearance because their era is built around short one-off judges.
- Reuse existing prompt metadata only when prompt_source=manual.
- If no manual style exists, use built-in default style/palette config.
- Include curated avatar-only roster entries for planned story characters whose
  events are not written yet, so their avatars can be generated first.
- Include UI-only avatar assets such as ``guide`` for reusable app guidance
  without inserting them into the runtime ``characters`` table.
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
        "rich deep color blocks, medium-to-strong saturation, clear value contrast, "
        "not pale, not faded, not washed out, "
        "natural stylized full-body adult proportions, head about one-fifth to one-sixth of total height, "
        "head clearly smaller than torso, torso and legs longer than head, "
        "same natural body ratio template across all human characters, compact adult proportions, not chibi, "
        "simple small eyes and nose, mature friendly expression, "
        "no visible outline, no ink contour, no dark stroke, edges defined only by adjacent flat color planes, "
        "exactly one character only, solo single subject, "
        "small full-body avatar with generous white margin around the entire figure, "
        "entire body visible from top of head to soles of sandals, both full feet and sandals clearly visible, "
        "whole figure fits inside frame with no cropping at the head, hands, robe hem, legs, feet, or staff, "
        "centered inside a square 1:1 avatar canvas, plain white background, "
        "high resolution, consistent design system across the full cast, "
        "distinct silhouette and face geometry for each character, "
        "distinct hairstyle and story-inspired accessory for each character, "
        "no text, no watermark"
    ),
    "negative_prompt": (
        "realistic, photoreal, anime, manga, glossy 3D render, clay, pixel art, "
        "chibi, super-deformed, giant head, large head, huge face, bobblehead, baby proportions, oversized eyes, "
        "long legs, short legs, tiny torso, oversized torso, tiny body, stretched body, "
        "uneven body ratio, inconsistent body proportions, head larger than torso, head one-third of body height, "
        "face fills frame, legs longer than torso, "
        "pale colors, washed-out colors, faded pastel look, overexposed, low contrast, weak color, transparent-looking color, "
        "same-face clones, duplicate character, multiple people, crowd, group shot, "
        "companions, side characters, extra faces, extra bodies, twin, mirrored figure, "
        "close-up, portrait crop, bust shot, half body, cropped head, cropped feet, "
        "waist-up, upper body only, torso crop, knees cropped, robe hem cropped, bottom cropped, "
        "missing legs, missing feet, missing sandals, cut off toes, zoomed-in character, fills entire frame, "
        "marshmallow body, gritty, dark, horror, black outline, dark outline, "
        "heavy outline, thick outline, ink line, line art, comic ink, contour line, "
        "stroke, bold stroke, sticker outline, cel-shaded contour lines, "
        "complex background, text, logo, watermark"
    ),
    "palettes": {
        "primeval": "soft beige + olive + sky blue accents",
        "patriarch": "warm sand + cream + muted teal accents",
        "exodus_wilderness": "teal + desert tan + bronze accents",
        "judges": "olive green + clay brown + muted gold accents",
        "monarchy": "royal purple + navy + muted gold accents",
        "divided_kingdom": "royal purple + navy + muted gold accents",
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
    "era_divided_kingdom": "divided_kingdom",
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
    "joseph_nazareth": "요셉(예수의 양아버지)",
    "jacob": "야곱",
    "abraham": "아브라함",
    "philip": "빌립",
    "philip_evangelist": "전도자 빌립",
    "andrew": "안드레",
    "david": "다윗",
    "matthew": "마태",
    "thomas": "도마",
    "saul": "사울",
    "joshua": "여호수아",
    "judas": "유다",
    "sarah": "사라",
    "aaron": "아론",
    "bathsheba": "밧세바",
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
    "deborah": "드보라",
    "eve": "하와",
    "james": "야고보",
    "lot": "롯",
    "noah": "노아",
    "rachel": "라헬",
    "ruth": "룻",
    "rahab": "라합",
    "abimelech": "아비멜렉",
    "ahaz": "아하스",
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
    "haggai": "학개",
    "hezekiah": "히스기야",
    "hoshea_king": "호세아 왕",
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
    "jonah": "요나",
    "jonathan": "요나단",
    "absalom": "압살롬",
    "abel": "아벨",
    "abihu": "아비후",
    "ahijah": "아히야",
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
    "elon": "엘론",
    "festus": "베스도",
    "goliath": "골리앗",
    "hannah": "한나",
    "herod": "헤롯",
    "jairus": "야이로",
    "jezebel": "이세벨",
    "jehoiachin": "여호야긴",
    "jehoiakim": "여호야김",
    "jehu": "예후",
    "jephthah": "입다",
    "jeroboam": "여로보암",
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
    "micaiah": "미가야",
    "miriam": "미리암",
    "naaman": "나아만",
    "nadab": "나답",
    "phinehas": "비느하스",
    "pilate": "빌라도",
    "potiphar": "보디발",
    "priscilla": "브리스길라",
    "rehoboam": "르호보암",
    "samson": "삼손",
    "sapphira": "삽비라",
    "seth": "셋",
    "shadrach": "사드락",
    "meshach": "메삭",
    "abednego": "아벳느고",
    "stephen": "스데반",
    "zechariah": "사가랴",
    "zechariah_prophet": "스가랴(선지자)",
    "zedekiah": "시드기야",
    "zerubbabel": "스룹바벨",
    "abdon": "압돈",
    "ibzan": "입산",
    "jair": "야일",
    "othniel": "옷니엘",
    "shamgar": "삼갈",
    "tola": "돌라",
}

EN_NAME_OVERRIDES = {
    "ahijah": "Ahijah the Shilonite",
    "hoshea_king": "Hoshea, Last King of Northern Israel",
    "jezebel": "Jezebel, Queen of Northern Israel",
}

AUTO_PROMPT_SOURCE = "auto_story_v2"
ACTIVE_DEFAULT_THRESHOLD = 2
FORCE_ACTIVE_DEFAULT_CODES = {
    "absalom",
    "abel",
    "achan",
    "ahaz",
    "caleb",
    "cain",
    "cornelius",
    "goliath",
    "haggai",
    "hoshea_king",
    "jairus",
    "jeroboam",
    "jehoiakim",
    "jesse",
    "jonah",
    "jonathan",
    "josiah",
    "korah",
    "lydia",
    "matthias",
    "micaiah",
    "naaman",
    "phinehas",
    "pilate",
    "potiphar",
    "rahab",
    "rehoboam",
    "stephen",
    "zechariah",
    "zechariah_prophet",
    "zedekiah",
    "zerubbabel",
}
FORCE_INACTIVE_DEFAULT_CODES = {"elizabeth", "gabriel", "god"}
FORCE_AUTO_PROMPT_CODES = {"elijah", "hezekiah", "saul", "solomon"}

# Characters can be prepared for avatar generation before their story events are
# added. They remain inactive in DB seed output until story appearances, admin
# activation, or an explicit FORCE_ACTIVE_DEFAULT_CODES override makes them visible.
CURATED_AVATAR_ROSTER: dict[str, dict[str, Any]] = {
    "ahaz": {
        "name_ko": "아하스",
        "name_en": "Ahaz",
        "era": "monarchy",
        "style_reference_codes": ["rehoboam", "hezekiah", "josiah"],
    },
    "absalom": {
        "name_ko": "압살롬",
        "name_en": "Absalom",
        "era": "monarchy",
        "style_reference_codes": ["david", "solomon", "saul"],
    },
    "jeroboam": {
        "name_ko": "여로보암",
        "name_en": "Jeroboam",
        "era": "monarchy",
        "style_reference_codes": ["solomon", "saul", "david"],
    },
    "rehoboam": {
        "name_ko": "르호보암",
        "name_en": "Rehoboam",
        "era": "monarchy",
        "style_reference_codes": ["solomon", "david", "saul"],
    },
    "jonah": {
        "name_ko": "요나",
        "name_en": "Jonah",
        "era": "divided_kingdom",
        "style_reference_codes": ["elijah", "elisha", "isaiah"],
    },
    "micaiah": {
        "name_ko": "미가야",
        "name_en": "Micaiah son of Imlah",
        "era": "divided_kingdom",
        "style_reference_codes": ["elijah", "elisha", "isaiah"],
    },
    "jeremiah": {
        "name_ko": "예레미야",
        "name_en": "Jeremiah",
        "era": "monarchy",
        "style_reference_codes": ["isaiah", "ezekiel", "ezra"],
    },
    "jezebel": {
        "name_ko": "이세벨",
        "name_en": "Jezebel, Queen of Northern Israel",
        "era": "divided_kingdom",
        "style_reference_codes": ["esther", "athaliah", "ahab"],
    },
    "jehoiakim": {
        "name_ko": "여호야김",
        "name_en": "Jehoiakim",
        "era": "monarchy",
        "style_reference_codes": ["josiah", "ahaz", "zedekiah"],
    },
    "othniel": {
        "name_ko": "옷니엘",
        "name_en": "Othniel",
        "era": "judges",
        "style_reference_codes": ["gideon", "joshua", "samson"],
    },
    "ehud": {
        "name_ko": "에훗",
        "name_en": "Ehud",
        "era": "judges",
        "style_reference_codes": ["gideon"],
    },
    "shamgar": {
        "name_ko": "삼갈",
        "name_en": "Shamgar",
        "era": "judges",
        "style_reference_codes": ["gideon", "joshua", "samson"],
    },
    "deborah": {
        "name_ko": "드보라",
        "name_en": "Deborah",
        "era": "judges",
        "style_reference_codes": ["ruth", "esther", "mary"],
    },
    "tola": {
        "name_ko": "돌라",
        "name_en": "Tola",
        "era": "judges",
        "style_reference_codes": ["gideon", "joshua", "samson"],
    },
    "jair": {
        "name_ko": "야일",
        "name_en": "Jair",
        "era": "judges",
        "style_reference_codes": ["gideon", "joshua", "samson"],
    },
    "jephthah": {
        "name_ko": "입다",
        "name_en": "Jephthah",
        "era": "judges",
        "style_reference_codes": ["gideon", "joshua", "samson"],
    },
    "ibzan": {
        "name_ko": "입산",
        "name_en": "Ibzan",
        "era": "judges",
        "style_reference_codes": ["gideon", "joshua", "samson"],
    },
    "elon": {
        "name_ko": "엘론",
        "name_en": "Elon",
        "era": "judges",
        "style_reference_codes": ["gideon", "joshua", "samson"],
    },
    "abdon": {
        "name_ko": "압돈",
        "name_en": "Abdon",
        "era": "judges",
        "style_reference_codes": ["gideon", "joshua", "samson"],
    },
    "samson": {
        "name_ko": "삼손",
        "name_en": "Samson",
        "era": "judges",
        "style_reference_codes": ["gideon", "joshua"],
    },
}

# UI-only avatars are generated by the same avatar pipeline so their tone stays
# aligned with the biblical cast, but seed builders skip them for DB characters.
UI_ONLY_AVATAR_ROSTER: dict[str, dict[str, Any]] = {
    "guide": {
        "name_ko": "안내자",
        "name_en": "Guide",
        "era": "gospels",
        "asset_only": True,
        "prompt_source": "manual",
        "use_common_style": False,
        "style_reference_codes": ["david", "john", "matthew", "timothy"],
        "prompt": (
            "same flat paper-cut vector avatar world as the existing biblical "
            "cast, warm cream + muted olive + teal-blue shawl + small "
            "parchment-gold accents, no visible outline, no ink contour, edges "
            "separated only by soft flat color planes, plain white background, "
            "Guide, joyful young adult biblical male guide character for app "
            "explanation popups, UI helper avatar not a Bible story person, "
            "face-dominant head-and-shoulders circular app icon composition, "
            "head and upper chest fill most of the square canvas, facial "
            "expression must be clearly readable in a 48px circular thumbnail, "
            "clearly beardless clean-shaven face, no moustache, no facial hair, "
            "large bright happy eyes with small catchlights, wide open cheerful "
            "smile, lifted friendly eyebrows, excited delighted expression like "
            "he is happily explaining something useful, front-facing face and "
            "shoulders, both eyes looking directly at the viewer, one open hand "
            "raised beside the cheek in a lively teaching gesture, other hand "
            "holding a small blank rolled parchment partly visible near the "
            "chest, cream tunic collar, muted olive robe shoulders, teal-blue "
            "short shawl visible around the neck and shoulders, centered in the "
            "canvas with enough white margin so the circular crop does not cut "
            "off hair, chin, shoulders, or raised hand, clean iconic silhouette, "
            "single character only, no other people, no text, no letters, no "
            "speech bubble"
        ),
        "negative_prompt_extra": (
            "beard, moustache, facial hair, stubble, old man, elderly, gray hair, "
            "stern expression, sad expression, angry expression, serious frown, "
            "closed mouth, hidden face, tiny unreadable face, small distant face, "
            "full body figure, head-to-toe figure, tiny standing body, face turned "
            "away, profile view, side view, speech bubble, readable text, label"
        ),
    },
}

# Divided-kingdom monarchs that need avatar-ready identities before their
# individual story events are written. Codes intentionally disambiguate
# same-name kings between Northern Israel and Southern Judah.
DIVIDED_KINGDOM_KING_ROSTER: dict[str, dict[str, Any]] = {
    # Northern Israel
    "nadab": {
        "name_ko": "나답",
        "name_en": "Nadab, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["jeroboam", "ahab", "hoshea_king"],
        "palette": "dark pine green + dull bronze + pale linen accents, low saturation",
        "signature": [
            "short-lived northern Israel king, son of Jeroboam, exactly one man only",
            "dark pine royal robe with dull bronze collar and a slightly crooked narrow crown band",
            "small cracked calf-shaped dynasty seal pinned high on the chest as a restrained sign of Jeroboam's fragile house",
            "fearful proud expression with tightened mouth, not smiling, not a prophet and not a battle scene",
        ],
        "mood": [
            "tense young kingly posture, one hand guarding the cracked chest seal near the collar",
        ],
        "visual": [
            "slim young northern king build with raised narrow shoulders",
            "narrow triangular face with high cheekbones, worried ambitious eyes, and uneven arched brows",
            "short dark hair under a crooked bronze Samaria royal headband",
            "thin mustache and small pointed dark beard, clearly different from the fuller-bearded kings",
        ],
        "negative": "Jeroboam, prophet, priest, battlefield, Baasha attacking, blood, gore",
    },
    "baasha": {
        "name_ko": "바아사",
        "name_en": "Baasha, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "jeroboam", "hoshea_king"],
        "palette": "dark olive + weathered bronze + clay red accents, low saturation",
        "signature": [
            "northern Israel usurper king silhouette, exactly one man only",
            "weathered olive royal cloak over a clay-red tunic with a heavy bronze shoulder clasp",
            "seized royal seal set into the shoulder clasp and a short dagger hilt barely visible near the upper sash as restrained signs of a violent rise",
            "cold ruthless expression with tight lips, not smiling, no active violence",
        ],
        "mood": [
            "stern usurper-king posture with squared shoulders, chin pushed forward, and guarded eyes",
        ],
        "visual": [
            "stocky middle-aged northern king build with broad compact shoulders and thick neck",
            "hard rectangular face with broad nose, watchful deep-set eyes, and a severe heavy brow",
            "close-cropped dark hair beneath a rough bronze crown band",
            "dense square dark beard trimmed close to the jaw, very different from Nadab's pointed beard",
        ],
        "negative": "Nadab, assassination scene, blood, gore, corpse, battlefield crowd",
    },
    "elah_king": {
        "name_ko": "엘라",
        "name_en": "Elah, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "jeroboam", "hoshea_king"],
        "palette": "muted wine red + dull bronze + dark olive accents, low saturation",
        "signature": [
            "weak northern Israel palace king silhouette, exactly one man only",
            "wine-red royal robe with dull bronze sash and a small Samaria crown band",
            "small empty cup held low as a restrained sign of careless palace feasting",
            "uneasy distracted expression, not a banquet scene",
        ],
        "mood": [
            "slack but royal posture, one hand lowered with an empty cup and worried eyes",
        ],
        "visual": [
            "soft middle-aged king build with slightly rounded shoulders",
            "oval face with tired distracted eyes and a weak brow",
            "dark hair under a narrow bronze royal headband",
            "short soft beard with muted faceted planes",
        ],
        "negative": "drunken party, feast crowd, Zimri attacking, blood, gore, corpse",
    },
    "zimri": {
        "name_ko": "시므리",
        "name_en": "Zimri, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "jeroboam", "hoshea_king"],
        "palette": "smoke gray + dark crimson + muted bronze accents, low saturation",
        "signature": [
            "seven-day northern Israel usurper king silhouette, exactly one man only",
            "smoke-gray mantle over dark crimson tunic with a narrow bronze commander collar",
            "broken palace key hanging high at the chest as a restrained sign of his brief seizure of power",
            "cornered sly expression with a tight uneven smirk, no fire scene",
        ],
        "mood": [
            "cornered defiant posture, shoulders pulled inward, fingers touching the broken key at the chest",
        ],
        "visual": [
            "wiry compact military-usurper build with tense narrow shoulders",
            "gaunt angular face with darting narrow eyes, asymmetrical brow, and sharp cheekbones",
            "short swept dark hair under a dark bronze commander headband",
            "thin mustache with a narrow pointed beard, sharper and smaller than Baasha's beard",
        ],
        "negative": "palace burning, flames, suicide scene, corpse, blood, gore, crowd",
    },
    "omri": {
        "name_ko": "오므리",
        "name_en": "Omri, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "jeroboam", "rehoboam"],
        "palette": "stone blue gray + muted bronze + deep olive accents, low saturation",
        "signature": [
            "founder of the Omride dynasty and Samaria-building king, exactly one man only",
            "stone-blue royal cloak with bronze belt, broad shoulder panels, and restrained northern crown band",
            "small stone citadel brooch near one shoulder plus a rolled city-plan strap across the chest as signs of building Samaria",
            "strategic calculating expression with controlled confidence, unsmiling, not a construction scene",
        ],
        "mood": [
            "controlled founder-king posture, standing steady with one hand resting near the city-plan strap",
        ],
        "visual": [
            "solid older middle-aged dynasty-founder build with broad stable shoulders and thick chest",
            "large square face with calculating eyes, heavy brow, and graying temples",
            "dark wavy hair with gray at the sides beneath a muted bronze royal headband",
            "full squared dark beard with gray streaks and clean blocky facets",
        ],
        "negative": "Ahab, Jezebel, construction crew, city crowd, battle scene",
    },
    "ahab": {
        "name_ko": "아합",
        "name_en": "Ahab, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["jeroboam", "ahab", "hoshea_king"],
        "palette": "royal purple + navy + muted gold accents, low saturation",
        "signature": [
            "northern kingdom king of Samaria silhouette, exactly one man only",
            "proud hardened ruler associated with Baal worship",
            "royal purple robe with navy mantle and muted gold headband",
            "small dark idol-shaped palace ornament kept secondary as a sign of apostasy",
            "no sling, no stone pouch, no shepherd accessory",
        ],
        "mood": [
            "proud hardened kingly posture, chin lifted with stubborn defiance",
        ],
        "visual": [
            "middle-aged northern king build with squared royal shoulders",
            "hard angular face with proud narrowed eyes and a stubborn brow",
            "dark hair under an ornate but restrained northern royal headband",
            "short dark beard with sharply faceted planes",
        ],
        "negative": "David, shepherd, sling, prophet Elijah, Mount Carmel scene, Jezebel, crowd",
    },
    "ahaziah_israel": {
        "name_ko": "아하시야(북이스라엘)",
        "name_en": "Ahaziah, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "hoshea_king", "jeroboam"],
        "palette": "sickly teal + dark navy + muted bronze accents, low saturation",
        "signature": [
            "Ahab's son and northern Israel king silhouette, exactly one man only",
            "dark navy royal mantle over sickly teal robe with muted bronze crown band",
            "small lattice-window token as a restrained sign of his fall and inquiry",
            "pale anxious expression, not Judah's Ahaziah",
        ],
        "mood": [
            "frail anxious royal posture, one hand holding a small lattice-window token",
        ],
        "visual": [
            "slender young northern king build with tense shoulders",
            "pale angular face with uneasy eyes and pinched brow",
            "short dark hair under a narrow bronze royal headband",
            "short dark beard with delicate faceted planes",
        ],
        "negative": "Ahaziah of Judah, Ahaz, child, sickbed scene, injury close-up, gore",
    },
    "joram_israel": {
        "name_ko": "요람(북이스라엘)",
        "name_en": "Joram, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "jeroboam", "hoshea_king"],
        "palette": "deep blue green + iron gray + muted bronze accents, low saturation",
        "signature": [
            "Joram of Northern Israel, son of Ahab, exactly one man only",
            "blue-green royal robe with iron-gray mantle, bronze crown band, and one broken Baal-pillar clasp near the shoulder",
            "sealed war report scroll tucked diagonally across the upper chest as a restrained sign of troubled campaigns",
            "wary diplomatic expression with tired suspicious eyes, not smiling, not Judah's Jehoram",
        ],
        "mood": [
            "guarded northern king posture, one shoulder slightly turned, hand near the sealed upper-chest scroll",
        ],
        "visual": [
            "tall lean middle-aged northern king build with narrow tense royal shoulders",
            "long face with prominent nose, hollow cheeks, suspicious heavy-lidded eyes, and a guarded brow",
            "straight dark hair under a bronze Samaria crown band",
            "short forked dark beard with sharp facets, clearly unlike Jehu's clipped commander beard",
        ],
        "negative": "Jehoram of Judah, Jehu killing scene, chariot battle, blood, gore",
    },
    "jehu": {
        "name_ko": "예후",
        "name_en": "Jehu, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "jeroboam", "hoshea_king"],
        "palette": "dark military green + blackened bronze + crimson accents, low saturation",
        "signature": [
            "fierce commander who became king of Northern Israel, exactly one man only",
            "military-green royal cloak over dark tunic with blackened bronze shoulder armor plates, no helmet",
            "small chariot-wheel medallion centered high on the chest and a short commander baton held upright near the shoulder as restrained signs of his zeal",
            "intense decisive expression with fierce focused eyes, no friendly smile, no battle scene",
        ],
        "mood": [
            "decisive commander-king posture, chest forward, baton close to the shoulder, eyes fierce but controlled",
        ],
        "visual": [
            "athletic middle-aged commander-king build with squared military shoulders and upright neck",
            "hawk-like face with prominent nose, sharp jaw, intense eyes, and a hard decisive brow",
            "short swept-back dark hair under a dark bronze commander crown band",
            "clipped black beard tight along the jaw, not long or forked",
        ],
        "negative": "Jezebel death scene, chariot crash, blood, gore, army crowd, battle",
    },
    "jehoahaz_israel": {
        "name_ko": "여호아하스(북이스라엘)",
        "name_en": "Jehoahaz, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "hoshea_king", "jeroboam"],
        "palette": "dusty blue + worn bronze + parchment tan accents, low saturation",
        "signature": [
            "oppressed northern Israel king under Aram's pressure, exactly one man only",
            "dusty blue royal robe with worn bronze crown band and plain sash",
            "small cracked shield token held low as a restrained sign of weakness under oppression",
            "humbled troubled expression, not Judah's Jehoahaz",
        ],
        "mood": [
            "humbled pleading royal posture, cracked shield token held low",
        ],
        "visual": [
            "lean middle-aged northern king build with bowed but royal shoulders",
            "weathered face with worried eyes and softened brow",
            "dark hair under a simple worn bronze headband",
            "short gray-streaked beard with modest facets",
        ],
        "negative": "Jehoahaz of Judah, Pharaoh Necho, prison, chains, battle scene",
    },
    "jehoash_israel": {
        "name_ko": "요아스(북이스라엘)",
        "name_en": "Jehoash, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "jeroboam", "elisha"],
        "palette": "royal blue + muted bronze + olive accents, low saturation",
        "signature": [
            "Jehoash of Northern Israel, exactly one man only",
            "royal blue robe with muted bronze crown band, olive sash, and three small arrows strapped diagonally near the upper chest",
            "small bow kept lowered at the side while the upper-chest arrows remain visible as a restrained sign of Elisha's victory prophecy",
            "conflicted but strengthened expression with respectful worried eyes, not smiling, not Judah's Joash",
        ],
        "mood": [
            "uncertain but strengthened king posture, one hand touching the arrow strap near the collar",
        ],
        "visual": [
            "mature northern king build with balanced shoulders and a slightly bowed respectful stance",
            "rounded rectangular face with heavy-lidded alert eyes, cautious brow, and softer cheeks",
            "short dark hair with subtle gray at the temples under bronze Samaria crown band",
            "medium rounded dark beard with a few gray facets, clearly not the young Judah Joash",
        ],
        "negative": "Joash of Judah, child king, temple repair, shooting action, battle scene",
    },
    "jeroboam_ii": {
        "name_ko": "여로보암 2세",
        "name_en": "Jeroboam II, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["jeroboam", "ahab", "hoshea_king"],
        "palette": "deep emerald + warm bronze + ivory accents, low saturation",
        "signature": [
            "prosperous northern Israel king Jeroboam the Second, exactly one man only",
            "deep emerald royal cloak with warm bronze collar, ivory under-robe, and broader northern crown band",
            "small border-map medallion high on the chest plus a rolled map edge near the shoulder as restrained signs of restored territory",
            "self-satisfied prosperous expression with a restrained proud smirk, not benevolent, clearly distinct from Jeroboam son of Nebat",
        ],
        "mood": [
            "confident expansion-era king posture, relaxed shoulders, chin lifted with restrained pride",
        ],
        "visual": [
            "large broad mature northern king build with confident shoulders and thick upper chest",
            "broad round-square face with self-assured eyes, full cheeks, and steady brow",
            "thick wavy dark hair beneath a warm bronze crown band",
            "full well-groomed rounded beard with polished faceted planes, more luxurious than Omri's graying beard",
        ],
        "negative": "Jeroboam son of Nebat, torn cloak, golden calf scene, prophet Amos",
    },
    "zechariah_king": {
        "name_ko": "스가랴 왕",
        "name_en": "Zechariah, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["jeroboam", "hoshea_king", "ahab"],
        "palette": "faded emerald + dull gold + ash gray accents, low saturation",
        "signature": [
            "last king of Jehu's dynasty in Northern Israel, exactly one man only",
            "faded emerald royal robe with dull gold crown band and ash-gray mantle",
            "small broken dynasty ring as a restrained sign of a line ending",
            "young worried royal expression, not Zechariah the prophet or priest",
        ],
        "mood": [
            "worried last-dynasty posture, broken ring held near the heart",
        ],
        "visual": [
            "young northern king build with narrow shoulders",
            "angular face with anxious eyes and uncertain brow",
            "short dark hair under a fading gold crown band",
            "short neat beard with soft facets",
        ],
        "negative": "Zechariah prophet, Zechariah father of John, priest robe, temple incense",
    },
    "shallum": {
        "name_ko": "살룸",
        "name_en": "Shallum, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "hoshea_king", "jeroboam"],
        "palette": "dark clay red + smoke gray + muted bronze accents, low saturation",
        "signature": [
            "one-month northern Israel usurper king, exactly one man only",
            "dark clay-red mantle with smoke-gray sash and muted bronze crown band",
            "small short-lived seal tablet as a restrained sign of a brief reign",
            "uneasy calculating expression, no assassination scene",
        ],
        "mood": [
            "uneasy usurper posture, short-lived seal tablet gripped tightly",
        ],
        "visual": [
            "compact anxious usurper build with tight shoulders",
            "thin angular face with restless eyes and sharp brow",
            "short dark hair under a narrow bronze headband",
            "short pointed beard with severe facets",
        ],
        "negative": "Zechariah murder scene, Menahem attacking, blood, gore, crowd",
    },
    "menahem": {
        "name_ko": "므나헴",
        "name_en": "Menahem, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahab", "hoshea_king", "jeroboam"],
        "palette": "iron gray + muted gold + dark olive accents, low saturation",
        "signature": [
            "harsh tribute-paying northern Israel king, exactly one man only",
            "iron-gray royal mantle with muted gold belt and northern crown band",
            "small Assyrian tribute tablet without readable text as a restrained sign",
            "hard calculating expression, no cruelty scene",
        ],
        "mood": [
            "hard tribute-king posture, blank tribute tablet held with guarded pride",
        ],
        "visual": [
            "stocky middle-aged northern king build with heavy shoulders",
            "broad stern face with calculating eyes and heavy brow",
            "dark hair under a muted gold royal headband",
            "full dark beard with blocky facets",
        ],
        "negative": "Assyrian king, Tiglath-pileser, cruelty scene, pregnant women, gore",
    },
    "pekahiah": {
        "name_ko": "브가히야",
        "name_en": "Pekahiah, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["hoshea_king", "ahab", "jeroboam"],
        "palette": "muted gold + storm blue + ash brown accents, low saturation",
        "signature": [
            "Pekahiah son of Menahem, northern Israel king, exactly one man only",
            "storm-blue robe with muted gold mantle edge and modest crown band",
            "small inherited royal seal as a restrained sign of a fragile throne",
            "uncertain heir expression, no palace coup scene",
        ],
        "mood": [
            "uncertain inherited-king posture, royal seal held carefully",
        ],
        "visual": [
            "young-to-middle-aged northern king build with hesitant shoulders",
            "soft angular face with uncertain eyes and mild brow",
            "short dark hair under a muted gold headband",
            "short trimmed beard with gentle facets",
        ],
        "negative": "Pekah attacking, coup scene, bodyguard, blood, gore, crowd",
    },
    "pekah": {
        "name_ko": "베가",
        "name_en": "Pekah, King of Israel",
        "kingdom": "north",
        "style_reference_codes": ["ahaz", "ahab", "hoshea_king"],
        "palette": "dark teal + bronze + muted crimson accents, low saturation",
        "signature": [
            "military ruler Pekah of Northern Israel, exactly one man only",
            "dark teal military-royal cloak with diagonal bronze war sash across the upper chest and crown band",
            "small sealed Aram alliance clasp pinned at the shoulder as a restrained sign of the Syro-Ephraimite crisis",
            "aggressive strategic expression with narrowed eyes, not smiling, not a battlefield",
        ],
        "mood": [
            "military king posture, shoulders angled forward, hand near the shoulder alliance clasp",
        ],
        "visual": [
            "lean soldier-king build with hard angular shoulders and long neck",
            "long hawkish face with fierce eyes, sharp brow, and narrow mouth",
            "short dark hair brushed back beneath a bronze military crown band",
            "straight narrow dark beard trimmed to a vertical point, distinct from Jehu's clipped jaw beard",
        ],
        "negative": "Ahaz, Rezin, Aram king, battlefield, siege scene, blood, gore",
    },
    # Southern Judah
    "abijah_judah": {
        "name_ko": "아비야(남유다)",
        "name_en": "Abijah, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["rehoboam", "josiah", "hezekiah"],
        "palette": "wine purple + temple gold + parchment ivory accents, low saturation",
        "signature": [
            "Abijah of Judah, Davidic royal heir, exactly one man only",
            "wine-purple robe with temple-gold Judah crown diadem and parchment ivory sash",
            "small temple trumpet clasp pinned near the shoulder as a restrained sign of trusting temple order",
            "bold but imperfect royal expression with confident eyes and a slight proud set to the mouth, not a priest",
        ],
        "mood": [
            "bold Davidic king posture, one shoulder lifted, hand near the temple trumpet shoulder clasp",
        ],
        "visual": [
            "young robust Judah king build with polished royal shoulders and strong neck",
            "square princely face with arched brows, confident eyes, and firm chin",
            "dark wavy hair under a small angular gold Judah crown diadem",
            "short tidy boxed beard with regal facets, darker and sharper than Jehoshaphat's beard",
        ],
        "negative": "Abijah prophet, priest robe, battle panorama, Jeroboam appearing, crowd",
    },
    "asa": {
        "name_ko": "아사",
        "name_en": "Asa, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["josiah", "hezekiah", "rehoboam"],
        "palette": "deep olive + royal blue + warm gold accents, low saturation",
        "signature": [
            "reforming king Asa of Judah, exactly one man only",
            "deep olive royal cloak over blue robe with warm gold Judah diadem",
            "small broken idol fragment kept low as a restrained sign of reform",
            "earnest firm expression, no idol-breaking scene",
        ],
        "mood": [
            "firm reforming king posture, broken idol fragment held away from the heart",
        ],
        "visual": [
            "mature Judah king build with upright disciplined shoulders",
            "long angular face with resolute eyes and calm brow",
            "dark hair under a small gold Judah crown diadem",
            "trimmed beard with clean faceted planes",
        ],
        "negative": "idol-breaking action, mother Maacah, battle scene, diseased feet close-up",
    },
    "jehoshaphat": {
        "name_ko": "여호사밧",
        "name_en": "Jehoshaphat, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["josiah", "hezekiah", "rehoboam"],
        "palette": "royal blue + parchment cream + muted gold accents, low saturation",
        "signature": [
            "Jehoshaphat of Judah, teaching-and-justice king, exactly one man only",
            "royal blue robe with parchment cream upper sash and muted gold Judah diadem",
            "small open law scroll held high at the chest and a slim judge staff rising beside one shoulder as restrained signs of teaching and justice",
            "benevolent wise expression with gentle smiling eyes, no battle scene",
        ],
        "mood": [
            "wise judicial king posture, warm calm shoulders, law scroll close to the heart",
        ],
        "visual": [
            "mature Judah king build with broad calm shoulders and open chest posture",
            "kind rectangular face with thoughtful soft eyes, fair brow, and subtle smile lines",
            "dark hair with clear gray at the temples beneath a gold Judah diadem",
            "full gray-streaked rounded beard with gentle faceted planes",
        ],
        "negative": "Ahab beside him, alliance scene, battlefield, choir army, crowd",
    },
    "jehoram_judah": {
        "name_ko": "여호람(남유다)",
        "name_en": "Jehoram, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["rehoboam", "ahab", "ahaz"],
        "palette": "dark purple + ash gray + tarnished gold accents, low saturation",
        "signature": [
            "Jehoram of Judah, exactly one man only",
            "dark purple Judah royal robe with ash-gray mantle and tarnished gold diadem",
            "small northern alliance seal as a restrained sign of Ahab's house influence",
            "cold uneasy expression, not Joram of Israel",
        ],
        "mood": [
            "cold uneasy Judah king posture, alliance seal held stiffly",
        ],
        "visual": [
            "middle-aged Judah king build with stiff shoulders",
            "narrow face with suspicious eyes and tight brow",
            "dark hair under a tarnished gold Judah diadem",
            "trimmed beard with hard facets",
        ],
        "negative": "Joram of Israel, brothers being killed, disease scene, gore, crowd",
    },
    "ahaziah_judah": {
        "name_ko": "아하시야(남유다)",
        "name_en": "Ahaziah, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["ahab", "ahaz", "rehoboam"],
        "palette": "royal violet + dark teal + muted gold accents, low saturation",
        "signature": [
            "Ahaziah of Judah, young king influenced by Ahab's house, exactly one man only",
            "royal violet Judah robe with dark teal mantle and muted gold diadem",
            "small northern alliance clasp as a restrained sign of divided loyalties",
            "uncertain proud expression, not Ahaziah of Israel",
        ],
        "mood": [
            "young conflicted king posture, northern alliance clasp held near the sash",
        ],
        "visual": [
            "young Judah king build with narrow polished shoulders",
            "smooth angular face with uncertain proud eyes",
            "short dark hair under a small gold Judah diadem",
            "short neat beard with soft facets",
        ],
        "negative": "Ahaziah of Israel, sickbed, window lattice, Jehu killing scene, gore",
    },
    "athaliah": {
        "name_ko": "아달랴",
        "name_en": "Athaliah, Queen of Judah",
        "kingdom": "south",
        "gender": "female",
        "style_reference_codes": ["esther", "rehoboam", "ahaz"],
        "palette": "deep royal violet + blackened gold + dark crimson accents, low saturation",
        "signature": [
            "Athaliah queen-ruler of Judah, distinctly female, exactly one woman only",
            "deep royal violet gown with blackened-gold Judah crown diadem and dark crimson mantle",
            "small usurped throne seal held tightly as a restrained sign of seizing power",
            "severe commanding expression, no child-harm scene",
        ],
        "mood": [
            "severe queen-ruler posture, chin lifted, usurped throne seal gripped tightly",
        ],
        "visual": [
            "mature royal woman build with upright commanding shoulders",
            "sharp angular oval face with cold determined eyes",
            "dark hair fully arranged beneath a blackened-gold royal diadem",
        ],
        "negative": "male, man, beard, child Joash, child-harm scene, massacre, blood, gore, crowd",
    },
    "joash_judah": {
        "name_ko": "요아스(남유다)",
        "name_en": "Joash, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["josiah", "hezekiah", "rehoboam"],
        "palette": "bright royal blue + warm gold + temple cream accents, low saturation",
        "signature": [
            "Joash of Judah, temple-repair king, exactly one man only",
            "bright royal blue robe with warm gold Judah diadem and temple-cream upper sash",
            "small temple repair tablet held high at the chest and a tiny offering-chest pendant near the collar as restrained signs of temple repair",
            "young adult stylized king with a hopeful gentle smile, not a child portrait and not Northern Israel's Jehoash",
        ],
        "mood": [
            "earnest temple-repair king posture, upright and hopeful, repair tablet close to the chest",
        ],
        "visual": [
            "young adult Judah king build with slim upright shoulders and lighter frame than Abijah",
            "youthful oval face with earnest bright eyes, gentle brow, and soft smile",
            "short dark curled hair under a small gold Judah diadem",
            "very short neat beard and mustache, adult-stylized not childlike",
        ],
        "negative": "child, boy, infant, Jehoash of Israel, Elisha arrows, assassination scene",
    },
    "amaziah_judah": {
        "name_ko": "아마샤",
        "name_en": "Amaziah, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["josiah", "hezekiah", "rehoboam"],
        "palette": "clay red + royal blue + muted gold accents, low saturation",
        "signature": [
            "Amaziah of Judah, half-faithful king, exactly one man only",
            "clay-red royal mantle over blue robe with muted gold Judah diadem",
            "small Edom shield token held low as a restrained sign of victory and pride",
            "confident but flawed expression, no battle scene",
        ],
        "mood": [
            "confident but flawed king posture, Edom shield token held low",
        ],
        "visual": [
            "mature Judah king build with proud shoulders",
            "long face with confident eyes and slightly lifted brow",
            "dark hair under a muted gold diadem",
            "trimmed beard with clean facets",
        ],
        "negative": "battle with Edom, Israel king Joash, captured Jerusalem scene, crowd",
    },
    "uzziah": {
        "name_ko": "웃시야",
        "name_en": "Uzziah, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["hezekiah", "josiah", "rehoboam"],
        "palette": "stone gray + royal indigo + warm gold accents, low saturation",
        "signature": [
            "Uzziah also called Azariah, strong builder king of Judah, exactly one man only",
            "stone-gray royal mantle over indigo robe with warm gold Judah diadem",
            "small tower plan and builder's cord as restrained signs of fortified strength",
            "capable proud expression, no incense intrusion scene",
        ],
        "mood": [
            "strong builder-king posture, tower plan held with controlled pride",
        ],
        "visual": [
            "strong mature Judah king build with broad shoulders",
            "square face with capable eyes and proud brow",
            "dark hair with gray hints under a gold Judah diadem",
            "full trimmed beard with geometric facets",
        ],
        "negative": "leprosy horror, priest confrontation, incense altar scene, gore",
    },
    "jotham": {
        "name_ko": "요담",
        "name_en": "Jotham, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["hezekiah", "josiah", "rehoboam"],
        "palette": "sage green + royal blue + muted gold accents, low saturation",
        "signature": [
            "Jotham of Judah, steady builder king, exactly one man only",
            "sage-green royal mantle over blue robe with muted gold Judah diadem",
            "small upper-gate model as a restrained sign of building work",
            "quiet faithful expression, not Gideon's son Jotham",
        ],
        "mood": [
            "quiet steady king posture, upper-gate model held carefully",
        ],
        "visual": [
            "mature Judah king build with calm narrow shoulders",
            "rectangular face with thoughtful eyes and balanced brow",
            "dark hair beneath a small gold Judah diadem",
            "trimmed beard with modest facets",
        ],
        "negative": "Jotham son of Gideon, parable trees, crowd, construction crew",
    },
    "manasseh": {
        "name_ko": "므낫세",
        "name_en": "Manasseh, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["ahaz", "hezekiah", "josiah"],
        "palette": "dark violet + ash black + tarnished gold accents, low saturation",
        "signature": [
            "Manasseh of Judah, long-reigning apostate king later humbled, exactly one man only",
            "dark violet royal robe with ash-black mantle and tarnished gold diadem",
            "small dark idol charm lowered in one hand as a restrained sign of apostasy",
            "troubled hardened expression, no sacrifice scene",
        ],
        "mood": [
            "troubled hardened king posture, idol charm held low and away from the heart",
        ],
        "visual": [
            "older Judah king build with heavy tense shoulders",
            "weathered angular face with haunted eyes and severe brow",
            "gray-streaked dark hair under a tarnished gold diadem",
            "full gray-streaked beard with blocky facets",
        ],
        "negative": "child sacrifice, blood, gore, Assyrian chains, prison scene, crowd",
    },
    "amon_judah": {
        "name_ko": "아몬(남유다)",
        "name_en": "Amon, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["ahaz", "jehoiakim", "zedekiah"],
        "palette": "dark crimson + ash gray + tarnished gold accents, low saturation",
        "signature": [
            "Amon of Judah, wicked short-reigning king, exactly one man only",
            "dark crimson royal robe with ash-gray mantle and tarnished gold diadem",
            "small palace idol token held close as a restrained sign of continuing evil",
            "hard suspicious expression, not the Egyptian god Amun",
        ],
        "mood": [
            "hard suspicious king posture, palace idol token gripped near the belt",
        ],
        "visual": [
            "young-to-middle-aged Judah king build with tense shoulders",
            "sharp face with suspicious eyes and furrowed brow",
            "dark hair under a tarnished gold Judah diadem",
            "short dark beard with severe facets",
        ],
        "negative": "Egyptian god Amun, animal head, deity, assassination scene, blood, gore",
    },
    "jehoahaz_judah": {
        "name_ko": "여호아하스(남유다)",
        "name_en": "Jehoahaz, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["josiah", "jehoiakim", "zedekiah"],
        "palette": "royal blue + dust gray + muted gold accents, low saturation",
        "signature": [
            "Jehoahaz of Judah, short-reigning son of Josiah, exactly one man only",
            "royal blue robe with dust-gray mantle and muted gold Judah diadem",
            "small Egyptian tribute token as a restrained sign of being removed by Pharaoh",
            "anxious displaced expression, not Northern Israel's Jehoahaz",
        ],
        "mood": [
            "anxious displaced king posture, tribute token held uncertainly",
        ],
        "visual": [
            "young Judah king build with slim tense shoulders",
            "youthful angular face with worried eyes and tight brow",
            "short dark hair under a muted gold Judah diadem",
            "short neat beard with soft facets",
        ],
        "negative": "Jehoahaz of Israel, prison chains, Pharaoh Necho scene, Egypt crowd",
    },
    "jehoiachin": {
        "name_ko": "여호야긴",
        "name_en": "Jehoiachin, King of Judah",
        "kingdom": "south",
        "style_reference_codes": ["jehoiakim", "zedekiah", "josiah"],
        "palette": "royal indigo + exile gray + muted gold accents, low saturation",
        "signature": [
            "Jehoiachin king of Judah taken into Babylonian exile, exactly one man only",
            "royal indigo robe with exile-gray mantle and muted gold Judah diadem",
            "small blank exile tablet as a restrained sign of captivity",
            "young sorrowful royal expression, not Jehoiakim and not Zedekiah",
        ],
        "mood": [
            "sorrowful exiled-king posture, blank exile tablet held close to the chest",
        ],
        "visual": [
            "young Judah king build with lowered but royal shoulders",
            "smooth angular face with sorrowful eyes and subdued brow",
            "short dark hair under a muted gold Judah diadem",
            "short neat beard with gentle facets",
        ],
        "negative": "Jehoiakim, Zedekiah, blindfold, chains, prison bars, execution scene",
    },
}

KO_NAME_OVERRIDES.update(
    {code: data["name_ko"] for code, data in DIVIDED_KINGDOM_KING_ROSTER.items()}
)
EN_NAME_OVERRIDES.update(
    {code: data["name_en"] for code, data in DIVIDED_KINGDOM_KING_ROSTER.items()}
)
FORCE_ACTIVE_DEFAULT_CODES.update(DIVIDED_KINGDOM_KING_ROSTER)
CURATED_AVATAR_ROSTER.update(
    {
        code: {
            "name_ko": data["name_ko"],
            "name_en": data["name_en"],
            "era": "divided_kingdom",
            "style_reference_codes": data.get("style_reference_codes", []),
        }
        for code, data in DIVIDED_KINGDOM_KING_ROSTER.items()
    }
)
CURATED_AVATAR_ROSTER["jehoiada"] = {
    "name_ko": "여호야다",
    "name_en": "Jehoiada the Priest",
    "era": "divided_kingdom",
    "style_reference_codes": ["aaron", "samuel", "josiah"],
}
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
    "king, queen, banquet crowd, attendants, throne scene, heroic nobleman, brave hero, gentle smile, "
    "kind face, friendly expression, soft innocent eyes, cute mascot, timid clerk, humble servant, "
    "monster, demon, horns, fantasy villain armor, soldier armor, sword, spear, crown, "
    "pale washed-out robe, plain beige clothing, oversized head, huge face, close-up portrait, "
    "cropped feet, missing sandals, waist-up crop"
)
DANIEL_NEGATIVE_PROMPT_EXTRA = (
    "multiple people, crowd, group, duo, pair, two people, extra character, background character, "
    "dull eyes, blank dot eyes, blue royal robe, dark blue robe, warrior armor, crown, weapon"
)
DAN_NEGATIVE_PROMPT_EXTRA = "multiple people, crowd, group, duo, pair, two people, extra character, background character"
ADAM_NEGATIVE_PROMPT_EXTRA = (
    "fisherman, apostle, disciple, fishing net, cast net, net weights, rope net, fish, boat, "
    "staff, shepherd staff, scroll, royal robe, modern clothing, exposed nudity, leaf underwear, "
    "very dark skin tone, overly dark brown face, reddish dark face, shadowed face, "
    "green skin, olive-green skin, yellow-green face, sallow green cast, sickly yellow skin, "
    "multiple people, Eve, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
EVE_NEGATIVE_PROMPT_EXTRA = (
    "royal queen, veil crown, jewelry-heavy outfit, modern dress, exposed nudity, leaf bikini, "
    "fisherwoman, fishing net, tools, weapon, scroll, multiple people, Adam, "
    "very dark skin tone, overly dark brown face, reddish dark face, shadowed face, "
    "green skin, olive-green skin, yellow-green face, sallow green cast, sickly yellow skin, "
    "cropped feet, missing sandals, waist-up crop, close-up portrait"
)
JUDAH_NEGATIVE_PROMPT_EXTRA = (
    "oversized head, giant head, huge face, bobblehead, face too large, close-up portrait, "
    "head one-third of body height, tiny body under oversized head, stubby body, short legs, "
    "cropped feet, missing sandals, waist-up crop, zoomed-in face"
)
LABAN_NEGATIVE_PROMPT_EXTRA = (
    "pale washed out colors, faded robe, cream-only robe, low contrast, ghostly pale face, "
    "plain beige clothing, weak silhouette, timid expression, Abraham, Jacob, generic shepherd, "
    "oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
ABRAHAM_NEGATIVE_PROMPT_EXTRA = (
    "generic old man, weak grandfather, frail body, stooped shoulders, timid expression, "
    "sad tired face, blank passive face, tiny body under oversized head, huge face, "
    "plain beige robe only, dull clothing, no covenant-patriarch dignity, "
    "very dark skin tone, overly dark brown face, reddish dark face, shadowed face, "
    "green skin, olive-green skin, yellow-green face, sallow green cast, sickly yellow skin, "
    "side view, three-quarter view, looking away, profile view, turned head, "
    "cropped feet, missing sandals, waist-up crop, close-up portrait"
)
AARON_NEGATIVE_PROMPT_EXTRA = (
    "elderly high priest, old priest, gray beard, white beard, gray hair, priestly breastplate, "
    "twelve-stone breastpiece, ornate high-priest robe, priestly turban, gold forehead plate, "
    "ceremonial temple outfit, frail body, stooped shoulders, generic priest, "
    "cropped feet, missing sandals, waist-up crop, close-up portrait"
)
MOSES_NEGATIVE_PROMPT_EXTRA = (
    "feeble elderly caricature, frail grandfather, fully white hair, fully white beard, "
    "fully gray hair, fully gray beard, sagging body, stooped shoulders, weary face, sad eyes, "
    "burdened expression, defeated expression, anxious expression, timid posture, apologetic posture, "
    "young prince of Egypt, royal Egyptian clothing, priestly breastplate, crown, king robe, "
    "very dark skin tone, overly dark brown face, shadowed face, side view, three-quarter view, "
    "green skin, olive-green skin, yellow-green face, sallow green cast, sickly yellow skin, "
    "looking away, profile view, turned head, "
    "cropped feet, missing sandals, waist-up crop, close-up portrait"
)
JOSEPH_NEGATIVE_PROMPT_EXTRA = (
    "very dark skin tone, overly dark brown face, shadowed face, reddish dark face, "
    "green skin, olive-green skin, yellow-green face, sallow green cast, sickly yellow skin, "
    "dull eyes, blank dot eyes, sleepy eyes, unfocused gaze, vacant expression, gloomy face, low contrast face, "
    "tiny unreadable eyes, eyes hidden by shadow, pale washed-out clothing, "
    "Pharaoh crown, royal nemes headcloth, full Egyptian king outfit, old man, gray beard, "
    "cropped feet, missing sandals, waist-up crop, close-up portrait"
)
DAVID_NEGATIVE_PROMPT_EXTRA = (
    "ordinary bard, generic harp player, plain background singer, timid expression, blank dot eyes, "
    "weak posture, servant-only clothing, dull robe, oversized harp hiding the body, "
    "Saul, Solomon, generic king, heavy crown, old king, gray beard, elderly David, "
    "cropped feet, missing sandals, waist-up crop, close-up portrait"
)
ELIJAH_NEGATIVE_PROMPT_EXTRA = (
    "scary horror face, ghost eyes, glowing white eyes, blank white eyes, empty eyes, possessed eyes, "
    "pale dead eyes, demonic glare, terrifying expression, sinister villain, monster, zombie, corpse-like face, "
    "angry rage face, violent attack pose, threatening clenched fist, blood, gore, corpse, weapon, "
    "purple royal robe, violet cloth, torn purple banner, gold-trimmed royal sash, court robe, priestly linen, "
    "king, crown, armor, fantasy wizard, magic staff, storm monster, "
    "overly dark face, harsh black shadows, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
NOAH_NEGATIVE_PROMPT_EXTRA = (
    "empty hands, open empty hands, blessing pose only, no tools, no ark, no boat, no wooden model, "
    "fisherman, fishing net, shepherd staff, royal robe, priestly robe, weapon, "
    "modern saw, modern hammer, metal power tool, ship captain uniform, "
    "frail old man, timid expression, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
KORAH_NEGATIVE_PROMPT_EXTRA = (
    "ordinary shepherd, faithful priest, humble servant, gentle smile, brave hero, calm teacher, Moses, Aaron, "
    "kind face, soft innocent eyes, priestly high-priest breastplate, ornate priest turban, royal crown, king robe, "
    "earthquake scene, falling body, person swallowed, corpse, death scene, blood, gore, multiple people, crowd, "
    "plain teal robe only, empty hands, no censer, no rebel sign, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
PHINEHAS_NEGATIVE_PROMPT_EXTRA = (
    "generic temple servant, ordinary ceremonial robe only, high priest breastplate, jeweled breastpiece, ornate turban, "
    "king, warrior armor, battle scene, active stabbing, killing scene, blood, gore, corpse, wound, multiple people, crowd, "
    "empty hands, no spear, no censer, timid expression, soft gentle smile, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
MATTHIAS_NEGATIVE_PROMPT_EXTRA = (
    "generic missionary, Paul, Barnabas, Judas Iscariot, Roman official, fisherman net, warrior, armor, weapon, "
    "side view, three-quarter view, looking away, turned head, leaning pose, running pose, "
    "empty hands, no lots, no scroll, no witness sign, dark villain expression, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
ASHER_NEGATIVE_PROMPT_EXTRA = (
    "Joseph, dreamer, Egyptian governor, generic traveler, faded pale colors, washed-out robe, gray face, green skin, olive-green skin, "
    "very dark face, shadowed face, no olive branch, no bread, no grain, no tribe blessing sign, "
    "side view, looking away, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
AHIJAH_NEGATIVE_PROMPT_EXTRA = (
    "medical eye bandage, wrapped cloth covering eyes, black blindfold, pirate eyepatch, normal focused eyes, clear dark pupils, direct eye contact, "
    "sharp youthful eyes, glowing eyes, empty eye sockets, missing eyes, blood, gore, wound, horror face, scary prophet, terrifying expression, zombie, corpse-like face, "
    "no torn cloak pieces, plain generic prophet, Samuel, Isaiah, "
    "royal king robe, crown, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
LEVI_ISSACHAR_NEGATIVE_PROMPT_EXTRA = (
    "faded pale skin, washed-out face, gray face, green skin, olive-green skin, yellow-green face, sallow green cast, sickly yellow skin, "
    "very dark face, shadowed face, low contrast face, ghostly pale clothing, generic dreamer, Joseph, Egyptian robe, "
    "side view, looking away, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
ZEBULUN_NEGATIVE_PROMPT_EXTRA = (
    "generic dreamer, Joseph, Egyptian governor, ordinary desert traveler, shepherd-only silhouette, farmer-only silhouette, "
    "fishing net as main prop, fisherman apostle, Peter, Andrew, modern sailor, modern ship captain, modern anchor, "
    "no ship sign, no harbor sign, no rope, empty hands, faded pale colors, washed-out robe, gray face, green skin, "
    "side view, looking away, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
AHAB_NEGATIVE_PROMPT_EXTRA = (
    "gentle king, humble faithful king, kind smile, repentant face, no idol, tiny unclear idol, empty hands, prophet robe, priest robe, "
    "David, Saul, Solomon, Elijah, shepherd, sling, no Baal sign, heroic posture, soft innocent eyes, "
    "battle gore, corpse, blood, multiple people, crowd, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
RAHAB_NEGATIVE_PROMPT_EXTRA = (
    "male, man, masculine face, broad male jaw, square male shoulders, beard, mustache, facial hair, stubble, warrior, armor, soldier, "
    "older woman, middle-aged matron, elderly face, deep wrinkles, gray hair, hunched posture, "
    "side view, three-quarter view, walking pose, running pose, leaning forward, looking away, face turned aside, "
    "seductive pose, exposed body, royal queen, soldier, warrior, weapon, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
NEHEMIAH_NEGATIVE_PROMPT_EXTRA = (
    "shepherd, shepherd staff, walking staff as main prop, cupbearer only, large cup as main prop, "
    "generic traveler, soldier armor, priestly robe, prophet robe, royal crown, throne, weapon, "
    "no trowel, no stone block, no measuring cord, no rebuilding plan, empty hands, "
    "modern construction helmet, modern tools, modern hammer, power tool, "
    "timid expression, weak posture, oversized head, huge face, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
SARAH_NEGATIVE_PROMPT_EXTRA = (
    "frail old woman, fully white hair, fully silver hair, severe wrinkles, hunched back, "
    "generic grandmother, weak body, timid expression, teenage girl, young maiden, royal court queen, "
    "cropped feet, missing sandals, waist-up crop, close-up portrait"
)
RACHEL_NEGATIVE_PROMPT_EXTRA = (
    "plain severe face, harsh angular ugly face, old woman, gray hair, tired expression, "
    "seductive pose, exposed body, royal queen, Sarah, Leah, generic servant, dull robe, "
    "cropped feet, missing sandals, waist-up crop, close-up portrait"
)
SAMUEL_NEGATIVE_PROMPT_EXTRA = (
    "sub-Saharan African features, very dark skin tone, foreign priest, Egyptian priest, "
    "generic gray scholar, frail weak old man, stooped tired grandfather, child Samuel, young Samuel, "
    "boy priest, smooth youthful face, black hair only, king, crown, spear, weapon, royal mantle, "
    "overly dark brown face, green skin, olive-green skin, yellow-green face, sallow green cast, "
    "blank dot eyes, timid expression, cropped feet, missing sandals, waist-up crop, close-up portrait"
)
SAUL_NEGATIVE_PROMPT_EXTRA = (
    "evil villain, cruel tyrant caricature, demonic face, wicked sneer, murderous expression, "
    "monster king, fully corrupt posture, rage face, raised weapon attack pose, "
    "perfect saint, overly gentle smiling saint, David, Solomon, generic noble king, "
    "cropped feet, missing sandals, waist-up crop, close-up portrait"
)
CALEB_NEGATIVE_PROMPT_EXTRA = (
    "turnaround sheet, character model sheet, reference sheet, concept sheet, "
    "front and back view, front view and rear view, back view, rear view, "
    "side-by-side poses, multiple poses, duplicate pose, second view, "
    "split screen, vertical center seam, mirrored figure, back-facing figure, "
    "rear-facing figure, extra full body view, shoulder pole, long pole across shoulders, "
    "thick black outline, heavy dark outline, comic ink lines, sticker outline, "
    "bold stroke, dark contour stroke, cel-shaded game art, toy mascot, "
    "chunky game character, stubby legs, oversized head, short body, squat proportions, "
    "large cartoon shoes, black line art around clothing, high contrast outline, "
    "timid expression, sad expression, blank passive face, weak posture, "
    "drooping shoulders, limp arms, hesitant pose, gardener, farmer holding produce, "
    "cute soft mascot, childlike innocence, handsome slim court noble, delicate fashion model, "
    "skinny body, narrow shoulders, angry warrior, aggressive fighter, armor"
)
ABSALOM_NEGATIVE_PROMPT_EXTRA = (
    "multiple people, crowd, group, duo, pair, two people, extra character, "
    "background character, army, battle scene, rebellion scene, throne room scene, "
    "David appearing, king beside him, soldiers, horse, mule, tree, oak tree, "
    "hanging hair, hair caught in branches, death scene, corpse, blood, gore, "
    "crown, crowned king, modern clothing, fantasy armor, helmet, readable label, readable text"
)
JUDGES_AVATAR_NEGATIVE_PROMPT_EXTRA = (
    "turnaround sheet, character model sheet, reference sheet, concept sheet, "
    "front and back view, back view, side-by-side poses, multiple poses, "
    "duplicate pose, second view, split screen, mirrored figure, extra full body view, "
    "thick black outline, heavy dark outline, comic ink lines, sticker outline, "
    "bold stroke, dark contour stroke, cel-shaded game art, toy mascot, "
    "chunky game character, stubby legs, oversized head, short body, squat proportions, "
    "large cartoon shoes, modern clothing, modern armor, helmeted fantasy warrior, "
    "readable label, readable text"
)
JUDGE_SPECIFIC_NEGATIVE_PROMPTS = {
    "othniel": "king, crown, royal throne, extra army, battle scene, blood, gore",
    "ehud": (
        "stabbing scene, king on throne, Eglon, blood, gore, violent wound, "
        "right-handed sword pose, two daggers, extra king, palace scene, "
        "reference character appearing, Gideon appearing, Joshua appearing, "
        "Samson appearing, copied reference avatar, duplicate Ehud, cloned figure, "
        "companion, attendant, guard, servant, messenger partner, second man, "
        "third person, crowd, group, two people, three people, multiple people"
    ),
    "shamgar": "battle scene, dead bodies, ox, cattle herd, blood, gore",
    "deborah": (
        "male, man, masculine face, broad male jaw, square male shoulders, beard, "
        "mustache, facial hair, armor, soldier, sword, second woman, Barak, palm tree scene"
    ),
    "tola": "worm, insect, bug, beetle, red worm, crawling creature, childlike mascot",
    "jair": "thirty sons, many sons, crowd, group, donkey herd, many donkeys, city labels",
    "jephthah": (
        "daughter, child, young girl, sacrifice scene, fire altar, tragic family scene, "
        "blood, gore, crowd, extra soldiers"
    ),
    "ibzan": "many children, sons and daughters, wedding crowd, banquet scene, bride, groom",
    "elon": (
        "modern businessman, suit, tie, technology, rocket, billionaire, celebrity portrait, "
        "modern hair style, modern city background"
    ),
    "abdon": "many sons, many grandsons, crowd, group, donkey herd, many donkeys, city labels",
    "samson": (
        "Delilah, lion, temple scene, pillars falling, tied prisoner, blindfold, "
        "blood, gore, multiple people, battle scene"
    ),
}

# Codes that the model tends to draw as multiple/symbolic figures.
# Force them to render as exactly one solo character.
SOLO_NEGATIVE_PROMPT_EXTRA = (
    "multiple people, crowd, group, duo, pair, two people, extra character, "
    "background character, twin, mirrored figure, second character, secondary figure, "
    "scene with brother, scene with father, scene with attendants"
)
SOLO_FORCED_CODES = {
    "ahaz",
    "cyrus",
    "haggai",
    "hoshea_king",
    "jezebel",
    "jehoiada",
    "jeroboam",
    "jonah",
    "micaiah",
    "rehoboam",
    "zechariah_prophet",
    "zerubbabel",
}

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

# 단순 여성형 강제용 공통 차단. 새로 FEMALE_CODES 에 추가된 dinah/hannah/sapphira
# 처럼 모델이 종종 남성으로 그리는 인물들에 일괄로 적용.
FEMALE_FORCE_NEGATIVE_PROMPT_EXTRA = (
    "male, man, masculine face, broad male jaw, square male shoulders, "
    "beard, mustache, facial hair, stubble, warrior, armor, soldier"
)
FEMALE_FORCE_CODES = {"bathsheba", "dinah", "hannah", "priscilla", "rahab", "sapphira"}

HANNAH_NEGATIVE_PROMPT_EXTRA = (
    "elderly woman, old woman, grandmother, gray hair, white hair, wrinkled face, "
    "frail old body, aged prophetess, aged widow, Naomi, Sarah, Elizabeth, "
    "priestly robe, high priest garment, warrior, armor, crown, royal robe"
)

# lydia 도 같은 이유로 여성형 강제. 빌립보 자색 옷감 장수.
LYDIA_NEGATIVE_PROMPT_EXTRA = (
    "male, man, masculine face, broad male jaw, square male shoulders, "
    "beard, mustache, facial hair, "
    "warrior, armor, soldier, slave, prisoner, jailer, "
    "Samson, Delilah scene, judge-era man, Nazirite hair, muscular male, "
    "second character, multiple people"
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

# hagar 는 족장 시대 여성 팔레트로 묶이면 sarah 와 너무 비슷해진다.
# 단, prompt 에 다른 인물 이름/비교를 넣으면 Imagen 이 그 사람들을 같이 그릴 수
# 있으므로 "한 명의 젊은 성인 여성" 정보만 남긴다.
HAGAR_NEGATIVE_PROMPT_EXTRA = (
    "elderly woman, old woman, aged matriarch, wealthy noble mistress, jeweled matriarch, "
    "cream robe, soft rose robe, beige matriarch clothing, ornate headband, gold earrings, "
    "male, man, tall man, bearded man, masculine face, broad male jaw, "
    "male headcloth, masculine headdress, beard, mustache, facial hair, "
    "child, teenager, girl, baby, son, family scene, "
    "large central male figure, extra woman, duplicate woman, row of people, lineup, "
    "second character, companion, group, duo, trio, multiple people"
)

GOLIATH_NEGATIVE_PROMPT_EXTRA = (
    "kind smile, friendly expression, gentle posture, peaceful aura, warm welcoming gesture, "
    "slim build, delicate features, child, teenager, slim shoulders, small stature, "
    "unarmed, empty hands"
)

NAAMAN_NEGATIVE_PROMPT_EXTRA = (
    "prophet robe, priest robe, hooded prophet, layered prophet head covering, "
    "Samuel, elderly prophet, listening prophet silhouette, shepherd, sling, stone pouch, "
    "scroll, staff, plain Hebrew robe, soft spiritual teacher pose, "
    "severe disease horror, open sores, bleeding, gore, disfigured face, rotting skin, "
    "medical close-up, suffering crowd, second character, multiple people"
)

HOSHEA_KING_NEGATIVE_PROMPT_EXTRA = (
    "Hosea the prophet, prophet Hosea, minor prophet, biblical prophet, prophet robe, "
    "prophecy scroll, large scroll, preaching pose, Gomer, prophet family scene, "
    "scribe, priest, Samuel, Isaiah, Jeremiah, elderly prophet silhouette, "
    "Assyrian king, Assyrian commander, captor, prison scene, jail bars, chains, "
    "battle scene, siege scene, crowd, multiple people, readable label, readable text"
)

AHAZ_NEGATIVE_PROMPT_EXTRA = (
    "Ahab, northern king of Samaria, Hoshea king, Hezekiah, Josiah, faithful reform king, "
    "prophet Isaiah, court prophet, priest, Assyrian commander, Aram king, Pekah, Rezin, "
    "battle scene, siege army, baby Immanuel scene, woman and child, "
    "multiple people, crowd, readable label, readable text, "
    "wide horizontal canvas, landscape aspect ratio, panoramic composition, 16:9 frame, "
    "extra-wide side margins, tiny distant character, off-center character"
)

JONAH_NEGATIVE_PROMPT_EXTRA = (
    "Jonathan, Saul's son, prince Jonathan, David's friend, royal prince, king's son, "
    "handsome warrior prince, bow and arrows, palace scene, friendship covenant scene, "
    "multiple people, sailors, ship crew, Nineveh crowd, city crowd, "
    "giant fish swallowing scene, inside fish belly, ocean storm scene, ship deck scene, "
    "elderly prophet, Samuel, Isaiah, copied prophet avatar, readable label, readable text"
)

MICAIAH_NEGATIVE_PROMPT_EXTRA = (
    "Micah the minor prophet, prophet Micah of Moresheth, book of Micah, "
    "Ahab king, Jehoshaphat king, Zedekiah son of Chenaanah, false prophets, "
    "crowded throne room scene, many prophets, horn props, battle scene, prison scene, "
    "king, crown, royal robe, court official, soldier, armor, helmet, "
    "Samuel, Isaiah copied avatar, Elijah copied avatar, Elisha copied avatar, "
    "multiple people, crowd, duo, readable label, readable text, "
    "portrait crop, bust shot, half body, cropped feet, missing sandals"
)

JEREMIAH_NEGATIVE_PROMPT_EXTRA = (
    "Isaiah copied avatar, Samuel, child Samuel, Ezekiel, Ezra, Haggai, Zechariah, "
    "king, crown, royal robe, priestly breastplate, temple incense scene, heavenly throne vision, "
    "seraphim, valley of dry bones, Baruch writing beside him, scribe desk, prison pit, mud pit, "
    "scroll burning scene, smashed jar scene, battle scene, siege army, "
    "multiple people, crowd, duo, readable label, readable text, "
    "portrait crop, bust shot, half body, close-up face, cropped feet, missing sandals"
)

EZEKIEL_NEGATIVE_PROMPT_EXTRA = (
    "generic prophet, generic priest, Ezra scribe-priest, Isaiah court prophet, Jeremiah weeping prophet, "
    "Samuel, Elijah, Elisha, Daniel court sage, king, crown, royal sash, royal robe, throne, "
    "scribe desk, writing table, temple incense scene, priestly breastplate, high-priest outfit, "
    "heavenly throne vision, living creatures, wheels full of eyes, valley scene, dry bones crowd, "
    "multiple people, crowd, readable label, readable text, portrait crop, bust shot, half body, "
    "close-up face, cropped feet, missing sandals"
)

JEHOIAKIM_NEGATIVE_PROMPT_EXTRA = (
    "Jehoiachin, Jehoahaz, Zedekiah, Josiah, righteous reform king, humble faithful king, "
    "Jeremiah, Baruch, prophet robe, scribe desk, scroll burning scene, open flame, "
    "Babylonian king, Nebuchadnezzar, Pharaoh Necho, Egyptian crown, captive prisoner, chains, "
    "battle scene, siege army, multiple people, crowd, readable label, readable text, "
    "wide horizontal canvas, landscape aspect ratio, panoramic composition, 16:9 frame, "
    "portrait crop, bust shot, half body, cropped feet, missing sandals"
)

JEHOIADA_NEGATIVE_PROMPT_EXTRA = (
    "king, crown, throne, royal diadem, young prince, child Joash, Athaliah, palace coup scene, "
    "coronation crowd, soldiers, guards, battle scene, execution scene, assassination scene, "
    "prophet mantle, Isaiah, Samuel copied avatar, warrior armor, helmet, sword, spear, "
    "multiple people, crowd, group, attendants, readable label, readable text, "
    "wide horizontal canvas, landscape aspect ratio, panoramic composition, 16:9 frame, "
    "portrait crop, bust shot, half body, cropped feet, missing sandals"
)

JEZEBEL_NEGATIVE_PROMPT_EXTRA = (
    "Esther, Persian queen, gentle heroine, salvation heroine, Athaliah, queen of Judah, "
    "Judah crown, Davidic line, motherly expression, faithful worshipper, prophetess, priestess, "
    "male, man, masculine face, broad male jaw, beard, mustache, facial hair, warrior armor, "
    "Ahab standing beside her, Jehu scene, window fall scene, Naboth stoning scene, dogs, "
    "blood, gore, corpse, injury, body falling, execution scene, "
    "multiple people, crowd, group, attendants, readable label, readable text, "
    "wide horizontal canvas, landscape aspect ratio, panoramic composition, 16:9 frame, "
    "portrait crop, bust shot, half body, cropped feet, missing sandals"
)

DIVIDED_KINGDOM_KING_NEGATIVE_PROMPT_EXTRA = (
    "prophet robe, priest robe, temple prophet, scribe robe, ordinary shepherd, "
    "modern monarch, European crown, medieval king, fantasy armor, helmet, "
    "battle panorama, active fighting, killing scene, assassination scene, execution scene, "
    "blood, gore, corpse, dead body, injury close-up, prison bars, chains, "
    "multiple people, crowd, group, attendants, army, readable label, readable text, "
    "same face as another divided-kingdom king, cloned facial features, identical beard, "
    "identical crown band, identical expression, "
    "wide horizontal canvas, landscape aspect ratio, panoramic composition, 16:9 frame, "
    "portrait crop, bust shot, half body, cropped feet, missing sandals"
)

ZERUBBABEL_NEGATIVE_PROMPT_EXTRA = (
    "Persian king, Cyrus, Darius, crowned monarch, golden crown, royal throne, "
    "Solomon, David, Jesus genealogy scene, newborn, family tree, "
    "completed palace scene, modern architect, hard hat, blueprint, "
    "multiple people, crowd, construction crew surrounding him, readable label, readable text"
)

HAGGAI_NEGATIVE_PROMPT_EXTRA = (
    "Zechariah, Zechariah prophet, Zechariah father of John, priest Zechariah, "
    "Elizabeth, baby John, temple incense scene, mute priest, priestly breastplate, "
    "young royal governor, Zerubbabel, construction crowd, "
    "multiple people, crowd, duo, readable label, readable text"
)

ZECHARIAH_PROPHET_NEGATIVE_PROMPT_EXTRA = (
    "Zechariah father of John the Baptist, priest Zechariah, elderly priest, "
    "Elizabeth, baby John, temple incense, angel Gabriel announcing birth, mute priest scene, "
    "Haggai, Zerubbabel, construction scene, crown, king, "
    "multiple people, crowd, duo, readable label, readable text"
)

ISAIAH_NEGATIVE_PROMPT_EXTRA = (
    "Samuel, child Samuel, young Samuel, listening prophet silhouette, "
    "tabernacle lamp, priestly child robe, hooded prophet, layered hood-like head covering, "
    "wrapped geometric headcloth, soft angular oval face, mustache with a short beard, "
    "purple-navy Samuel robe, gentle listening pose, ordinary hooded elderly prophet, "
    "duplicate Samuel, copied Samuel avatar, Ezra, scribe-only scholar, king, crown, "
    "seraphim, angel, heavenly host, extra character, multiple people, "
    "portrait crop, bust shot, half body, waist-up crop, close-up face, cropped robe, "
    "cropped feet, missing feet, cropped sandals, giant scroll covering the body, "
    "tongs touching lips, burning mouth, injury, gore, readable text"
)

FEMALE_CODES = {
    "bathsheba",
    "bilhah",
    "deborah",
    "delilah",
    "dinah",
    "elizabeth",
    "esther",
    "eve",
    "hagar",
    "hannah",
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
    "rahab",
    "rebekah",
    "ruth",
    "sapphira",
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
    "adam": [
        "first human build with simple dignified strength, not a fisherman and not an apostle",
        "natural warm peach-beige ancient human face with alert innocent eyes, dark natural hair, and short natural beard",
        "modest rough animal-skin leather tunic with simple leather belt, bare forearms and sandals",
        "empty hands or one open hand only, no tools, no fishing net, no staff, no weapon",
    ],
    "esther": [
        "slender graceful build",
        "soft elegant oval face with refined feminine beauty",
        "long dark hair under a royal veil with geometric jewel accents",
    ],
    "eve": [
        "slender graceful build",
        "soft delicate natural warm peach-beige face with gentle feminine features",
        "long flowing hair with soft faceted strands",
        "modest rough animal-skin leather dress with simple leather wrap and sandals, not royal and not exposed",
    ],
    "eli": [
        "elderly Shiloh priest build with dignified but heavy shoulders, not a generic tribal elder",
        "weathered warm Hebrew face with gray-white hair, full white-gray beard, heavy brows, and gentle watchful priestly eyes",
        "white linen priest robe, cream ephod, muted blue-gold sash, and simple priestly head wrap, clearly priestly",
        "small tabernacle lamp or incense censer held low as his identifying priestly object",
    ],
    "gabriel": [
        "tall luminous figure with graceful proportions",
        "smooth serene face with gentle heavenly features",
        "soft radiant hair framed by simple glowing planes",
    ],
    "hannah": [
        "young adult Israelite woman, around late twenties to early thirties, not elderly",
        "soft warm peach-beige face with sorrowful but gentle eyes, no wrinkles, no gray hair",
        "modest Shiloh pilgrim clothing with a simple warm clay veil and muted olive dress, not priestly and not royal",
        "small empty hands lifted in prayer, no baby in the base avatar, no staff, no scroll",
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
        "tall broad-shouldered Aramean military commander build",
        "sharp angular officer face with strong straight nose and stern focused eyes",
        "short well-groomed dark hair under a bronze Aramean commander headband",
        "trimmed dark beard befitting a high-ranking officer",
        "subtle pale leprosy patches on one cheek and one visible hand, clean and non-gory",
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
    "hagar": [
        "slender resilient young adult feminine build",
        "youthful adult oval face with gentle Egyptian features",
        "dark hair fully tucked under a plain deep indigo headscarf",
    ],
    "zerubbabel": [
        "mature post-exile Judah governor build with sturdy civic-leader shoulders",
        "rectangular determined face with tired but faithful eyes and a practical brow",
        "short dark hair under a simple Persian-period Judean official headband",
        "trimmed dark beard with clean angular planes",
    ],
    "haggai": [
        "elderly restoration prophet build with compact upright shoulders",
        "weathered oval face with piercing urgent eyes and deep forehead lines",
        "short gray hair under a plain prophet's headcloth, not priestly",
        "full gray beard with blocky faceted strands",
    ],
    "zechariah_prophet": [
        "young adult visionary restoration prophet build, lean and alert",
        "long narrow face with bright watchful eyes and contemplative brow",
        "medium dark hair under a simple muted indigo head wrap, not priestly",
        "short neat dark beard with angular faceted planes",
    ],
    "absalom": [
        "tall graceful royal prince build with confident upright posture",
        "striking handsome angular face with proud eyes and refined royal features",
        "very long thick dark hair flowing in layered geometric locks as his main identifying feature",
        "short neat princely beard, carefully groomed",
    ],
    "caleb": [
        "mature broad-shouldered traveler build matching the existing Joshua avatar proportions",
        "long wedge-shaped face with firm brow, clear unwavering eyes, and simple small features",
        "medium wavy dark hair in angular chunks with a narrow muted headband",
        "short angular beard with soft faceted planes",
    ],
    "jeroboam": [
        "strong ambitious royal official build with squared shoulders",
        "sharp angular face with watchful eyes and a determined brow",
        "short dark hair under a narrow northern official headband",
        "trimmed angular beard with crisp faceted planes",
    ],
    "rehoboam": [
        "young royal heir build with polished but slightly uncertain bearing",
        "smooth square princely face with cautious eyes",
        "neatly arranged dark hair under a simple royal headband",
        "short tidy beard, less severe than Jeroboam",
    ],
    "ahab": [
        "middle-aged northern king build with squared royal shoulders",
        "hard angular face with proud narrowed eyes and a stubborn brow",
        "dark hair under an ornate but restrained northern royal headband",
        "short dark beard with sharply faceted planes",
    ],
    "ahaz": [
        "young-to-middle-aged Judah king build with broad royal shoulders and upright palace bearing",
        "anxious but kingly angular face with wary eyes, strong brow, and controlled royal dignity",
        "short dark hair beneath a small angular gold Judah crown diadem, clearly a king not an official",
        "trimmed dark beard with crisp regal faceted planes",
    ],
    "hoshea_king": [
        "middle-aged final northern Israel king build with tense royal shoulders",
        "long narrow weary face with worried eyes and a guarded anxious brow",
        "short dark hair under a simple bronze Samaria royal headband",
        "trimmed dark beard with slightly uneven faceted planes",
    ],
    "jonah": [
        "weathered northern prophet build with compact traveler proportions",
        "rectangular anxious face with wary eyes, furrowed brow, and a reluctant expression",
        "short dark hair partly visible under a simple sea-teal travel headwrap",
        "short uneven dark beard with angular faceted planes",
    ],
    "micaiah": [
        "solitary northern court-prophet build with lean upright shoulders",
        "long angular face with steady fearless eyes, strong nose, and uncompromising brow",
        "medium dark hair under a plain charcoal prophet headcloth, not royal",
        "short dark beard with sharp faceted planes and a few gray streaks",
    ],
    "jeremiah": [
        "lean sorrowful Judah prophet build with narrow shoulders but steady upright resolve",
        "long angular face with tearful compassionate eyes, strong nose, and deeply furrowed brow",
        "dark wavy hair with gray streaks tied back by a plain clay-brown headband, not hooded",
        "medium dark beard with gray streaks and weathered faceted strands",
    ],
    "jehoiakim": [
        "middle-aged Judah king build with broad royal shoulders and heavy palace bearing",
        "hard angular royal face with narrowed proud eyes, sharp nose, and stubborn brow",
        "short dark hair beneath an angular gold Judah crown diadem with a small red jewel",
        "trimmed dark beard with crisp severe faceted planes",
    ],
    "isaiah": [
        "tall narrow Jerusalem court-prophet build with solemn upright shoulders",
        "long rectangular face with high cheekbones, deep-set visionary eyes, and a grave brow",
        "uncovered gray-streaked wavy hair swept back, no hood and no wrapped head covering",
        "long split gray beard with angular faceted planes",
        "full robe length visible down to both sandals, lower body and feet clearly visible",
    ],
    "othniel": [
        "steady mature tribal commander build with broad but compact shoulders",
        "square Judahite face with firm brow and calm courageous eyes",
        "short blocky dark curls held by a simple muted cloth band",
        "trimmed angular beard",
    ],
    "ehud": [
        "compact agile Benjaminite judge build with a solitary balanced stance",
        "diamond-shaped face with alert narrow eyes and controlled expression",
        "closely cropped faceted dark hair under a small travel headcloth",
        "short neat beard",
    ],
    "shamgar": [
        "rugged farmer-judge build with strong work-worn forearms",
        "hexagonal weathered face with practical steady eyes",
        "rough medium-length dark hair in angular chunks",
        "full blocky beard",
    ],
    "deborah": [
        "dignified mature feminine judge build with upright composed shoulders",
        "wise angular oval face with clear discerning eyes and gentle strength",
        "dark hair fully covered by a layered olive head veil",
    ],
    "tola": [
        "quiet sturdy elder-judge build with modest compact proportions",
        "soft rectangular face with thoughtful settled eyes",
        "wrapped geometric headcloth framing the face",
        "short gray-streaked angular beard",
    ],
    "jair": [
        "prosperous but humble Gilead elder build with broad stable posture",
        "rounded hexagonal face with kind authoritative eyes",
        "short dark hair under a simple clay-brown head wrap",
        "full neatly shaped beard",
    ],
    "jephthah": [
        "weathered outcast-warrior build with lean powerful shoulders",
        "long wedge-shaped face with sorrowful stern eyes and scarred-looking facets",
        "untidy shoulder-length dark hair in rough polygon strands",
        "short rugged beard",
    ],
    "ibzan": [
        "peaceful Bethlehem elder build with soft broad shoulders",
        "soft angular oval face with warm clan-leader expression",
        "neatly wrapped muted headcloth with a small woven tassel",
        "trimmed gray-streaked beard",
    ],
    "elon": [
        "calm Zebulun elder-judge build with tall narrow proportions",
        "rectangular face with quiet thoughtful eyes",
        "straight shoulder-length hair under a blue-green tribal headband",
        "trimmed faceted beard",
    ],
    "abdon": [
        "well-established Pirathon elder build with dignified stable shoulders",
        "broad square face with generous but serious eyes",
        "medium wavy gray-streaked hair under a simple gold-clay head wrap",
        "full blocky gray-streaked beard",
    ],
    "samson": [
        "powerful Nazirite judge build, muscular but still matching the cast's compact proportions",
        "strong angular face with heavy brow and intense prayerful eyes",
        "long uncut dark hair falling in heavy geometric locks",
        "full blocky beard",
    ],
}

CHARACTER_MOOD_OVERRIDES = {
    "adam": [
        "front-facing first-human posture, one hand open in wonder and the other relaxed, no fishing or labor prop",
    ],
    "esther": ["gentle confident smile and poised posture"],
    "eve": [
        "front-facing first-woman posture with gentle alert eyes, hands relaxed near the leather garment",
    ],
    "hannah": [
        "front-facing prayerful posture, sorrowful hope in the eyes, a young adult woman longing for a child",
    ],
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
        "disciplined but burdened commander's posture, proud yet visibly troubled by illness",
    ],
    "achan": [
        "shrinking nervous posture with shoulders hunched, guilty downcast expression",
    ],
    "ahab": [
        "proud hardened kingly posture, chin lifted with stubborn defiance",
    ],
    "ahaz": [
        "front-facing solitary royal king posture, one hand holding a short gold scepter close to the body and the other resting on a heavy royal mantle, visibly anxious but unmistakably a king",
    ],
    "hoshea_king": [
        "somber final-king posture, shoulders tense, one hand holding a small blank broken tribute tablet close to the chest",
    ],
    "jonah": [
        "reluctant but called prophet posture, shoulders slightly turned as if resisting the journey, one hand holding a small blank message scroll close to the chest and the other near a tiny fish-shaped travel token",
    ],
    "micaiah": [
        "front-facing solitary truth-telling prophet posture, one hand holding a small blank court-warning scroll near the chest and the other raised calmly as if refusing false prophecy",
    ],
    "jeremiah": [
        "front-facing solitary weeping-prophet posture, one hand holding a narrow blank warning scroll near the heart and the other holding a small cracked clay jar shard, sorrowful but unshaken",
    ],
    "jehoiakim": [
        "front-facing solitary defiant king posture, chin lifted, one hand holding a short gold scepter and the other gripping a sealed royal decree scroll, proud and resistant to prophetic warning",
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
    "hagar": [
        "calm resilient standing posture with both arms relaxed at sides",
    ],
    "zerubbabel": [
        "steady rebuilding-leader posture, one hand holding a small foundation stone and the other a blank work order scroll, resolved but humble",
    ],
    "haggai": [
        "urgent prophetic posture, one hand raised in exhortation and the other holding a small blank oracle scroll close to the chest",
    ],
    "zechariah_prophet": [
        "visionary prophetic posture, one hand holding a small measuring cord and the other a blank vision scroll, eyes lifted with hope",
    ],
    "isaiah": [
        "small full-body standing avatar pose with generous white margin, one hand holding a narrow open blank prophecy scroll close to the torso, the other near a small ember-coal clasp at the chest, both sandals visible, eyes lifted with holy awe",
    ],
    "caleb": [
        "single front-facing standing pose, shoulders squared and chest lifted, steady faithful expression, one hand held near the heart in conviction, the other hand holding a small grape cluster close to the body",
    ],
    "jeroboam": [
        "front-facing solitary official posture, ambitious and alert, one hand holding a small torn cloak piece as a restrained symbol",
    ],
    "rehoboam": [
        "front-facing solitary young king posture, one hand near a folded royal mantle, cautious and dignified",
    ],
    "othniel": [
        "calm courageous judge posture, one hand resting near a sheathed short sword, not fighting",
    ],
    "ehud": [
        "absolute solo avatar pose, front-facing and centered, left hand clearly emphasized near a small sheathed dagger at the waist, right arm relaxed, no one standing beside him",
    ],
    "shamgar": [
        "steady farmer-defender posture holding a long wooden oxgoad vertically like a staff",
    ],
    "deborah": [
        "wise prophetic judge posture, one hand lifted gently as if giving counsel and the other holding a small scroll",
    ],
    "tola": [
        "modest settled judge posture holding a simple staff close to the body",
    ],
    "jair": [
        "dignified Gilead elder posture holding a small rolled map with simple dot marks",
    ],
    "jephthah": [
        "resolute but sorrow-aware posture, weathered cloak draped over one shoulder, hands kept peaceful",
    ],
    "ibzan": [
        "warm elder judge posture with a small ceremonial staff and woven tassels",
    ],
    "elon": [
        "quiet faithful judge posture holding a simple tribal staff, calm and grounded",
    ],
    "abdon": [
        "honorable elder judge posture holding a carved walking staff with a small donkey medallion",
    ],
    "samson": [
        "strong but prayerful standing posture, hands near the chest in restrained strength, not attacking",
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
    "divided_kingdom": "structured royal-era silhouette",
    "prophets_exile": "solemn exile-era silhouette",
    "post_exile_return": "rebuilder-era silhouette",
    "gospels": "traveling teacher silhouette",
    "early_church": "mission-era silhouette",
}

CODE_PALETTE_OVERRIDES = {
    "abraham": "natural warm peach-beige skin + deep warm brown garment + muted clay red + warm cream accents, low saturation",
    "adam": "natural warm peach-beige skin + leather brown garment + earth umber + warm sand accents, low saturation",
    "absalom": "deep royal blue + muted crimson + warm gold accents, low saturation",
    "ahaz": "deep royal indigo + muted purple + warm gold trim + ash gray accent, low saturation",
    "bathsheba": "deep blue + muted bronze + warm cream accents, low saturation",
    "caleb": "muted teal + parchment cream + warm clay brown accents, low saturation",
    "deborah": "olive green + warm parchment + muted clay rose accents",
    "daniel": "deep emerald green + olive green + parchment cream + muted gold accents, low saturation",
    "ehud": "deep olive + desert tan + muted bronze accents",
    "eve": "natural warm peach-beige skin + leather brown garment + soft umber + warm sand accents, low saturation",
    "hagar": "desert teal + copper + deep indigo accents",
    "haman": "dark Persian violet + charcoal black + cold muted gold + blood-red accent, low saturation",
    "haggai": "weathered clay + parchment cream + muted crimson accents, low saturation",
    "hoshea_king": "storm blue + iron gray + muted bronze accents, low saturation",
    "isaiah": "deep indigo + ash gray + ember gold accents, low saturation",
    "isaac": "warm cream + muted olive + weathered tan accents, low saturation",
    "jehoiakim": "deep crimson + royal indigo + dark gold trim + ash gray accents, low saturation",
    "jeremiah": "weathered olive + clay brown + muted crimson + parchment cream accents, low saturation",
    "jeroboam": "deep forest green + muted bronze + parchment tan accents, low saturation",
    "judah": "deep wine red + warm tan + dark umber + muted gold accents, low saturation",
    "korah": "deep teal + desert tan + bronze censer + clay red accent, low saturation",
    "laban": "deep Aramean indigo + rich clay brown + dark teal + bronze accents, low saturation",
    "jonah": "sea teal + storm gray + parchment cream accents, low saturation",
    "micaiah": "deep olive + muted charcoal + pale parchment + small gold accents, low saturation",
    "rehoboam": "royal indigo + warm gold + muted ivory accents, low saturation",
    "rahab": "teal + sand headscarf + clay brown accents, low saturation",
    "noah": "weathered wood brown + olive work robe + warm cream + muted sky blue accent, low saturation",
    "rachel": "soft rose + warm cream + muted teal accents, low saturation",
    "sarah": "soft rose-brown + warm cream + muted blue accents, low saturation",
    "samson": "deep olive + clay brown + muted gold accents",
    "zechariah_prophet": "muted indigo + sage green + parchment cream accents, low saturation",
    "zerubbabel": "deep olive + stone gray + muted gold accents, low saturation",
}

CODE_SIGNATURE_HINTS = {
    "adam": [
        "Adam the first human man, exactly one man only",
        "modest rough animal-skin leather tunic after Eden, simple leather belt, bare forearms and sandals",
        "open empty hands with first-human wonder, no fishing net, no staff, no tools, no scroll",
        "natural warm peach-beige ancient human skin tone, clear lighter face, alert innocent eyes, not a fisherman and not an apostle",
    ],
    "abraham": [
        "central covenant patriarch silhouette, protagonist-level presence, age seventy-five or older but strong",
        "front-facing majestic weathered face with natural warm peach-beige skin, gray-white beard, calm confident faithful eyes looking directly forward, and noble warmth",
        "rich warm-brown travel-worn layered robe, muted clay-red mantle or sash, tall walking staff, and founder-of-the-family presence",
        "not frail, not timid, not a generic old man, not a royal court figure",
    ],
    "aaron": [
        "mature Levite spokesman silhouette beside Moses, not high priest in the base avatar",
        "simple desert robe and staff, dark hair and full dark beard with no gray",
        "steady brotherly confidence for standing before Pharaoh",
    ],
    "absalom": [
        "royal prince of David's house silhouette, exactly one man only",
        "beautiful but restless king's son presence with proud confidence",
        "long heavy hair as the unmistakable identifying feature",
        "deep royal blue cloak over a muted crimson tunic with restrained gold trim",
        "small princely sash and signet-like belt ornament, no crown",
    ],
    "caleb": [
        "faithful wilderness scout silhouette in the same soft flat vector style as Moses and Joshua",
        "wholehearted courageous witness who trusts God when others are afraid",
        "muted robe and sash with gentle paper-cut facets, no visible ink outline",
        "small compact purple grape cluster kept secondary as a promised-land sign",
    ],
    "hannah": [
        "Hannah mother of Samuel before old age, young adult married Israelite woman, not elderly",
        "modest Shiloh worshiper clothing, warm clay veil over dark hair, muted olive dress, simple sandals",
        "tearful prayerful hope, gentle maternal warmth, no gray hair, no wrinkles, no grandmother look",
        "empty hands raised in quiet prayer, no priestly robe, no baby in the base avatar",
    ],
    "jeroboam": [
        "ambitious servant of Solomon who will become northern kingdom ruler",
        "deep green official cloak with bronze sash, no crown",
        "small torn cloak piece in one hand as a restrained sign of Ahijah's prophecy",
        "serious alert expression, not a battle scene",
    ],
    "ahijah": [
        "elderly prophet from Shiloh, wise and solemn, clearly distinct from Samuel and Isaiah",
        "clearly blind from old age: soft pale cataract-like eyes with almost no dark pupils, unfocused gaze past the viewer, calm listening expression, not frightening",
        "plain warm brown prophet mantle with a muted cream inner robe",
        "one hand holding torn pieces of a new outer garment as the unmistakable sign of the divided kingdom",
    ],
    "rehoboam": [
        "Solomon's royal son and heir silhouette",
        "royal indigo robe with warm gold sash, no oversized crown",
        "young princely presence with cautious confidence",
        "folded mantle detail, not a coronation scene",
    ],
    "ahab": [
        "northern kingdom king of Samaria silhouette, exactly one man only",
        "proud hardened ruler associated with Baal worship",
        "royal purple robe with navy mantle and muted gold headband",
        "small dark idol-shaped palace ornament kept secondary as a sign of apostasy",
        "no sling, no stone pouch, no shepherd accessory",
    ],
    "ahaz": [
        "Ahaz king of Judah, exactly one man only",
        "unmistakable Judah king silhouette, royal first and fearful second",
        "deep indigo royal robe with thick gold collar, gold belt, and heavy purple mantle",
        "small angular gold crown diadem and short gold scepter as clear royal identifiers",
        "hesitant worried expression during the Aram and Ephraim threat, not faithful Hezekiah and not northern king Ahab",
        "centered full-body figure inside a square 1:1 avatar canvas with balanced white margins",
    ],
    "hoshea_king": [
        "last king of Northern Israel in Samaria, exactly one man only",
        "somber fallen-king presence, distinct from Hosea the prophet",
        "storm-blue royal robe with iron-gray mantle and muted bronze headband",
        "small blank broken tribute tablet as a sign of failed Assyrian tribute, not a prophecy scroll",
        "anxious guarded expression, not a preacher and not an Assyrian captor",
    ],
    "zerubbabel": [
        "post-exile governor of Judah and temple-rebuilding leader, exactly one man only",
        "Davidic-line civic leader without crown or throne",
        "deep olive governor cloak over stone-gray tunic with muted gold sash",
        "small foundation stone and blank rebuilding order scroll as restrained signs",
        "humble determined expression, not a Persian king and not a modern builder",
    ],
    "haggai": [
        "post-exile prophet urging the people to rebuild the temple, exactly one man only",
        "weathered clay prophet mantle over parchment robe with muted crimson sash",
        "small blank oracle scroll and simple walking staff as restrained signs",
        "urgent exhorting expression, distinct from Zechariah and not a priestly incense scene",
    ],
    "zechariah_prophet": [
        "post-exile visionary prophet son of Berechiah, exactly one man only",
        "clearly distinct from Zechariah father of John the Baptist",
        "muted indigo mantle over sage-green robe with parchment sash",
        "small measuring cord and blank vision scroll as restrained signs of restoration visions",
        "hopeful watchful expression, not a temple incense scene and not a birth-announcement scene",
    ],
    "jonah": [
        "reluctant prophet son of Amittai sent toward Nineveh, exactly one man only",
        "clearly distinct from Jonathan the royal prince and from elderly court prophets",
        "sea-teal travel cloak over storm-gray tunic with parchment sash",
        "small blank message scroll and tiny fish-shaped travel token as restrained signs",
        "uneasy called-by-God expression, not a ship scene and not inside a fish",
    ],
    "micaiah": [
        "Micaiah son of Imlah, northern Israel prophet who spoke truth before Ahab, exactly one man only",
        "clearly distinct from Micah of Moresheth the minor prophet and from Samuel or Isaiah",
        "deep olive prophet mantle over muted charcoal robe with pale parchment sash",
        "small blank court-warning scroll held near the chest, no crown and no royal clothing",
        "fearless uncompromising expression, not a throne-room scene and not one of many prophets",
    ],
    "jeremiah": [
        "weeping prophet of Judah silhouette, exactly one man only",
        "sorrowful faithful prophet who warns Jerusalem with grief and courage",
        "weathered olive mantle over clay-brown robe with muted crimson sash",
        "small blank warning scroll and cracked clay jar shard as restrained prophetic signs",
        "tearful eyes and firm mouth, not Isaiah's court-prophet look and not Samuel",
    ],
    "jehoiakim": [
        "Jehoiakim king of Judah, exactly one man only",
        "unmistakable proud Judah king silhouette, royal and defiant",
        "deep crimson royal robe under royal indigo mantle with thick dark gold collar and belt",
        "small angular gold crown diadem with red jewel and short gold scepter as clear royal identifiers",
        "sealed royal decree scroll in one hand as a restrained sign of rejecting prophetic warning, not an active burning scene",
        "hard proud expression, not faithful Josiah, not captive Jehoiachin, and not blind Zedekiah",
    ],
    "othniel": [
        "first judge of Israel silhouette from Judah",
        "faithful deliverer and steady tribal leader presence",
        "plain olive judge cloak over a clay-brown tunic",
        "short bronze sword kept sheathed as a symbol of deliverance, not battle",
    ],
    "ehud": [
        "left-handed Benjaminite judge silhouette, exactly one man only",
        "compact agile presence with quiet courage, not a story scene",
        "muted travel cloak and one small sealed message pouch at the belt",
        "left hand visibly emphasized near a small sheathed dagger",
        "plain white background with no palace, no king, no guards, no companions",
    ],
    "shamgar": [
        "rugged farmer-judge silhouette from the era of judges",
        "work-worn defender presence without royal clothing",
        "plain short tunic with leather work belt",
        "long wooden oxgoad held upright as his distinctive accessory",
    ],
    "deborah": [
        "prophetess and judge of Israel silhouette, distinctly female",
        "wise counselor presence with calm spiritual authority",
        "layered olive veil and modest long robe with parchment accents",
        "small scroll and subtle palm-frond brooch as Deborah's palm sign",
    ],
    "tola": [
        "quiet judge of Israel from Issachar silhouette",
        "modest faithful elder presence rather than warrior champion",
        "simple olive-brown robe with an understated tribal sash",
        "plain staff and small folded judgment cloth, no insect imagery",
    ],
    "jair": [
        "Gilead elder judge silhouette with settled clan authority",
        "prosperous but humble presence, not royal",
        "earth-toned robe with a muted gold sash",
        "rolled map with simple dot marks symbolizing his towns",
    ],
    "jephthah": [
        "mighty warrior judge of Gilead silhouette",
        "weathered outcast leader presence with a serious faithful burden",
        "rough travel cloak over plain judge-era tunic",
        "empty peaceful hands, strength shown through posture not weapons",
    ],
    "ibzan": [
        "Bethlehem elder judge silhouette",
        "peaceful clan-leader presence with generous hospitality",
        "soft clay and olive layered robe with woven tassel details",
        "small ceremonial staff suggesting household leadership",
    ],
    "elon": [
        "biblical judge of Zebulun silhouette, ancient Israelite elder",
        "quiet steady presence, not modern and not royal",
        "blue-green Zebulun-toned cloak over simple earth robe",
        "plain tribal staff as a restrained judge symbol",
    ],
    "abdon": [
        "Pirathon elder judge silhouette with established household dignity",
        "honorable settled leader presence, wealthy but humble",
        "olive robe with muted gold-clay sash and simple sandals",
        "carved walking staff with a small donkey medallion symbol",
    ],
    "samson": [
        "Nazirite judge silhouette from the era of judges",
        "long uncut hair as the main identifying feature",
        "powerful restrained strength, not a fantasy warrior",
        "simple rugged tunic with bare forearms and muted judge-era sash",
    ],
    "daniel": [
        "court-wise exile silhouette",
        "calm dignified bearing with bright intelligent eyes",
        "rolled scroll accent",
    ],
    "david": [
        "central hero shepherd-king silhouette, protagonist-level presence",
        "confident faithful kingly bearing with bright intelligent eyes and warm courage",
        "small lyre held at the side, sling pouch at the belt, and restrained gold royal mantle trim",
    ],
    "elijah": [
        "rugged wilderness prophet silhouette, strong but not frightening",
        "normal warm dark eyes with visible pupils, serious human face, rough brown mantle energy",
    ],
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
        "Eve the first woman, exactly one woman only",
        "modest rough animal-skin leather dress after Eden, simple leather wrap and sandals",
        "natural warm peach-beige ancient human skin tone, clear lighter face, gentle expression with alert first-human wonder, no royal jewelry and no exposed body",
        "soft feminine presence, visually paired with Adam's leather garment style",
    ],
    "ezra": [
        "scribe-teacher silhouette",
        "measured studious bearing",
        "rolled scroll accent",
    ],
    "ezekiel": [
        "unmistakable Ezekiel exile priest-prophet silhouette by the Chebar canal, exactly one man only",
        "Babylonian exile-priest robe: deep indigo-gray mantle over parchment linen, ash-blue shoulder bands, small priestly cord, no crown and no royal sash",
        "one hand lifted in prophetic command and the other holding a small blank clay tablet or sealed blank vision scroll as a sign of symbolic actions",
        "visionary grief-and-hope presence: intense watchful eyes, furrowed brow, short dark beard with gray streaks, weathered exile face",
        "not Ezra's calm scribe desk look, not Isaiah's royal-court prophet look, not Jeremiah's weeping mud-prison look",
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
        "protected-yet-resilient bearing with bright intelligent eyes and a small catchlight",
        "patterned robe accent",
    ],
    "mary": [
        "humble courageous mother silhouette",
        "calm grounded presence",
        "layered travel veil",
    ],
    "hagar": [
        "single young adult Egyptian servant woman silhouette, one woman only",
        "plain desert teal ankle-length dress with a simple copper cloth sash",
        "deep indigo head scarf, no jewelry and no ornate headband",
        "small water-skin held at her side, standing alone",
        "humble desert servant presence, not a noble mistress",
        "full body single centered woman, no surrounding characters",
    ],
    "bathsheba": [
        "dignified Jerusalem woman who later becomes queen mother, exactly one woman only",
        "modest deep blue veil over dark braided hair, bronze water jar kept secondary",
        "poised but sorrow-aware face, never seductive or bathing-focused",
        "royal mother dignity for later scenes, no exposed body, no sexualized framing",
    ],
    "haman": [
        "Haman the arrogant Persian court villain from Esther, exactly one man only",
        "dark Persian violet court robe with charcoal-black mantle, cold muted-gold trim, and a small blood-red sash accent",
        "narrow suspicious eyes, sharp angular nose, thin curled mustache, tight cruel smirk, and proud lifted chin",
        "sealed decree scroll gripped in one hand and a signet ring held forward as signs of dangerous royal power",
        "threatening self-important posture, not heroic, not gentle, not a king and not a soldier",
    ],
    "isaiah": [
        "Jerusalem royal-court prophet silhouette, not a listening child-prophet",
        "deep indigo mantle over an ash-gray robe with parchment cream sash",
        "full-body standing figure with visible robe hem, legs, and sandals",
        "small narrow open blank prophecy scroll held upright and a small ember-coal clasp as Isaiah's calling sign",
        "stern visionary presence, uncovered hair, no hooded head covering",
    ],
    "isaac": [
        "adult covenant son silhouette, calm and thoughtful, not a small child",
        "short trimmed beard and steady obedient posture for the Moriah scene",
        "plain patriarchal robe with a small bundled firewood motif kept secondary",
    ],
    "moses": [
        "confident mature wilderness liberator silhouette, adult but not elderly in the base avatar",
        "dark hair with no gray and a strong full dark beard",
        "wooden staff held upright like a leader entrusted with God's work",
    ],
    "nehemiah": [
        "wall-rebuilder silhouette",
        "focused civic resolve",
        "builder's belt with wooden tools",
    ],
    "noah": [
        "ark-builder silhouette with clear woodworking identity",
        "weathered survivor presence, calm obedient builder",
        "builder's belt with wooden tools, one small wooden ark or boat model kept in hand",
    ],
    "paul": [
        "road-worn missionary silhouette",
        "intense teacher's focus",
        "rolled scroll or letter satchel",
    ],
    "rachel": [
        "strikingly beautiful young shepherdess and beloved matriarch silhouette",
        "large gentle eyes, graceful oval face, and warm radiant smile",
        "modest elegance, not royal and not seductive",
    ],
    "leah": [
        "plain modest matriarch silhouette",
        "simple gentle presence",
    ],
    "saul": [
        "first king silhouette",
        "simple geometric crown band or royal sash",
        "very tall presence with early humble dignity and a slight troubled shadow",
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
        "measured judicial calm with bright intelligent discerning eyes",
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
        "Aramean Syrian army commander serving the king of Aram, exactly one man only",
        "polished bronze scale armor cuirass over a deep red military tunic, decorative shoulder plates",
        "richly trimmed dark crimson commander cloak fastened at one shoulder",
        "bronze helmet or commander headband, short bronze sword at the belt",
        "small command baton in one hand and clean linen wrap on the other forearm",
        "visible but subtle leprosy sign: pale skin patches on hand and cheek, not grotesque",
        "authoritative battlefield officer presence, distinctly a foreign general not an Israelite prophet",
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
    "priscilla": [
        "Greco-Roman era tentmaker and scripture-teaching woman silhouette, distinctly female",
        "modest travel-ready long robe with teal and warm brown accents, neat head covering",
        "small folded tent cloth and blank teaching scroll kept secondary as signs of ministry with Aquila",
        "wise attentive teacher presence, calm but confident",
    ],
    "rahab": [
        "young adult courageous Jericho woman silhouette, distinctly female and modest",
        "front-facing youthful warm face with alert protective eyes, dark hair under a sand-colored headscarf",
        "teal outer robe, brown shoulder shawl, slim young adult build, not elderly and not side-facing",
        "small scarlet cord kept secondary as her story sign, not a decorative ribbon",
        "alert protective posture of someone hiding the scouts, no sensual framing and no walking pose",
    ],
    "sarah": [
        "mature beautiful covenant matriarch silhouette, graceful and strong, not frail in the base avatar",
        "warm dignified face with wise gentle eyes, subtle age lines, and covenant-mother presence",
        "mostly dark hair under a modest layered veil, only faint silver at the temples if visible",
        "soft rose-brown mantle over warm cream robe with muted blue accents, not a royal court woman",
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

FEMALE_CODES.update(
    code
    for code, data in DIVIDED_KINGDOM_KING_ROSTER.items()
    if data.get("gender") == "female"
)
CHARACTER_VISUAL_OVERRIDES.update(
    {
        code: data["visual"]
        for code, data in DIVIDED_KINGDOM_KING_ROSTER.items()
        if data.get("visual")
    }
)
CHARACTER_MOOD_OVERRIDES.update(
    {
        code: data["mood"]
        for code, data in DIVIDED_KINGDOM_KING_ROSTER.items()
        if data.get("mood")
    }
)
CODE_PALETTE_OVERRIDES.update(
    {
        code: data["palette"]
        for code, data in DIVIDED_KINGDOM_KING_ROSTER.items()
        if data.get("palette")
    }
)
CODE_SIGNATURE_HINTS.update(
    {
        code: data["signature"]
        for code, data in DIVIDED_KINGDOM_KING_ROSTER.items()
        if data.get("signature")
    }
)
CHARACTER_VISUAL_OVERRIDES["jehoiada"] = [
    "elderly Jerusalem high-priest build with dignified upright shoulders and calm strength",
    "long wise face with steady protective eyes, heavy gray brows, and a firm compassionate mouth",
    "white and gray hair mostly covered by a layered cream priestly turban with a narrow gold band",
    "full white-gray beard in neat angular facets, clearly priestly and not a royal king beard",
]
CHARACTER_MOOD_OVERRIDES["jehoiada"] = [
    "protective covenant-priest posture, one hand holding a small sealed covenant scroll high near the chest and the other resting calmly over a gold priestly sash",
]
CODE_PALETTE_OVERRIDES["jehoiada"] = (
    "temple linen white + warm parchment cream + muted gold + deep olive accents, low saturation"
)
CODE_SIGNATURE_HINTS["jehoiada"] = [
    "Jehoiada the Jerusalem temple priest who protected Joash, exactly one man only",
    "elderly faithful priestly leader, not a prophet and not a king",
    "white linen priest robe with cream outer layer, muted gold sash, and small square priestly breast panel high on the chest",
    "small sealed covenant scroll held near the upper chest as a sign of restoring the covenant and protecting the Davidic line",
    "calm resolute expression with holy courage, no crown and no throne",
]
CHARACTER_VISUAL_OVERRIDES["jezebel"] = [
    "Sidonian royal queen build with tall elegant posture and sharply controlled shoulders",
    "angular refined face with cold calculating eyes, arched brows, and a firm unsmiling mouth",
    "dark braided hair arranged beneath a jeweled Phoenician-style veil and narrow gold headpiece",
    "slender hands held near the upper chest, one hand holding a small sealed royal letter with a wax seal",
]
CHARACTER_MOOD_OVERRIDES["jezebel"] = [
    "cold commanding queen posture, sealed royal letter held high near the chest as a sign of schemes and royal influence",
]
CODE_PALETTE_OVERRIDES["jezebel"] = (
    "deep crimson + Phoenician gold + dark teal + black-violet accents, low saturation"
)
CODE_SIGNATURE_HINTS["jezebel"] = [
    "Jezebel the Sidonian queen of Northern Israel, exactly one woman only",
    "adult Phoenician royal woman, not Esther and not Athaliah",
    "deep crimson and dark teal royal dress with Phoenician gold trim, jeweled veil, and narrow gold headpiece",
    "small sealed royal letter held near the upper chest as a sign of Naboth's false accusation plot",
    "cold calculating expression, glamorous but spiritually dangerous presence, no violence scene",
]

# 구약 주요 인물은 같은 직분끼리 옷과 얼굴이 쉽게 닮아 보인다. 특히 같은
# 이야기 안에서 함께 서는 인물들은 색, 소품, 체형, 표정이 바로 구분되도록
# 마지막에 한 번 더 덮어쓴다.
CHARACTER_VISUAL_OVERRIDES.update(
    {
        "ahab": [
            "middle-aged northern Israel king build with hard squared royal shoulders and dangerous pride",
            "hard angular face with narrowed malicious eyes, stubborn brow, and a cold idolatrous smirk",
            "dark hair under an ornate northern royal headband, short sharply faceted dark beard",
            "deep royal purple robe with navy mantle and muted gold trim, one hand gripping a small dark Baal idol figure held clearly near the chest",
        ],
        "ahijah": [
            "elderly Shiloh prophet build with lean upright shoulders, wise but not frightening",
            "ancient Hebrew face with soft pale cataract-like blind eyes, almost no dark pupils, unfocused gaze past the viewer, and no visible injury",
            "gray hair under a simple warm-brown prophet headcloth, short gray beard with angular facets",
            "plain warm-brown prophet mantle over cream robe, torn cloak pieces held clearly as the divided-kingdom sign",
        ],
        "abraham": [
            "majestic elderly covenant-patriarch build with upright steady shoulders, strong despite age",
            "front-facing natural warm peach-beige weathered long face with deep smile lines, calm confident faithful eyes looking directly forward, and strong noble nose",
            "white-gray hair under a sand-colored headcloth, never youthful dark hair",
            "full white-gray beard with broad angular facets, deep warm-brown cloak with muted clay-red mantle or sash and restrained warm-gold trim",
        ],
        "asher": [
            "Asher son of Jacob build with sturdy peaceful tribal-son proportions, not a Joseph-like dreamer",
            "natural warm peach-beige face with healthy color, gentle alert eyes, and a short neat beard",
            "warm olive and cream robe with rich honey-tan sash, not faded or gray",
            "small olive branch, round bread loaf, and grain sheaf kept close as signs of rich food and blessing",
        ],
        "sarah": [
            "mature beautiful covenant-matriarch build with dignified upright posture and slender shoulders, not frail in the base avatar",
            "warm graceful face with subtle age lines, wise gentle eyes, and restrained covenant-mother dignity",
            "mostly dark hair tucked under a soft rose-brown veil with warm cream layers, only faint silver at the temples if visible",
        ],
        "isaac": [
            "adult covenant-son build, calm and strong enough to carry firewood, not a child",
            "thoughtful oval face with obedient eyes and a short trimmed beard",
            "muted olive headcloth with a small bundled-firewood strap as a restrained sign",
        ],
        "judah": [
            "Judah son of Jacob and ancestor of the tribe of Judah, exactly one man only",
            "balanced full-body proportions with a normal-sized head and face, head clearly smaller than torso",
            "deep wine-red mantle over warm tan tunic with dark umber sash and small signet cord kept secondary",
            "serious responsible brotherly expression, not a generic dreamer and not a king",
        ],
        "laban": [
            "Laban the Aramean household head from Haran, father of Rachel and Leah, exactly one man only",
            "rich deep indigo outer robe over clay-brown tunic with dark teal sash and bronze clasp, not pale or faded",
            "wary calculating elder face with stronger color contrast, not Abraham and not Jacob",
            "small household staff and folded contract cloth kept secondary, no royal crown",
        ],
        "jacob": [
            "young adult tent-dwelling patriarch build, lean and quick-footed rather than elderly",
            "narrow angular face with wary intelligent eyes and a calculating brow",
            "dark hair and medium dark beard without gray in the base avatar",
            "striped muted-clay cloak and traveler staff, clearly different from Abraham's sand robe",
        ],
        "judah": [
            "balanced mature patriarch-son build with natural full-body proportions and sturdy shoulders",
            "normal-sized head and balanced face, head clearly smaller than torso, serious dark eyes, and short neat beard",
            "deep wine-red mantle over warm tan tunic with dark umber sash, small signet cord kept secondary",
            "full body visible with long torso and legs, not a close-up and not a childlike mascot",
        ],
        "laban": [
            "established Aramean household-head build with sturdy shoulders and strong adult proportions",
            "weathered face with wary calculating eyes, medium dark beard, and richer warm skin tone",
            "deep indigo outer robe over rich clay-brown tunic with dark teal sash and bronze clasp, never pale cream-only",
            "small household staff and folded contract cloth kept secondary, clearly distinct from Jacob and Abraham",
        ],
        "levi": [
            "Levi son of Jacob build with sturdy tribal-brother proportions and restrained intensity, not a priestly high priest yet",
            "natural warm peach-beige face with healthy skin color, dark attentive eyes, and a firm brow",
            "warm cream tunic under muted rust-brown mantle with deep teal sash, rich color blocks not faded",
            "small plain tribal staff held close, no jeweled breastplate, no ornate priestly turban",
        ],
        "issachar": [
            "Issachar son of Jacob build with solid grounded worker-scholar proportions and steady shoulders",
            "natural warm peach-beige face with healthy skin color, calm thoughtful eyes, and short dark beard",
            "warm wheat-brown robe with cream underlayer and muted teal sash, clear rich color not washed out",
            "small folded grain bundle and simple burden strap as signs of strength and labor, not a Joseph-like dreamer",
        ],
        "rachel": [
            "strikingly beautiful young shepherdess build with graceful slender shoulders",
            "soft luminous oval face with refined balanced features, large gentle dark eyes, delicate brows, and a warm radiant smile",
            "long dark glossy hair mostly under a graceful rose-cream layered veil, not gray and not severe",
            "deep rose mantle over warm cream robe with muted teal sash and tiny soft-gold clasp, modest and non-seductive, clearly distinct from Leah",
        ],
        "esau": [
            "rugged hunter build with broad shoulders and sunburnt presence",
            "red-brown hairy forearms, thick brows, and a rough impulsive expression",
            "rust-red hunter cloak, leather belt, and small bow or quiver kept secondary",
        ],
        "joseph": [
            "slender but resilient Hebrew-to-Egyptian governor build",
            "clear warm peach-beige young angular face with bright intelligent dark eyes, small crisp catchlights, alert wise focus, and restrained resilience, later framed by neat Egyptian grooming",
            "cream linen tunic with teal Egyptian collar and a small signet cord, not Pharaoh's crown",
            "short neat beard or clean-shaven Egyptian-influenced jaw depending on scene age",
        ],
        "pharaoh": [
            "ancient Egyptian royal build with rigid ceremonial posture",
            "smooth commanding face with kohl-lined eyes and a severe straight nose",
            "striped nemes headcloth, white linen robe, and gold-blue collar, never Hebrew clothing",
            "clean-shaven jaw or tiny ceremonial false-beard shape kept subtle",
        ],
        "moses": [
            "vigorous elder wilderness patriarch build, strong upright shoulders and steady full-body stance, not frail and not stooped",
            "strict front-facing natural warm peach-beige rectangular face with steady courageous eyes looking directly forward, lifted brow, and dignified calm authority",
            "deep ash-ochre desert mantle over plain robe, wooden staff as main silhouette",
            "mature dark hair and full dark beard with only subtle gray at the temples, not priestly breastplate and not royal",
            "quiet signs of Exodus leadership: desert-worn mantle, lawgiver dignity, and shepherding authority without a crown",
        ],
        "phinehas": [
            "Phinehas son of Eleazar build with young priestly zeal and compact upright strength",
            "natural warm face with intense covenant-protective eyes, strong brow, and short dark beard",
            "simple cream Levite-priest robe with muted blue sash and bronze clasp, not the ornate high-priest breastplate",
            "bronze spear held lowered and vertical beside the body plus small incense censer at the belt, no violent action scene",
        ],
        "aaron": [
            "mature Levite spokesman build, upright and steady, similar age world as Moses but clearly distinct",
            "kind strong face with dark brows, attentive eyes, and a neatly shaped full dark beard",
            "warm cream desert robe with muted blue sash and clay-brown mantle, no priestly breastplate",
            "simple headcloth and wooden staff, not a high-priest turban and not royal",
        ],
        "miriam": [
            "elderly prophetess build with firm shoulders and a musical worship presence",
            "lined feminine face with alert eyes and silver hair under a muted blue veil",
            "small hand drum kept close to the body as her distinctive sign",
        ],
        "joshua": [
            "young-to-mature military aide and commander build with compact alert shoulders",
            "square determined face with steady eyes, short dark beard, and practical brow",
            "muted blue commander cloak with bronze belt and small sheathed short sword",
            "no crown, no priestly linen, not Moses' staff-centered silhouette",
        ],
        "gideon": [
            "hesitant farmer-judge build becoming steadier, not a polished king",
            "plain gray-green cloak over clay work tunic with a fleece fold at the belt",
            "small clay jar and torch motif kept secondary as his 300-men sign",
            "worried eyes that become obedient and resolved",
        ],
        "samuel": [
            "vigorous elderly prophet-priest build with strong upright shoulders and steady spiritual authority, not frail",
            "ancient Hebrew Israelite elder with natural warm peach-beige skin tone, full white hair, white beard, thick white brows, listening eyes, and a firm compassionate mouth",
            "cream linen ephod under a deep blue-gray prophet mantle, completely unlike Saul's royal clothing",
            "small oil horn and blank scroll held close, no crown and no weapon",
        ],
        "saul": [
            "very tall first-king build with strong shoulders and restrained humble royal bearing, chosen from among the people",
            "long serious face with earnest modest eyes, dark brows, and a slight troubled shadow, not wicked in the base avatar",
            "deep indigo royal mantle over warm cream tunic, muted bronze crown band, and long spear lowered upright as a royal sign, not an attack pose",
            "short dark beard with sharp edges, clearly not David or Samuel, noble but still humble before later decline",
        ],
        "david": [
            "central hero shepherd-king build with graceful athletic shoulders and royal dignity",
            "handsome youthful-to-mature oval face with bright intelligent faithful eyes, alert spark, courageous smile, and reddish-brown hair tones",
            "deep royal-blue cloak over cream tunic with muted sky-blue sash and restrained soft-gold trim",
            "small lyre held to one side, sling pouch visible at the belt, short neat beard in adult king scenes",
        ],
        "jonathan": [
            "young royal warrior-prince build with loyal open posture",
            "handsome angular face with earnest eyes, calmer and softer than Saul",
            "muted blue prince cloak with bronze clasp and bow signal accessory",
            "short neat beard, no heavy crown and no spear-centered silhouette",
        ],
        "solomon": [
            "young wise king build with composed palace posture",
            "smooth thoughtful face with bright intelligent discerning eyes, calm alert focus, and restrained confidence",
            "clear sky-blue royal mantle over ivory robe with refined gold sash, not Saul's dark mantle and not David's deeper blue cloak",
            "small blank wisdom scroll or signet ring, no battlefield weapon",
        ],
        "elijah": [
            "rugged wilderness prophet build with sharp wind-worn shoulders, strong but approachable",
            "weathered human face with normal warm dark eyes, visible pupils, calm stern brow, and no glowing or white eyes",
            "rough dark-brown mantle with leather belt and warm tan robe, prophetic seriousness without horror",
            "full rugged beard and wind-worn brown hair, no court robe and no priestly linen",
        ],
        "korah": [
            "Korah the rebellious Levite leader build with proud squared shoulders and tense challenging posture",
            "ordinary Levite face with narrowed argumentative eyes, lifted chin, and self-important expression, not gentle and not heroic",
            "deep teal Levite robe with desert tan underlayer and clay-red sash, clearly distinct from Aaron's cream spokesman robe",
            "bronze censer held forward as his unmistakable sign, no priestly breastplate, no royal crown, no earthquake scene in the avatar",
        ],
        "noah": [
            "Noah the ark-builder patriarch build with sturdy working shoulders and calm obedient confidence",
            "weathered but warm face with focused builder's eyes, gray-brown hair and beard, not frail",
            "weathered wood-brown work mantle over olive robe with blue work-cuff accent and leather tool belt",
            "small wooden ark or boat model in one hand and simple wooden carpentry tool in the other hand, no fishing net",
        ],
        "elisha": [
            "gentler successor-prophet build with broad compassionate shoulders",
            "rounder face with watchful merciful eyes and a serious healer's calm",
            "gray-blue prophet mantle over pale robe, clearly smoother than Elijah's rough hair mantle",
            "receding hair or bald crown with short beard, matching the biblical mockery episode carefully",
        ],
        "daniel": [
            "exile court-sage build that can age from youth to elderly scenes",
            "long calm face with bright intelligent eyes, disciplined focus, and quiet courage",
            "deep emerald-green Babylonian-Persian court robe with olive mantle, parchment sash, and blank scroll",
            "neat beard in adult scenes and white beard in late-life scenes when requested",
        ],
        "ezekiel": [
            "exile priest-prophet build with squared shoulders and solemn visionary command, not a generic robed elder",
            "narrow angular face with intense watchful eyes, furrowed brow, grief-lined cheeks, and a small spark of hope",
            "deep indigo-gray exile mantle over parchment linen robe, ash-blue shoulder bands, small priestly cord, and dusty travel hem",
            "short dark beard with gray streaks, wind-worn dark hair, distinct from Ezra's calm scribe-priest look and Isaiah's court-prophet look",
            "small blank clay tablet or sealed blank vision scroll held close as his symbolic-action accessory",
        ],
        "ezra": [
            "scribe-priest build with careful teacher posture",
            "slim elderly face with focused reading eyes and neatly trimmed gray beard",
            "parchment cream priest-scribe robe with brown writing satchel and blank Torah scroll",
            "not a wall builder and not a Persian courtier",
        ],
        "nehemiah": [
            "Persian cupbearer turned wall-rebuilder build with civic resolve",
            "practical face with tired determined eyes and a short dark beard",
            "stone-gray Persian tunic under sage work cloak with builder belt, sleeves ready for rebuilding work",
            "small stone block, wooden trowel, measuring cord, and blank rebuilding plan scroll kept visible; cup motif is tiny and secondary",
            "clearly Jerusalem wall-and-city rebuilding leader, not a shepherd, not a priest, and not a generic traveler",
        ],
        "rahab": [
            "young adult Jericho woman build with front-facing graceful posture and courageous calm",
            "warm youthful face looking directly forward, dark attentive eyes, smooth skin, and modest hopeful expression",
            "deep teal dress with sand headscarf and clay-brown wrap, simple city-house clothing and not royal",
            "scarlet cord held visibly but modestly near the chest as the unmistakable Jericho sign, no weapon and no walking pose",
        ],
        "esther": [
            "Persian queen build with graceful but brave posture",
            "soft elegant face with tense courageous eyes, not a generic court lady",
            "turquoise and crimson Persian royal dress with delicate gold veil and small crown band",
            "hands held near the heart as if choosing courage",
        ],
        "mordecai": [
            "older Jewish court guardian build with protective shoulders",
            "wise square face with gray beard and watchful eyes",
            "blue-gray Persian gate official robe with modest Jewish sash",
            "small sealed court token, no crown and no priestly clothing",
        ],
        "haman": [
            "Persian high official build with rigid pride and a sharp courtly silhouette",
            "long narrow face with suspicious narrowed eyes, sharp nose, thin curled mustache, and a cold cruel smirk",
            "dark violet court robe under charcoal-black mantle with cold gold trim and a small blood-red sash accent",
            "sealed decree scroll and signet ring kept prominent, showing dangerous authority but no crown",
        ],
    }
)
CHARACTER_MOOD_OVERRIDES.update(
    {
        "abraham": [
            "strict front-facing protagonist covenant-patriarch posture, eyes looking directly at viewer, tall staff planted firmly, chest lifted, one hand open in faithful blessing",
        ],
        "sarah": [
            "mature covenant-matriarch posture with a restrained hopeful smile and hands gathered near the chest",
        ],
        "isaac": [
            "calm adult son posture, one hand near a small bundled-firewood strap, obedient but thoughtful",
        ],
        "jacob": [
            "alert traveler posture with staff held close and cautious eyes turned forward",
        ],
        "judah": [
            "front-facing full-body posture with normal head-to-body ratio, one hand near a small signet cord, serious responsible expression",
        ],
        "laban": [
            "front-facing sturdy household-head posture, deep robe colors visible, one hand on a small staff and wary calculating eyes",
        ],
        "haman": [
            "front-facing arrogant villain posture, chin lifted, one hand clutching a sealed decree scroll and the other showing a signet ring, narrowed eyes looking down with contempt",
        ],
        "esau": [
            "hungry impatient hunter posture with rugged shoulders and one hand near a bow strap",
        ],
        "joseph": [
            "composed survivor-governor posture, bright intelligent eyes forward with a small catchlight, clear warm face, one hand near a small signet cord and the other holding a blank plan scroll",
        ],
        "pharaoh": [
            "rigid front-facing Egyptian ruler posture with one hand lowered in command and unsmiling eyes",
        ],
        "moses": [
            "strict front-facing wilderness patriarch posture, eyes looking directly at viewer, wooden staff planted firmly like a leader guiding the camp, shoulders lifted, dignified faithful expression",
        ],
        "aaron": [
            "front-facing spokesman posture with one hand open as if speaking for Moses and the other near a simple staff",
        ],
        "miriam": [
            "elderly worship-leader posture holding a small hand drum close, watchful and strong",
        ],
        "joshua": [
            "front-facing successor-commander posture with squared shoulders and one hand near a sheathed sword",
        ],
        "gideon": [
            "cautious farmer-judge posture, clay jar and torch motif held low, courage still forming",
        ],
        "samuel": [
            "front-facing vigorous elderly Hebrew prophet-priest posture, white hair and beard visible, oil horn held near the chest, stern listening expression with quiet holy authority",
        ],
        "eli": [
            "front-facing elderly Shiloh priest posture, white linen robe and ephod clearly visible, small tabernacle lamp or incense censer held low, gentle watchful priestly expression",
        ],
        "rachel": [
            "front-facing graceful beloved shepherdess posture with one hand near a small water jar, warm radiant smile and modest confidence",
        ],
        "saul": [
            "front-facing tall first-king posture with long spear lowered upright, shoulders controlled, humble but troubled expression",
        ],
        "david": [
            "front-facing protagonist shepherd-king posture, chest lifted, bright intelligent faithful eyes, small lyre and sling pouch visible, warm courageous royal confidence",
        ],
        "jonathan": [
            "loyal prince posture with bow held low and open-hearted expression",
        ],
        "solomon": [
            "calm seated-or-standing wisdom posture, blank scroll held near the chest, bright intelligent discerning eyes",
        ],
        "elijah": [
            "rugged prophet posture with rough mantle gathered calmly to one side, firm but non-scary expression, normal warm dark eyes looking forward",
        ],
        "korah": [
            "front-facing rebellious Levite posture, bronze censer held forward, chin lifted, argumentative eyes challenging Moses' authority without any earthquake or death scene",
        ],
        "noah": [
            "front-facing ark-builder posture, small wooden ark or boat model held close and a simple carpentry tool visible, calm obedient builder expression",
        ],
        "elisha": [
            "compassionate prophet posture with gray-blue mantle gathered in one hand, merciful but firm",
        ],
        "daniel": [
            "court-sage posture with hands folded over a blank scroll, calm under pressure",
        ],
        "ezekiel": [
            "front-facing visionary exile-priest posture, one hand raised as if prophesying to dry bones, the other holding a small blank clay tablet or sealed blank vision scroll, intense grief-and-hope eyes looking forward",
        ],
        "ezra": [
            "scribe-priest posture reading from a blank scroll, focused and reverent",
        ],
        "nehemiah": [
            "front-facing rebuilder posture with trowel, measuring cord, small stone block, and blank rebuilding plan held close, determined civic courage",
        ],
        "rahab": [
            "strict front-facing young Jericho woman posture, scarlet cord held near the chest, courageous hopeful eyes looking directly forward, full body visible",
        ],
        "esther": [
            "brave queen posture with one hand near the heart and the other slightly extended toward mercy",
        ],
        "mordecai": [
            "protective elder posture with sealed court token held low and watchful eyes",
        ],
    }
)
CODE_PALETTE_OVERRIDES.update(
    {
        "aaron": "warm desert cream + muted blue + clay brown + dark umber accents, low saturation",
        "daniel": "deep emerald green + olive green + parchment cream + muted gold accents, low saturation",
        "abraham": "natural warm peach-beige skin + deep warm brown garment + muted clay red + warm cream accents, low saturation",
        "david": "deep royal blue + muted sky blue + cream + soft gold accents, low saturation",
        "eli": "priestly linen white + warm cream + muted blue-gold sash + soft gray accents, low saturation",
        "elijah": "rough dark brown + warm tan + muted ember gold accents, low saturation",
        "elisha": "gray blue + pale cream + muted olive accents, low saturation",
        "esau": "rust red + leather brown + desert tan accents, low saturation",
        "esther": "Persian turquoise + deep crimson + refined gold accents, low saturation",
        "ezekiel": "muted indigo gray + parchment cream + ash blue accents, low saturation",
        "ezra": "parchment cream + warm brown + priestly blue accents, low saturation",
        "gideon": "gray green + clay brown + torch amber accents, low saturation",
        "jacob": "striped muted clay + dusty blue + warm tan accents, low saturation",
        "jonathan": "loyal muted blue + bronze + warm cream accents, low saturation",
        "joseph": "natural warm peach-beige skin + Egyptian cream linen + teal collar + soft gold accents, low saturation",
        "joshua": "commander blue + desert tan + muted bronze accents, low saturation",
        "korah": "deep teal + desert tan + clay red sash + bronze censer accents, low saturation",
        "miriam": "aged blue + warm cream + muted copper drum accents, low saturation",
        "mordecai": "blue gray + Persian cream + muted bronze accents, low saturation",
        "moses": "natural warm peach-beige skin + deep ash ochre garment + desert tan + dark umber accents, low saturation",
        "nehemiah": "stone gray + sage green + warm limestone + muted bronze tool accents, low saturation",
        "noah": "weathered wood brown + olive work robe + warm cream + muted sky blue tool accents, low saturation",
        "pharaoh": "Egyptian white linen + lapis blue + gold accents, low saturation",
        "rachel": "deep rose + warm cream + muted teal + soft gold accents, low saturation",
        "rahab": "deep teal + sand headscarf + clay brown wrap + scarlet cord accent, low saturation",
        "samuel": "natural warm peach-beige skin + white hair + cream linen + deep blue gray + oil-horn amber accents, low saturation",
        "saul": "dark indigo + black violet + muted bronze accents, low saturation",
        "sarah": "soft rose-brown + warm cream + muted blue accents, low saturation",
        "solomon": "clear sky blue + pale ivory + refined gold + soft teal accents, low saturation",
    }
)
CODE_SIGNATURE_HINTS.update(
    {
        "aaron": [
            "Aaron the mature Levite brother and spokesman of Moses, exactly one man only",
            "warm cream desert robe with muted blue sash, clay-brown mantle, simple headcloth, and wooden staff",
            "dark hair and full dark beard with no gray, clearly not the later high-priest outfit",
            "gentle but confident spokesman face, no crown, no priestly breastplate, no ornate turban",
        ],
        "daniel": [
            "Daniel the faithful Jewish exile and court-wise prophet, exactly one man only",
            "deep emerald-green Babylonian-Persian court robe with olive mantle, parchment sash, and blank scroll",
            "bright intelligent eyes, disciplined courage, and calm dignified bearing",
            "no blue royal robe, no crown, no weapon, clearly not a warrior or king",
        ],
        "david": [
            "David the central shepherd-king of Israel, exactly one man only",
            "deep royal-blue cloak over cream tunic with muted sky-blue sash and restrained soft-gold trim",
            "small lyre held to one side and sling pouch at the belt as unmistakable David signs",
            "handsome courageous faithful expression with bright intelligent eyes and protagonist-level royal dignity, clearly distinct from Saul and Solomon",
        ],
        "elijah": [
            "Elijah the rugged wilderness prophet, exactly one man only",
            "rough dark-brown hair mantle and leather belt as the main silhouette",
            "normal warm dark eyes with visible pupils, firm non-scary expression, and wind-worn hair",
            "strong prophetic seriousness but approachable human face, not Elisha, not Samuel, not a royal court prophet",
        ],
        "korah": [
            "Korah the rebellious Levite leader who challenged Moses and Aaron, exactly one man only",
            "deep teal Levite robe with desert tan underlayer, clay-red sash, and bronze censer held forward",
            "proud argumentative expression with narrowed eyes and lifted chin, not humble and not heroic",
            "avatar shows his identity before judgment, no earthquake, no falling body, no death scene, no crowd",
        ],
        "noah": [
            "Noah the ark-builder patriarch before the flood, exactly one man only",
            "weathered wood-brown work mantle over olive robe, leather tool belt, and simple ancient carpentry tools",
            "small wooden ark or boat model held visibly in one hand, simple wooden mallet or adze held in the other hand",
            "calm obedient builder expression, not a fisherman, no fishing net, no modern tools",
        ],
        "elisha": [
            "Elisha the successor prophet, exactly one man only",
            "gray-blue prophet mantle with compassionate healer presence",
            "receding hair or bald crown, short beard, gentler than Elijah",
            "not Elijah's rough hair mantle and not a priestly robe",
        ],
        "joshua": [
            "Joshua the young-to-mature military aide and successor commander after Moses, exactly one man only",
            "muted blue commander cloak with bronze belt and small sheathed short sword",
            "alert faithful military leader with short dark beard, no crown and no priestly garments",
            "distinct from Moses' staff silhouette and never gray-haired in the base avatar",
        ],
        "jacob": [
            "Jacob the young tent-dwelling patriarch and traveler, exactly one man only",
            "striped muted-clay cloak, dusty blue sash, travel staff, and cautious intelligent eyes",
            "dark hair and medium dark beard, not elderly unless a story scene explicitly requests it",
            "no crown, no royal sash, clearly distinct from Abraham and Esau",
        ],
        "moses": [
            "Moses the vigorous elder wilderness patriarch, Exodus liberator, Sinai lawgiver, and shepherd-leader of Israel, exactly one man only",
            "natural warm peach-beige skin on face and hands, deep ash-ochre desert mantle, wooden staff planted firmly, mature dark hair with only subtle gray at the temples, and full dark beard",
            "strict front-facing dignified faithful expression, eyes looking directly forward with calm courage, a leader who spoke with God and guided Israel through the wilderness",
            "no stone tablets in the base avatar; keep the wooden staff as the only main prop, not Aaron's priestly linen and not a king",
        ],
        "nehemiah": [
            "Nehemiah the Jerusalem wall-rebuilding leader, exactly one man only",
            "stone-gray Persian tunic under sage work cloak with builder belt and sleeves ready for work",
            "small stone block, wooden trowel, measuring cord, and blank rebuilding plan scroll must be visible together",
            "determined civic courage, cup motif only tiny and secondary, not a shepherd, not a priest, not a generic traveler",
        ],
        "rachel": [
            "Rachel the beautiful beloved shepherdess and wife of Jacob, exactly one woman only",
            "deep rose mantle over warm cream robe with muted teal sash, tiny soft-gold clasp, and graceful veil",
            "large gentle dark eyes, refined balanced features, glossy dark hair, and warm radiant smile",
            "modest non-seductive beauty, clearly distinct from Leah and Sarah",
        ],
        "rahab": [
            "Rahab the young courageous woman of Jericho, exactly one woman only",
            "strict front-facing youthful face, dark attentive eyes looking directly forward, smooth warm skin, and modest hopeful expression",
            "deep teal city dress with sand headscarf and clay-brown wrap, scarlet cord held clearly near the chest",
            "not old, not walking, not side view, not seductive, not a queen, and not a soldier",
        ],
        "samuel": [
            "Samuel the elderly prophet-priest who hears God, anoints Saul and David, and continues speaking with authority, exactly one man only",
            "ancient Hebrew Israelite elder with natural warm peach-beige skin tone, full white hair, white beard, cream linen ephod under deep blue-gray prophet mantle, and small oil horn",
            "strong upright old prophet presence, stern listening eyes, calm holy authority, no crown and no weapon",
            "visually distinct from Saul's dark royal mantle and David's deep blue shepherd-king cloak",
        ],
        "saul": [
            "Saul the first king of Israel, exactly one man only",
            "very tall body, dark indigo royal mantle, bronze crown band, and long spear",
            "earnest humble early-king expression with a slight troubled shadow, not David and not Samuel",
            "royal but conflicted presence, not an evil caricature, no shepherd harp or priestly oil horn",
        ],
        "solomon": [
            "Solomon the young wise king of Israel, exactly one man only",
            "clear sky-blue royal mantle over pale ivory robe, refined gold sash, and blank wisdom scroll",
            "composed discerning expression with bright intelligent eyes, not Saul's dark spear-bearing silhouette and not David's deeper blue cloak",
        ],
    }
)

# 사용자 생성 결과를 보며 다시 조정한 구약 인물들. 같은 직분끼리 닮아 보이는
# 문제를 줄이기 위해 소품, 체형, 얼굴 인상, 옷 색을 더 직접적으로 고정한다.
CHARACTER_VISUAL_OVERRIDES.update(
    {
        "ahab": [
            "middle-aged wicked northern Israel king build with hard squared royal shoulders and dangerous pride",
            "hard angular face with narrowed malicious eyes, stubborn brow, and a cold idolatrous smirk",
            "dark hair under an ornate northern royal headband, short sharply faceted dark beard",
            "dark royal purple robe with navy mantle and muted gold trim, one hand gripping a clearly visible small dark Baal idol held high near the chest",
        ],
        "ahijah": [
            "elderly Shiloh prophet build with lean upright shoulders, wise and solemn but not frightening",
            "ancient Hebrew face with soft pale cataract-like blind eyes, almost no dark pupils, unfocused gaze past the viewer, and no visible injury",
            "gray hair under a simple warm-brown prophet headcloth, short gray beard with angular facets",
            "plain warm-brown prophet mantle over cream robe, torn cloak pieces held clearly as the divided-kingdom sign",
        ],
        "asher": [
            "Asher son of Jacob build with sturdy peaceful tribal-son proportions, not a Joseph-like dreamer",
            "natural warm peach-beige face with healthy skin color, gentle alert eyes, and a short neat beard",
            "warm olive and cream robe with rich honey-tan sash, never faded or gray",
            "small olive branch, round bread loaf, and grain sheaf kept close as signs of rich food and blessing",
        ],
        "levi": [
            "Levi son of Jacob build with sturdy tribal-brother proportions and restrained intensity, not a priestly high priest yet",
            "natural warm peach-beige face with healthy skin color, dark attentive eyes, and a firm brow",
            "warm cream tunic under muted rust-brown mantle with deep teal sash, rich color blocks not faded",
            "small plain tribal staff held close, no jeweled breastplate, no ornate priestly turban",
        ],
        "issachar": [
            "Issachar son of Jacob build with solid grounded worker-scholar proportions and steady shoulders",
            "natural warm peach-beige face with healthy skin color, calm thoughtful eyes, and short dark beard",
            "warm wheat-brown robe with cream underlayer and muted teal sash, clear rich color not washed out",
            "small folded grain bundle and simple burden strap as signs of strength and labor, not a Joseph-like dreamer",
        ],
        "zebulun": [
            "Zebulun son of Jacob build with sturdy coastal-tribe merchant-sailor proportions, not a fisherman apostle",
            "natural warm peach-beige face with alert practical eyes, broad brow, and short angular beard",
            "deep sea-blue outer mantle over warm cream tunic with muted bronze clasp and rope-brown sash, rich color blocks not faded",
            "small ancient ship-prow token and coiled harbor rope held close as signs of dwelling by the sea and ships",
        ],
        "phinehas": [
            "Phinehas son of Eleazar build with young priestly zeal and compact upright strength",
            "natural warm face with intense covenant-protective eyes, strong brow, and short dark beard",
            "simple cream Levite-priest robe with muted blue sash and bronze clasp, not the ornate high-priest breastplate",
            "bronze spear held lowered and vertical beside the body plus small incense censer at the belt, no violent action scene",
        ],
        "caleb": [
            "Caleb son of Jephunneh build with rugged broad-shouldered faithful commander proportions, stockier and tougher than a slim court noble",
            "weathered warm face with clear unwavering eyes, strong brow, square jaw, and sun-worn veteran confidence",
            "short dark hair under a simple scout headband, thick practical beard with angular facets",
            "muted teal commander cloak over desert-tan travel robe, bronze belt, small spy staff and grape-cluster token kept secondary",
        ],
        "korah": [
            "Korah the rebellious Levite leader build with proud squared shoulders and tense challenging posture",
            "ordinary Levite face with narrowed argumentative eyes, lifted chin, and self-important expression, not gentle and not heroic",
            "deep teal Levite robe with desert tan underlayer and clay-red sash, clearly distinct from Aaron's cream spokesman robe",
            "bronze censer thrust forward as his unmistakable sign, one free hand partly clenched as if challenging Moses and Aaron, no earthquake scene in the avatar",
        ],
        "saul": [
            "very tall first-king build with strong shoulders and restrained humble royal bearing, chosen from among the people",
            "long serious face with earnest modest eyes, dark brows, and a slight troubled shadow, not wicked in the base avatar",
            "dark indigo and black-violet luxury royal mantle over warm cream tunic, layered gold-bronze trim, muted bronze crown band, and long spear lowered upright as a royal sign, not an attack pose",
            "short dark beard with sharp edges, clearly not David or Samuel, noble but still humble before later decline",
        ],
    }
)
CHARACTER_MOOD_OVERRIDES.update(
    {
        "ahab": [
            "front-facing wicked king posture, Baal idol held clearly near the chest, narrowed malicious eyes, proud but dangerous stance",
        ],
        "ahijah": [
            "front-facing blind Shiloh prophet posture, unfocused eyes not making eye contact, head slightly lifted as if listening, torn cloak pieces held in both hands with solemn authority",
        ],
        "asher": [
            "front-facing tribal-son posture with olive branch, bread loaf, and grain sheaf held close, peaceful blessed expression",
        ],
        "levi": [
            "front-facing tribal-brother posture with plain staff held low, steady intense expression and warm healthy face",
        ],
        "issachar": [
            "front-facing grounded worker-scholar posture with grain bundle and burden strap, calm thoughtful expression",
        ],
        "zebulun": [
            "front-facing coastal-tribe posture with small ship-prow token and coiled harbor rope visible, alert practical expression",
        ],
        "phinehas": [
            "strict front-facing zealous priest posture, spear lowered vertical, small censer visible, intense protective expression without violence",
        ],
        "caleb": [
            "front-facing rugged faithful commander posture, chest square, weathered confident eyes, one hand near a spy staff or grape-cluster token",
        ],
        "korah": [
            "strict front-facing rebellious Levite posture, bronze censer held forward, chin lifted, argumentative eyes challenging Moses' authority",
        ],
        "saul": [
            "front-facing tall first-king posture with long spear lowered upright, dark luxury royal cloak displayed, shoulders controlled, humble chosen-king expression with only a slight troubled shadow",
        ],
    }
)
CODE_PALETTE_OVERRIDES.update(
    {
        "ahab": "dark royal purple + navy mantle + muted gold trim + black idol accent, low saturation",
        "ahijah": "warm brown prophet mantle + cream robe + torn-cloak tan accents, low saturation",
        "asher": "natural warm peach-beige skin + warm olive + cream + honey tan + grain gold accents, low saturation",
        "levi": "natural warm peach-beige skin + muted rust brown + warm cream + deep teal accents, low saturation",
        "issachar": "natural warm peach-beige skin + wheat brown + cream + muted teal accents, low saturation",
        "zebulun": "natural warm peach-beige skin + deep sea blue + warm cream + rope brown + muted bronze accents, low saturation",
        "phinehas": "priestly cream + muted blue + bronze spear and censer + clay accent, low saturation",
        "caleb": "rugged desert tan + muted teal commander cloak + warm clay brown + bronze accents, low saturation",
        "korah": "deep teal + desert tan + clay red sash + bronze censer accents, low saturation",
        "saul": "dark indigo + black violet luxury royal mantle + warm cream tunic + muted gold bronze trim, low saturation",
    }
)
CODE_SIGNATURE_HINTS.update(
    {
        "ahab": [
            "Ahab the wicked northern Israel king associated with Baal worship, exactly one man only",
            "dark royal purple robe with navy mantle and muted gold trim, clearly not David, Saul, or Solomon",
            "small dark Baal idol held clearly near the chest as the main identity sign",
            "narrow malicious eyes and cold idolatrous smirk, proud dangerous king presence, no prophet robe",
        ],
        "ahijah": [
            "Ahijah the Shilonite prophet who signaled the divided kingdom, exactly one man only",
            "soft pale cataract-like blind eyes with almost no dark pupils, unfocused gaze past the viewer, wise solemn listening expression, not frightening and no visible injury",
            "warm-brown prophet mantle over cream robe, torn cloak pieces held in both hands as the main sign",
            "elderly Hebrew prophet, no crown, no royal robe, no horror eyes",
        ],
        "asher": [
            "Asher son of Jacob, exactly one man only",
            "warm healthy peach-beige face, warm olive and cream robe with honey-tan sash",
            "olive branch, round bread loaf, and grain sheaf visible as signs of abundant food and blessing",
            "front-facing peaceful sturdy tribal-son presence, not Joseph and not an Egyptian official",
        ],
        "levi": [
            "Levi son of Jacob, exactly one man only",
            "warm peach-beige face, rust-brown mantle, cream tunic, deep teal sash, plain tribal staff",
            "tribal brother before later priesthood, no ornate high-priest clothing and no jeweled breastplate",
            "front-facing sturdy intense presence, clearly distinct from Aaron and Moses",
        ],
        "issachar": [
            "Issachar son of Jacob, exactly one man only",
            "warm peach-beige face, wheat-brown robe, cream underlayer, muted teal sash",
            "grain bundle and burden strap visible as signs of steady labor and strength",
            "front-facing grounded thoughtful presence, not Joseph and not an Egyptian official",
        ],
        "zebulun": [
            "Zebulun son of Jacob, coastal tribe associated with the seashore and ships, exactly one man only",
            "deep sea-blue outer mantle over warm cream tunic, rope-brown sash, and muted bronze clasp",
            "small ancient ship-prow token and coiled harbor rope visible as the main identity signs",
            "front-facing sturdy practical coastal-tribe presence, not a fisherman apostle, not Joseph, and not a modern sailor",
        ],
        "phinehas": [
            "Phinehas son of Eleazar the zealous priest, exactly one man only",
            "simple cream Levite-priest robe with muted blue sash, bronze spear lowered vertically, and small censer at the belt",
            "intense covenant-protective eyes, not an ornate high priest and not a battle warrior",
            "avatar shows identity without violence: no stabbing, no blood, no crowd",
        ],
        "caleb": [
            "Caleb son of Jephunneh, faithful spy and rugged commander, exactly one man only",
            "stocky broad-shouldered veteran build, weathered face, strong brow, clear unwavering eyes",
            "muted teal commander cloak over desert-tan travel robe, bronze belt, small spy staff and grape-cluster token",
            "faith-filled battle-tested confidence, not a handsome slim court noble and not Joshua",
        ],
        "eli": [
            "Eli the elderly priest of Shiloh who served at the tabernacle when Samuel was young, exactly one man only",
            "elderly Hebrew priest with gray-white hair, full white-gray beard, heavy brows, and watchful but gentle priestly eyes",
            "white linen priest robe with cream ephod, muted blue-gold sash, and simple priestly head wrap, clearly priestly and not ordinary tribal clothing",
            "small tabernacle lamp or incense censer held low as his unmistakable priest sign, no crown and no prophet mantle",
        ],
        "korah": [
            "Korah the rebellious Levite leader who challenged Moses and Aaron, exactly one man only",
            "deep teal Levite robe with desert tan underlayer, clay-red sash, and bronze censer held forward",
            "front-facing proud argumentative expression with narrowed eyes and lifted chin, not humble and not heroic",
            "avatar shows his identity before judgment, no earthquake, no falling body, no death scene, no crowd",
        ],
        "saul": [
            "Saul the first king of Israel, exactly one man only",
            "very tall body, dark indigo and black-violet luxury royal mantle over warm cream tunic, layered muted gold-bronze trim, bronze crown band, and long spear lowered upright",
            "earnest humble early-king expression with a slight troubled shadow, not David and not Samuel",
            "royal but conflicted presence, not an evil caricature in the base avatar, no shepherd harp or priestly oil horn",
        ],
    }
)
CHARACTER_VISUAL_OVERRIDES["hezekiah"] = [
    "middle-aged Judah king build with dignified but humbled shoulders",
    "rectangular face with prayerful worried eyes, softened brow, and a short full beard",
    "deep indigo royal mantle over ivory robe with a narrow gold Judah crown band",
    "small unsealed threat letter held near the chest, not a prophecy scroll and not a weapon",
]
CHARACTER_MOOD_OVERRIDES["hezekiah"] = [
    "front-facing prayerful king posture, threat letter held open near the heart, anxious but trusting expression",
]
CODE_PALETTE_OVERRIDES["hezekiah"] = (
    "deep indigo + ivory cream + restrained Judah gold accents, low saturation"
)
CODE_SIGNATURE_HINTS["hezekiah"] = [
    "Hezekiah the praying king of Judah, exactly one man only",
    "deep indigo royal mantle over ivory robe with restrained gold crown band",
    "small unsealed threat letter held near the chest as a sign of the Assyrian crisis",
    "humble anxious faith, not proud Saul, not youthful Solomon, and not a prophet",
]

NT_CHARACTER_VISUAL_OVERRIDES = {
    "jesus": [
        "calm Galilean teacher build with balanced upright shoulders",
        "kind oval face with steady compassionate eyes and a short dark beard",
        "shoulder-length dark wavy hair in soft faceted planes",
        "cream tunic under a deep muted red outer robe with a simple travel sash",
    ],
    "mary": [
        "modest young Judean mother build with gentle protective posture",
        "soft feminine oval face with quiet faithful eyes",
        "dark hair fully covered by a layered blue mantle and cream under-veil",
        "simple rose-brown dress beneath the blue mantle, no ornaments",
    ],
    "joseph_nazareth": [
        "sturdy carpenter father build with squared practical shoulders",
        "warm rectangular face with careful protective eyes and a trimmed beard",
        "short dark hair under a plain work headcloth",
        "ochre work tunic with a carpenter belt, small wooden mallet kept close to the body",
    ],
    "zechariah": [
        "elderly Jerusalem priest build with dignified narrow shoulders",
        "long weathered face with astonished priestly eyes and heavy gray brows",
        "gray hair under a cream priestly head wrap",
        "white linen priest robe with a muted gold sash and small incense censer held low",
    ],
    "elizabeth": [
        "elderly Judean woman build with gentle stooped shoulders",
        "kind weathered feminine face with joyful patient eyes and soft wrinkles",
        "gray-streaked hair hidden beneath a muted plum veil",
        "cream robe with muted plum shawl, hands held near the chest in grateful wonder",
    ],
    "gabriel": [
        "tall luminous messenger figure with graceful adult proportions",
        "smooth serene face with bright gentle eyes",
        "soft radiant hair framed by simple faceted light planes",
        "white and pale gold robe with restrained angular wing shapes, no weapon",
    ],
    "john_the_baptist": [
        "rugged wilderness prophet build with lean wiry shoulders",
        "weathered angular face with intense eyes, strong brow, and wild beard",
        "rough dark hair in untidy faceted chunks",
        "camel-hair cloak, leather belt, and reed staff as clear wilderness prophet signs",
    ],
    "herod": [
        "Herodian ruler build with polished but tense royal shoulders",
        "sharp suspicious face with narrowed eyes and a trimmed dark beard",
        "short dark hair under a small angular royal headband",
        "dark crimson robe with black-violet mantle and restrained gold trim",
    ],
    "andrew": [
        "slender fisherman-disciple build with quick attentive posture",
        "long narrow friendly face with searching eyes and short beard",
        "short blocky curls under a plain sea-worn headcloth",
        "sand-colored tunic with blue-green sash and a small hand net at the side",
    ],
    "peter": [
        "broad sturdy fisherman-apostle build with strong hands and squared stance",
        "rounder weathered face with bold earnest eyes and a thick short beard",
        "short dark curls in chunky faceted planes",
        "deep blue outer cloak over a tan work tunic, heavy fishing net over one shoulder",
    ],
    "philip": [
        "lean road-worn disciple build with guide-like alert posture",
        "angular thoughtful face with open curious eyes and a neat short beard",
        "medium dark hair under a light travel head wrap",
        "sage travel cloak with a small route scroll tube and simple sandals",
    ],
    "philip_evangelist": [
        "mature early-church evangelist build, lean from long roads but steadier than the apostle Philip",
        "kind decisive face with focused eyes and a short graying beard",
        "close dark hair with a simple travel head wrap, slightly weathered by desert roads",
        "plain deacon-evangelist robe with dusty travel cloak and a small blank Isaiah scroll tube, no fisherman gear",
    ],
    "james_zebedee": [
        "energetic fisherman brother build with compact strong shoulders",
        "square sun-browned face with intense loyal eyes and full blocky beard",
        "thick dark hair under a rope-tied headband",
        "rust-brown work tunic with an oar handle and coiled rope as fishing signs",
    ],
    "john": [
        "younger beloved-disciple build with gentle narrow shoulders",
        "smooth youthful adult face with reflective eyes and a small neat beard",
        "straight shoulder-length dark hair in clean polygon sheets",
        "soft green-blue cloak with a small blank scroll satchel, quieter than Peter and James",
    ],
    "matthew": [
        "former tax collector turned disciple build with neat composed posture",
        "oval observant face with careful eyes and a trimmed beard",
        "closely arranged dark hair beneath a tidy headcloth",
        "warm brown robe with a wax tablet, stylus, and small coin pouch kept secondary",
    ],
    "jairus": [
        "synagogue ruler build with formal steady bearing",
        "serious fatherly face with worried compassionate eyes and trimmed gray-streaked beard",
        "neatly wrapped headcloth framing the face",
        "dignified dark teal robe with a small blank synagogue scroll case",
    ],
    "lazarus": [
        "Bethany man restored to life build with slim recovering posture",
        "gentle pale face with amazed grateful eyes and short beard",
        "dark hair partly covered by a loose linen wrap",
        "olive robe with clean loose linen bands at the shoulders and wrists, not frightening",
    ],
    "martha": [
        "Bethany host woman build with practical capable shoulders",
        "warm oval feminine face with focused caring eyes",
        "dark hair covered by a clay-brown household veil",
        "earth-toned robe with a folded serving cloth and small bread basket held low",
    ],
    "judas": [
        "lean treasurer-disciple build with guarded inward posture",
        "narrow angular face with uneasy calculating eyes and a trimmed pointed beard",
        "dark hair under a muted olive hood-like head covering",
        "dark olive robe with a small coin pouch held close, no heroic stance",
    ],
    "pilate": [
        "Roman governor build with formal upright authority",
        "clean angular Roman face with weary skeptical eyes and short trimmed beard",
        "short cropped dark hair with no Hebrew headcloth",
        "ivory tunic, red-edged toga cloak, and small blank legal tablet held at the side",
    ],
    "mary_magdalene": [
        "devout female disciple build with graceful but grounded proportions",
        "soft oval face with hopeful resurrection-witness eyes",
        "long dark hair partly covered by a dawn-colored rose veil",
        "cream robe with soft rose shawl, hands clasped empty at the chest",
    ],
    "thomas": [
        "thoughtful disciple build with careful craftsman posture",
        "long rectangular face with questioning eyes and a neat dark beard",
        "medium wavy hair under a muted gray-blue head wrap",
        "gray-blue robe with a small measuring cord at the belt, reflective not fearful",
    ],
    "stephen": [
        "Hellenistic deacon build with humble service posture",
        "bright calm face with courageous eyes and short neat beard",
        "short dark curls with a simple cream headcloth",
        "plain linen tunic with a folded serving cloth and small bread basket held close",
    ],
    "paul": [
        "compact road-worn missionary build in a strict front-facing upright standing avatar pose",
        "front-facing sharp oval face looking directly at the viewer, both eyes equally visible, strong nose, and short dark beard",
        "receding dark hair in close faceted planes, symmetrical from the front",
        "dark teal travel cloak over a dusty tan tunic, scroll satchel centered across the chest, staff held vertical beside the body",
    ],
    "barnabas": [
        "broad warm encourager build with open steady shoulders",
        "rounded square face with generous eyes and a full neatly shaped beard",
        "medium dark curls under a soft olive head wrap",
        "olive-green travel cloak with a small folded gift purse and blank scroll tube",
    ],
    "cornelius": [
        "Roman centurion build with disciplined military posture",
        "square Roman face with respectful prayerful eyes and short trimmed beard",
        "closely cropped dark hair beneath a bronze centurion headband",
        "bronze armor over a deep red tunic, red cloak, and short baton held calmly",
    ],
    "john_mark": [
        "young adult assistant scribe build with light traveler proportions",
        "smooth youthful face with attentive eyes and only a very short beard",
        "short dark curls under a small travel headcloth",
        "warm ochre travel tunic with a shoulder satchel and small blank parchment roll",
    ],
    "james": [
        "Jerusalem church elder build with composed prayerful authority",
        "long wise face with steady discerning eyes and a gray-streaked beard",
        "dark gray-streaked hair under a plain cream prayer shawl",
        "simple linen robe with a folded elder's shawl and small blank council scroll",
    ],
    "silas": [
        "sturdy prophet-companion build with resilient travel posture",
        "square faithful face with strong hopeful eyes and trimmed beard",
        "short blocky curls beneath a dark indigo travel hood",
        "indigo cloak over a dusty robe, small hymn scroll tucked near the belt",
    ],
    "timothy": [
        "young adult disciple build with modest slender shoulders",
        "gentle youthful face with earnest eyes and a very short neat beard",
        "soft dark hair under a simple blue-gray head wrap",
        "blue-gray robe with a folded letter packet held close to the chest",
    ],
    "lydia": [
        "poised merchant woman build with graceful confident posture",
        "soft elegant face with warm intelligent eyes",
        "long dark hair partly covered by a refined purple shawl",
        "rich but modest purple-dyed robe with a folded bolt of purple cloth under one arm",
    ],
    "aquila": [
        "Jewish tentmaker craftsman build with practical work-ready shoulders",
        "warm angular face with focused eyes and a short workman's beard",
        "short dark hair under a plain leather-edged head wrap",
        "tan work tunic with a leather apron, awl, and folded tent cloth roll",
    ],
    "priscilla": [
        "Greco-Roman Jewish tentmaker and scripture-teaching woman build, matching the same compact full-body avatar proportions as the existing cast",
        "soft intelligent feminine face with attentive eyes, clearly stylized not realistic",
        "dark hair fully covered by a simple teal headscarf with flat low-poly facets",
        "modest teal outer robe over a warm brown work dress, small folded tent cloth and blank teaching scroll kept close to the body",
    ],
    "festus": [
        "Roman governor build with formal legal posture",
        "stern Roman face with wary administrative eyes and short trimmed beard",
        "short cropped hair with a narrow civic headband",
        "cream toga with muted red trim and a blank legal scroll held stiffly",
    ],
    "agrippa": [
        "client king build with polished courtly posture",
        "refined angular face with curious evaluating eyes and a neatly groomed beard",
        "dark hair beneath a small gold diadem, not a full crown",
        "purple-gold court robe with restrained royal trim and a small signet ring",
    ],
}

NT_CHARACTER_MOOD_OVERRIDES = {
    "jesus": [
        "serene compassionate teacher posture, one hand open in blessing and the other relaxed"
    ],
    "mary": ["quiet faithful posture with hands gently gathered, protective but calm"],
    "joseph_nazareth": [
        "protective carpenter-father posture, one hand near the tool belt and one hand open"
    ],
    "zechariah": [
        "astonished priestly posture, censer held low as if surprised in the temple"
    ],
    "elizabeth": ["grateful elder-mother posture with joyful patient expression"],
    "gabriel": [
        "gentle messenger posture, one hand extended in announcement and the other lowered"
    ],
    "john_the_baptist": [
        "urgent wilderness-prophet posture, reed staff upright and eyes intense"
    ],
    "herod": [
        "tense ruler posture with suspicious narrowed eyes, no kindness in the stance"
    ],
    "andrew": [
        "inviting disciple posture with small net lowered, ready to bring another person to Jesus"
    ],
    "peter": [
        "bold but teachable posture with net over one shoulder and one hand over the heart"
    ],
    "philip": ["road-guide disciple posture with route scroll held near the chest"],
    "philip_evangelist": [
        "early-church evangelist posture, one hand open toward the road and a blank scroll tube held close"
    ],
    "james_zebedee": ["energetic loyal disciple posture with coiled rope held close"],
    "john": ["quiet attentive disciple posture with scroll satchel held gently"],
    "matthew": [
        "humble converted-tax-collector posture, wax tablet lowered instead of used"
    ],
    "jairus": [
        "anxious father and synagogue leader posture, hands pleading but dignified"
    ],
    "lazarus": ["newly restored grateful posture, linen bands loose and hands open"],
    "martha": [
        "capable hospitable posture with serving cloth held low, attentive not distracted"
    ],
    "judas": [
        "guarded treasurer posture, coin pouch close to the body and eyes turned aside"
    ],
    "pilate": [
        "weary judging posture with legal tablet lowered, conflicted but authoritative"
    ],
    "mary_magdalene": [
        "reverent resurrection-witness posture with hopeful upward gaze"
    ],
    "thomas": ["thoughtful searching posture with one hand near the measuring cord"],
    "stephen": ["courageous servant posture with peaceful face lifted slightly"],
    "paul": [
        "strict front-facing missionary posture, torso square to the viewer, both feet planted, scroll satchel centered, eyes looking directly forward"
    ],
    "barnabas": ["encouraging open-handed posture, warm and steady rather than severe"],
    "cornelius": [
        "disciplined prayerful posture, military body held respectfully still"
    ],
    "john_mark": ["alert assistant posture with parchment roll held ready for travel"],
    "james": ["Jerusalem elder posture with hands calm over a folded council scroll"],
    "silas": [
        "resilient companion posture, hymn scroll near the chest and shoulders squared"
    ],
    "timothy": [
        "earnest young-worker posture, letter packet held close with humble confidence"
    ],
    "lydia": ["welcoming faithful host posture with purple cloth folded neatly"],
    "aquila": [
        "steady craftsman posture with awl and tent cloth held safely, not working mid-action"
    ],
    "priscilla": [
        "calm scripture-teacher posture in the exact same flat vector avatar style, scroll and tent cloth kept secondary"
    ],
    "festus": ["formal Roman legal posture with severe administrative expression"],
    "agrippa": ["curious royal hearing posture with one hand near a small signet ring"],
}

NT_CODE_PALETTE_OVERRIDES = {
    "jesus": "deep muted red + warm cream + desert tan accents, low saturation",
    "mary": "soft blue mantle + cream + muted rose-brown accents, low saturation",
    "joseph_nazareth": "ochre brown + warm cream + muted cedar accents, low saturation",
    "zechariah": "temple linen white + muted gold + warm gray accents, low saturation",
    "elizabeth": "muted plum + parchment cream + soft clay accents, low saturation",
    "gabriel": "warm white + pale gold + soft sky accents, low saturation",
    "john_the_baptist": "camel brown + leather umber + reed green accents, low saturation",
    "herod": "dark crimson + black-violet + muted gold accents, low saturation",
    "andrew": "sea green + sand tan + rope brown accents, low saturation",
    "peter": "deep blue + weathered tan + rope brown accents, low saturation",
    "philip": "sage green + light clay + parchment accents, low saturation",
    "philip_evangelist": "dusty olive + parchment cream + road tan accents, low saturation",
    "james_zebedee": "rust brown + deep sea blue + rope tan accents, low saturation",
    "john": "soft green-blue + parchment cream + muted olive accents, low saturation",
    "matthew": "warm brown + muted teal + wax tan accents, low saturation",
    "jairus": "dark teal + temple cream + muted bronze accents, low saturation",
    "lazarus": "olive green + clean linen white + pale clay accents, low saturation",
    "martha": "clay brown + warm cream + olive accents, low saturation",
    "judas": "dark olive + shadow brown + dull brass accents, low saturation",
    "pilate": "Roman ivory + muted crimson + stone gray accents, low saturation",
    "mary_magdalene": "soft rose + cream + dawn gold accents, low saturation",
    "thomas": "gray-blue + warm taupe + muted copper accents, low saturation",
    "stephen": "plain linen cream + warm ochre + pale blue accents, low saturation",
    "paul": "dark teal + dusty tan + parchment accents, low saturation",
    "barnabas": "olive green + warm tan + muted gold accents, low saturation",
    "cornelius": "bronze + deep red + iron gray accents, low saturation",
    "john_mark": "warm ochre + light blue-gray + parchment accents, low saturation",
    "james": "cream linen + deep olive + gray accents, low saturation",
    "silas": "indigo + dusty tan + parchment accents, low saturation",
    "timothy": "blue-gray + soft cream + muted green accents, low saturation",
    "lydia": "rich purple + cream + muted gold accents, low saturation",
    "aquila": "tan leather + muted teal + tent-cloth cream accents, low saturation",
    "priscilla": "teal + warm brown + parchment cream accents, low saturation",
    "festus": "Roman cream + muted red + stone gray accents, low saturation",
    "agrippa": "royal purple + muted gold + deep blue accents, low saturation",
}

NT_CODE_SIGNATURE_HINTS = {
    "jesus": [
        "Jesus of Nazareth, exactly one adult male figure only",
        "Galilean teacher and healer, not a king on a throne and not a Roman official",
        "deep muted red outer robe over a cream tunic, simple sandals, no halo and no written symbol",
        "gentle compassionate expression that can anchor gospel story scenes",
    ],
    "mary": [
        "Mary the mother of Jesus, exactly one adult woman only",
        "Nazareth mother presence, modest blue mantle and cream veil, no royal jewelry",
        "gentle faithful expression, protective but quiet",
    ],
    "joseph_nazareth": [
        "Joseph of Nazareth, carpenter and earthly father figure of Jesus, exactly one man only",
        "ochre work tunic, carpenter belt, small wooden mallet, protective steady presence",
        "distinct from Joseph son of Jacob by older fatherly carpenter look",
    ],
    "zechariah": [
        "Zechariah the temple priest and father of John the Baptist, exactly one elderly man only",
        "white linen priest robe, muted gold sash, small incense censer, astonished temple-priest expression",
        "distinct from Zechariah the prophet by priestly clothing and elderly father role",
    ],
    "elizabeth": [
        "Elizabeth the elderly mother of John the Baptist, exactly one elderly woman only",
        "muted plum veil, cream robe, grateful expectant expression, clearly older than Mary",
    ],
    "gabriel": [
        "Gabriel the heavenly messenger, exactly one angelic figure only",
        "simple white and pale gold faceted robe, restrained wing shapes, no weapon, no human crowd",
    ],
    "john_the_baptist": [
        "John the Baptist, wilderness prophet who prepares the way, exactly one man only",
        "camel-hair cloak, leather belt, reed staff, rugged hair and beard",
        "wilderness-prophet look, not John the apostle and not a temple priest",
    ],
    "herod": [
        "Herod the anxious Judean ruler, exactly one man only",
        "dark crimson royal robe, small angular headband, suspicious eyes, not a Roman governor",
    ],
    "andrew": [
        "Andrew the fisherman disciple, exactly one man only",
        "slender sea-worn fisherman with small hand net, inviting rather than commanding",
        "distinct from Peter by lighter build and smaller net",
    ],
    "peter": [
        "Peter the fisherman apostle, exactly one man only",
        "broad sturdy build, heavy fishing net over shoulder, bold earnest eyes",
        "distinct from Andrew, James, and John by larger build and deep blue cloak",
    ],
    "philip": [
        "Philip the disciple, exactly one man only",
        "road-worn guide-like disciple with route scroll tube and sage travel cloak",
        "curious helper presence, not a fisherman net carrier",
    ],
    "philip_evangelist": [
        "Philip the evangelist from Acts, one of the seven servants, exactly one man only",
        "mature early-church messenger with dusty travel cloak and blank Isaiah scroll tube",
        "distinct from Philip the apostle; no fisherman gear, no youthful disciple styling",
    ],
    "james_zebedee": [
        "James son of Zebedee, fisherman apostle and brother of John, exactly one man only",
        "coiled rope and oar handle, rust-brown work tunic, energetic loyal presence",
        "distinct from James the Jerusalem elder",
    ],
    "john": [
        "John the apostle, younger beloved disciple, exactly one man only",
        "soft green-blue cloak, scroll satchel, reflective gentle expression",
        "distinct from John the Baptist by clean disciple robe and no camel-hair cloak",
    ],
    "matthew": [
        "Matthew the former tax collector disciple, exactly one man only",
        "wax tablet, stylus, small coin pouch lowered after leaving the tax booth",
        "humble converted presence, not a merchant and not a Roman official",
    ],
    "jairus": [
        "Jairus the synagogue ruler and desperate father, exactly one man only",
        "formal synagogue robe, small blank scroll case, anxious fatherly expression",
    ],
    "lazarus": [
        "Lazarus of Bethany restored from the tomb, exactly one man only",
        "clean loose linen bands over an olive robe, grateful recovering expression, not horror imagery",
    ],
    "martha": [
        "Martha of Bethany, hospitable sister of Lazarus, exactly one woman only",
        "household serving cloth and small bread basket, capable attentive expression",
    ],
    "judas": [
        "Judas Iscariot the treasurer disciple, exactly one man only",
        "dark olive robe, coin pouch close to body, guarded expression, no villain caricature",
    ],
    "pilate": [
        "Pontius Pilate the Roman governor, exactly one man only",
        "ivory tunic, red-edged toga cloak, legal tablet, Roman cropped hair, not Herod",
    ],
    "mary_magdalene": [
        "Mary Magdalene the resurrection witness, exactly one adult woman only",
        "soft rose shawl and cream robe, hopeful dawn-witness expression, hands empty",
    ],
    "thomas": [
        "Thomas the disciple, exactly one man only",
        "gray-blue robe, measuring cord, thoughtful searching expression, not fearful",
    ],
    "stephen": [
        "Stephen the Hellenistic deacon and martyr, exactly one man only",
        "plain linen service tunic, folded serving cloth, courageous peaceful face",
    ],
    "paul": [
        "Paul the road-worn missionary apostle, exactly one man only",
        "strict front-facing full-body avatar, face and torso square to the viewer, both eyes visible",
        "compact intense build, receding dark hair, dark teal travel cloak, centered scroll satchel, vertical staff",
        "distinct from Barnabas by sharper face and more focused expression",
        "no side profile, no three-quarter view, no leaning pose, no turned head",
    ],
    "barnabas": [
        "Barnabas the encourager and missionary companion, exactly one man only",
        "broad warm build, olive-green travel cloak, open hands, small gift purse",
        "distinct from Paul by rounder face and warmer posture",
    ],
    "cornelius": [
        "Cornelius the Roman centurion who receives Peter, exactly one man only",
        "bronze armor, deep red tunic, disciplined prayerful posture, not a Judean elder",
    ],
    "john_mark": [
        "John Mark the young adult missionary assistant and scribe, exactly one man only",
        "warm ochre travel tunic, shoulder satchel, small blank parchment roll",
        "youthful assistant look, distinct from John the apostle and John the Baptist",
    ],
    "james": [
        "James the Jerusalem church elder, exactly one man only",
        "plain cream prayer shawl, council scroll, wise elder expression",
        "distinct from James son of Zebedee by elder robe and no fishing gear",
    ],
    "silas": [
        "Silas the prophet companion of Paul, exactly one man only",
        "indigo travel hood, hymn scroll, resilient companion posture",
    ],
    "timothy": [
        "Timothy the young adult coworker of Paul, exactly one man only",
        "blue-gray robe, folded letter packet, earnest humble confidence",
    ],
    "lydia": [
        "Lydia the purple-cloth merchant and faithful host, exactly one woman only",
        "purple cloth bolt, modest merchant robe, welcoming dignified expression",
    ],
    "aquila": [
        "Aquila the Jewish tentmaker and teacher, exactly one man only",
        "leather apron, awl, tent cloth roll, practical craftsman posture",
    ],
    "priscilla": [
        "Priscilla the Jewish tentmaker and scripture teacher, exactly one woman only",
        "same compact low-poly flat vector avatar world as Mary, Lydia, and other existing women",
        "teal headscarf, modest teal robe, warm brown work dress, folded tent cloth and blank teaching scroll",
        "calm teacher expression, not realistic, not glamorous, not a different art style",
    ],
    "festus": [
        "Festus the Roman governor hearing Paul's case, exactly one man only",
        "formal cream toga with muted red trim, legal scroll, severe administrative face",
    ],
    "agrippa": [
        "King Agrippa hearing Paul's defense, exactly one man only",
        "purple-gold court robe, small diadem, curious royal expression, not a Roman governor",
    ],
}

NT_STYLE_REFERENCE_CODES = {
    "joseph_nazareth": ["jesus", "mary"],
    "elizabeth": ["mary", "ruth", "naomi"],
    "john_the_baptist": ["elijah", "isaiah"],
    "andrew": ["peter", "john"],
    "peter": ["andrew", "john"],
    "philip": ["peter", "john"],
    "philip_evangelist": ["stephen", "peter"],
    "james_zebedee": ["peter", "john"],
    "john": ["peter", "andrew"],
    "matthew": ["peter", "john"],
    "mary_magdalene": ["mary", "lydia"],
    "paul": ["barnabas", "peter"],
    "barnabas": ["paul", "peter"],
    "john_mark": ["barnabas", "paul"],
    "james": ["peter", "john"],
    "silas": ["paul", "barnabas"],
    "timothy": ["paul", "silas"],
    "aquila": ["paul", "barnabas"],
    "priscilla": ["ruth", "esther", "deborah"],
}

CHARACTER_VISUAL_OVERRIDES.update(NT_CHARACTER_VISUAL_OVERRIDES)
CHARACTER_MOOD_OVERRIDES.update(NT_CHARACTER_MOOD_OVERRIDES)
CODE_PALETTE_OVERRIDES.update(NT_CODE_PALETTE_OVERRIDES)
CODE_SIGNATURE_HINTS.update(NT_CODE_SIGNATURE_HINTS)

CHARACTER_VISUAL_OVERRIDES["matthias"] = [
    "Matthias the apostle chosen after Judas build with humble adult witness posture",
    "warm Judean face with steady sincere eyes, short dark beard, and calm prayerful brow",
    "short dark hair under a simple travel headcloth, not a fisherman and not Paul",
    "warm cream apostle robe with muted olive cloak, small pouch of blank lot stones and a blank witness scroll held close",
]
CHARACTER_MOOD_OVERRIDES["matthias"] = [
    "strict front-facing newly chosen apostle posture, lot-stone pouch and blank scroll visible, humble steady witness expression",
]
CODE_PALETTE_OVERRIDES["matthias"] = (
    "warm cream + muted olive cloak + parchment scroll + small stone accents, low saturation"
)
CODE_SIGNATURE_HINTS["matthias"] = [
    "Matthias the apostle chosen by lot to replace Judas, exactly one man only",
    "strict front-facing full-body avatar, face and torso square to the viewer, both eyes visible",
    "warm cream robe with muted olive cloak, small pouch of blank lot stones and a blank witness scroll as the main identity signs",
    "humble sincere witness expression, not Paul, not Barnabas, not Judas, no fisherman net and no weapon",
]
NT_STYLE_REFERENCE_CODES["matthias"] = ["peter", "john", "james"]

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
        description="Build character meta JSON (codes, names, avatar prompts) from assets/events data."
    )
    parser.add_argument(
        "--stories-dir",
        default="assets/events",
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
            "Judges-era story characters are also active with one mention."
        ),
    )
    return parser.parse_args()


def parse_event_number(raw_title: str) -> int:
    """제목 앞 3자리 번호가 있으면 반환, 없으면 0.

    번호가 빠진 신 JSON 포맷에서는 0 을 반환 → caller 가 row['story_index'] 로
    fallback 정렬해야 한다 (load_story_rows 가 처리).
    """
    match = EVENT_NO_RE.match(raw_title.strip())
    if match is None:
        return 0
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
    # title 앞 번호가 없는 새 포맷 → story_index 로 안정 정렬.
    rows.sort(
        key=lambda row: (
            int(row["story_index"]) if isinstance(row.get("story_index"), int) else 0,
            str(row.get("title", "")),
        )
    )
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


def append_negative_prompt_extra(
    character: dict[str, Any],
    extra: str,
) -> None:
    extra = extra.strip()
    if not extra:
        return
    current = str(character.get("negative_prompt_extra", "")).strip()
    character["negative_prompt_extra"] = ", ".join(
        part for part in [current, extra] if part
    )


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
        "divided_kingdom",
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


def normalize_palette_text(palette_text: str) -> str:
    text = " ".join(str(palette_text).split())
    return text.replace(
        "low saturation",
        "medium saturation with rich deep color blocks and clear contrast",
    )


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
    source_label: str = "assets/events",
) -> dict[str, Any]:
    avatar_roster = {
        **CURATED_AVATAR_ROSTER,
        **UI_ONLY_AVATAR_ROSTER,
    }
    mention_counts: Counter[str] = Counter()
    era_votes: dict[str, Counter[str]] = defaultdict(Counter)
    story_profiles: dict[str, dict[str, list[dict[str, Any]]]] = defaultdict(
        lambda: defaultdict(list)
    )

    for row in rows:
        # title 앞 번호 우선, 없으면 story_index 로 fallback.
        number = parse_event_number(str(row.get("title", "")))
        if number == 0 and isinstance(row.get("story_index"), int):
            number = int(row["story_index"])
        era_style = normalize_style_era(str(row.get("era", "")))
        raw_persons = [
            str(code).strip() for code in row.get("characters", []) if str(code).strip()
        ]
        for scene_characters in row.get("scene_characters", []) or []:
            if not isinstance(scene_characters, list):
                continue
            raw_persons.extend(
                str(code).strip() for code in scene_characters if str(code).strip()
            )
        raw_persons = dedupe_preserve_order(raw_persons)
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
    selected_code_set = set(selected_codes)
    for code in avatar_roster:
        if code not in selected_code_set:
            selected_codes.append(code)
            selected_code_set.add(code)

    palettes = style_source["palettes"]
    default_style = "patriarch"

    characters: list[dict[str, Any]] = []
    for idx, code in enumerate(selected_codes, start=1):
        template = template_map.get(code, {})
        curated = avatar_roster.get(code, {})
        template_prompt_source = str(template.get("prompt_source", "")).strip().lower()
        curated_prompt_source = str(curated.get("prompt_source", "")).strip().lower()
        if code in FORCE_AUTO_PROMPT_CODES:
            template_prompt_source = ""
        if code in UI_ONLY_AVATAR_ROSTER:
            template_prompt_source = ""

        voted_style = default_style
        if era_votes.get(code):
            voted_style = sorted(
                era_votes[code].items(), key=lambda item: (-item[1], item[0])
            )[0][0]
        elif curated.get("era"):
            voted_style = normalize_style_era(str(curated["era"]))

        if template_prompt_source == "manual" and template.get("era"):
            era_style = normalize_style_era(str(template["era"]))
        elif era_votes.get(code):
            era_style = voted_style
        elif curated.get("era"):
            era_style = normalize_style_era(str(curated["era"]))
        else:
            era_style = default_style
        if era_style not in palettes:
            era_style = voted_style if voted_style in palettes else default_style

        name_en = (
            str(template.get("name_en", "")).strip()
            or str(curated.get("name_en", "")).strip()
            or EN_NAME_OVERRIDES.get(code, "")
            or prettify_name_en(code)
        )
        template_name_ko = str(template.get("name_ko", "")).strip()
        if has_hangul(template_name_ko):
            name_ko = template_name_ko
        elif has_hangul(str(curated.get("name_ko", "")).strip()):
            name_ko = str(curated["name_ko"]).strip()
        elif code in KO_NAME_OVERRIDES:
            name_ko = KO_NAME_OVERRIDES[code]
        elif template_name_ko:
            name_ko = template_name_ko
        else:
            name_ko = name_en

        palette_text = CODE_PALETTE_OVERRIDES.get(
            code,
            str(palettes.get(era_style, palettes[default_style])),
        )
        palette_text = normalize_palette_text(palette_text)
        prompt = ""
        if template_prompt_source == "manual":
            prompt = str(template.get("prompt", "")).strip()
        elif curated_prompt_source == "manual":
            prompt = str(curated.get("prompt", "")).strip()
        use_common_style = bool(template.get("use_common_style", True))
        disable_adult_guardrail = bool(template.get("disable_adult_guardrail", False))
        person_generation = str(template.get("person_generation", "")).strip()
        asset_only = bool(template.get("asset_only", curated.get("asset_only", False)))
        prompt_source = (
            template_prompt_source
            if template_prompt_source == "manual"
            else (
                curated_prompt_source
                if curated_prompt_source == "manual"
                else AUTO_PROMPT_SOURCE
            )
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

        appears_in_judges_story = bool(story_profiles.get(code, {}).get("judges"))
        is_active_default = mention_counts[code] >= active_threshold or (
            appears_in_judges_story and mention_counts[code] >= 1
        )
        if code in FORCE_ACTIVE_DEFAULT_CODES:
            is_active_default = True
        if code in FORCE_INACTIVE_DEFAULT_CODES:
            is_active_default = False
        if asset_only:
            is_active_default = False

        character = {
            "index": idx,
            "code": code,
            "name_ko": name_ko,
            "name_en": name_en,
            "era": era_style,
            "prompt": prompt,
            "prompt_source": prompt_source,
            "mention_count": mention_counts[code],
            "is_active_default": is_active_default,
        }
        if asset_only:
            character["asset_only"] = True
        if not use_common_style:
            character["use_common_style"] = False
        if disable_adult_guardrail:
            character["disable_adult_guardrail"] = True
        if person_generation:
            character["person_generation"] = person_generation
        curated_style_reference_codes = [
            str(reference_code).strip()
            for reference_code in curated.get("style_reference_codes", [])
            if str(reference_code).strip()
        ]
        if curated_style_reference_codes:
            character["style_reference_codes"] = curated_style_reference_codes
        curated_negative_prompt_extra = str(
            curated.get("negative_prompt_extra", "")
        ).strip()
        if curated_negative_prompt_extra:
            append_negative_prompt_extra(character, curated_negative_prompt_extra)
        if code == "god":
            character["negative_prompt_extra"] = GOD_NEGATIVE_PROMPT_EXTRA
        if code == "gabriel":
            character["negative_prompt_extra"] = GABRIEL_NEGATIVE_PROMPT_EXTRA
        if code == "haman":
            character["negative_prompt_extra"] = HAMAN_NEGATIVE_PROMPT_EXTRA
        if code == "adam":
            character["negative_prompt_extra"] = ADAM_NEGATIVE_PROMPT_EXTRA
        if code == "eve":
            character["negative_prompt_extra"] = EVE_NEGATIVE_PROMPT_EXTRA
        if code == "abraham":
            character["negative_prompt_extra"] = ABRAHAM_NEGATIVE_PROMPT_EXTRA
        if code == "aaron":
            character["negative_prompt_extra"] = AARON_NEGATIVE_PROMPT_EXTRA
        if code == "moses":
            character["negative_prompt_extra"] = MOSES_NEGATIVE_PROMPT_EXTRA
        if code == "joseph":
            character["negative_prompt_extra"] = JOSEPH_NEGATIVE_PROMPT_EXTRA
        if code == "david":
            character["negative_prompt_extra"] = DAVID_NEGATIVE_PROMPT_EXTRA
        if code == "elijah":
            character["negative_prompt_extra"] = ELIJAH_NEGATIVE_PROMPT_EXTRA
        if code == "korah":
            character["negative_prompt_extra"] = KORAH_NEGATIVE_PROMPT_EXTRA
        if code == "phinehas":
            character["negative_prompt_extra"] = PHINEHAS_NEGATIVE_PROMPT_EXTRA
        if code == "matthias":
            character["negative_prompt_extra"] = MATTHIAS_NEGATIVE_PROMPT_EXTRA
        if code == "asher":
            character["negative_prompt_extra"] = ASHER_NEGATIVE_PROMPT_EXTRA
        if code == "ahijah":
            character["negative_prompt_extra"] = AHIJAH_NEGATIVE_PROMPT_EXTRA
        if code in {"levi", "issachar"}:
            character["negative_prompt_extra"] = LEVI_ISSACHAR_NEGATIVE_PROMPT_EXTRA
        if code == "zebulun":
            character["negative_prompt_extra"] = ZEBULUN_NEGATIVE_PROMPT_EXTRA
        if code == "noah":
            character["negative_prompt_extra"] = NOAH_NEGATIVE_PROMPT_EXTRA
        if code == "nehemiah":
            character["negative_prompt_extra"] = NEHEMIAH_NEGATIVE_PROMPT_EXTRA
        if code == "sarah":
            character["negative_prompt_extra"] = SARAH_NEGATIVE_PROMPT_EXTRA
        if code == "rachel":
            character["negative_prompt_extra"] = RACHEL_NEGATIVE_PROMPT_EXTRA
        if code == "samuel":
            character["negative_prompt_extra"] = SAMUEL_NEGATIVE_PROMPT_EXTRA
        if code == "saul":
            character["negative_prompt_extra"] = SAUL_NEGATIVE_PROMPT_EXTRA
        if code == "daniel":
            character["negative_prompt_extra"] = DANIEL_NEGATIVE_PROMPT_EXTRA
        if code == "judah":
            character["negative_prompt_extra"] = JUDAH_NEGATIVE_PROMPT_EXTRA
        if code == "laban":
            character["negative_prompt_extra"] = LABAN_NEGATIVE_PROMPT_EXTRA
        if code == "caleb":
            character["negative_prompt_extra"] = CALEB_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["moses", "joshua"]
        if code == "absalom":
            character["negative_prompt_extra"] = ABSALOM_NEGATIVE_PROMPT_EXTRA
        if code == "ruth":
            character["negative_prompt_extra"] = RUTH_NEGATIVE_PROMPT_EXTRA
        if code == "goliath":
            character["negative_prompt_extra"] = GOLIATH_NEGATIVE_PROMPT_EXTRA
        if code == "naaman":
            character["negative_prompt_extra"] = NAAMAN_NEGATIVE_PROMPT_EXTRA
        if code == "hoshea_king":
            character["negative_prompt_extra"] = HOSHEA_KING_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["ahab", "jeroboam", "rehoboam"]
        if code == "ahaz":
            character["negative_prompt_extra"] = AHAZ_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["rehoboam", "hezekiah", "josiah"]
        if code == "zerubbabel":
            character["negative_prompt_extra"] = ZERUBBABEL_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["ezra", "nehemiah", "isaiah"]
        if code == "haggai":
            character["negative_prompt_extra"] = HAGGAI_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["isaiah", "ezra", "nehemiah"]
        if code == "zechariah_prophet":
            character["negative_prompt_extra"] = ZECHARIAH_PROPHET_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["isaiah", "ezra", "nehemiah"]
        if code == "jonah":
            character["negative_prompt_extra"] = JONAH_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["elijah", "elisha", "isaiah"]
        if code == "micaiah":
            character["negative_prompt_extra"] = MICAIAH_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["elijah", "elisha", "isaiah"]
        if code == "jeremiah":
            character["negative_prompt_extra"] = JEREMIAH_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["isaiah", "ezekiel", "ezra"]
        if code == "ezekiel":
            character["negative_prompt_extra"] = EZEKIEL_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["isaiah", "jeremiah", "ezra"]
        if code == "jehoiakim":
            character["negative_prompt_extra"] = JEHOIAKIM_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["josiah", "ahaz", "zedekiah"]
        if code == "jehoiada":
            character["negative_prompt_extra"] = JEHOIADA_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["aaron", "samuel", "josiah"]
        if code == "jezebel":
            character["negative_prompt_extra"] = JEZEBEL_NEGATIVE_PROMPT_EXTRA
            character["style_reference_codes"] = ["esther", "athaliah", "ahab"]
        if code in DIVIDED_KINGDOM_KING_ROSTER:
            append_negative_prompt_extra(
                character,
                DIVIDED_KINGDOM_KING_NEGATIVE_PROMPT_EXTRA,
            )
            append_negative_prompt_extra(
                character,
                str(DIVIDED_KINGDOM_KING_ROSTER[code].get("negative", "")),
            )
        if code == "ahab":
            append_negative_prompt_extra(character, AHAB_NEGATIVE_PROMPT_EXTRA)
        if code == "isaiah":
            character["negative_prompt_extra"] = ISAIAH_NEGATIVE_PROMPT_EXTRA
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
        if code == "hagar":
            character["negative_prompt_extra"] = HAGAR_NEGATIVE_PROMPT_EXTRA
        if code in FEMALE_FORCE_CODES:
            character["negative_prompt_extra"] = FEMALE_FORCE_NEGATIVE_PROMPT_EXTRA
        if code == "hannah":
            append_negative_prompt_extra(character, HANNAH_NEGATIVE_PROMPT_EXTRA)
        if code == "rahab":
            append_negative_prompt_extra(character, RAHAB_NEGATIVE_PROMPT_EXTRA)
        if code in SOLO_FORCED_CODES:
            append_negative_prompt_extra(character, SOLO_NEGATIVE_PROMPT_EXTRA)
        if code in CURATED_AVATAR_ROSTER:
            style_reference_codes = [
                str(reference_code).strip()
                for reference_code in curated.get("style_reference_codes", [])
                if str(reference_code).strip()
            ]
            if style_reference_codes:
                character["style_reference_codes"] = style_reference_codes
            append_negative_prompt_extra(
                character,
                JUDGES_AVATAR_NEGATIVE_PROMPT_EXTRA,
            )
            append_negative_prompt_extra(
                character,
                JUDGE_SPECIFIC_NEGATIVE_PROMPTS.get(code, ""),
            )
        if code in NT_STYLE_REFERENCE_CODES:
            style_reference_codes = [
                reference_code
                for reference_code in NT_STYLE_REFERENCE_CODES[code]
                if reference_code != code
            ]
            if style_reference_codes:
                character["style_reference_codes"] = style_reference_codes
        characters.append(character)

    forced_active_note = ", ".join(
        f"{code}=true" for code in sorted(FORCE_ACTIVE_DEFAULT_CODES)
    )
    forced_inactive_note = ", ".join(
        f"{code}=false" for code in sorted(FORCE_INACTIVE_DEFAULT_CODES)
    )
    visibility_override_note = ", ".join(
        part for part in [forced_active_note, forced_inactive_note] if part
    )

    output = {
        "meta": {
            "title": "Bible avatar prompts (all individuals from 200 stories)",
            "version": "3.0",
            "count": len(characters),
            "style_source": AUTO_PROMPT_SOURCE,
            "active_threshold": active_threshold,
            "curated_avatar_roster_codes": list(CURATED_AVATAR_ROSTER.keys()),
            "ui_only_avatar_codes": list(UI_ONLY_AVATAR_ROSTER.keys()),
            "note": (
                f"Generated from {source_label} with "
                "disciples/apostles/brothers expanded to individuals. "
                f"All characters with mention_count >= {min_mentions} are emitted; "
                f"is_active_default=true when mention_count >= {active_threshold}, "
                "or when a character appears in an era_judges story at least once. "
                "Some codes have explicit visibility overrides, including "
                f"{visibility_override_note}. "
                "Curated avatar roster entries may have mention_count=0 so avatars "
                "can be prepared before their story events are written. Runtime "
                "visibility is controlled by characters.is_active in DB. UI-only "
                "avatar entries are marked asset_only=true and are generated as "
                "PNG assets but skipped by DB seed builders."
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
        source_label=str(stories_dir),
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
