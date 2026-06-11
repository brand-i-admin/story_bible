#!/usr/bin/env python3
"""Build tools/seed/character_meta.json from assets/200_stories JSON files.

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
        "centered inside a square 1:1 avatar canvas, plain white background, "
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
    "deborah": "드보라",
    "eve": "하와",
    "james": "야고보",
    "lot": "롯",
    "noah": "노아",
    "rachel": "라헬",
    "ruth": "룻",
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
    "rehoboam": "르호보암",
    "samson": "삼손",
    "sapphira": "삽비라",
    "seth": "셋",
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
    "ahaz",
    "haggai",
    "hoshea_king",
    "jeroboam",
    "jehoiakim",
    "jonah",
    "jonathan",
    "josiah",
    "micaiah",
    "naaman",
    "rehoboam",
    "zechariah_prophet",
    "zedekiah",
    "zerubbabel",
}
FORCE_INACTIVE_DEFAULT_CODES = {"elizabeth", "gabriel", "god"}

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
    "king, queen, banquet crowd, attendants, throne scene"
)
DANIEL_NEGATIVE_PROMPT_EXTRA = "multiple people, crowd, group, duo, pair, two people, extra character, background character"
DAN_NEGATIVE_PROMPT_EXTRA = "multiple people, crowd, group, duo, pair, two people, extra character, background character"
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
    "cute soft mascot, childlike innocence, angry warrior, aggressive fighter, armor"
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
FEMALE_FORCE_CODES = {"dinah", "hannah", "sapphira"}

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
    "absalom": "deep royal blue + muted crimson + warm gold accents, low saturation",
    "ahaz": "deep royal indigo + muted purple + warm gold trim + ash gray accent, low saturation",
    "caleb": "muted teal + parchment cream + warm clay brown accents, low saturation",
    "deborah": "olive green + warm parchment + muted clay rose accents",
    "ehud": "deep olive + desert tan + muted bronze accents",
    "hagar": "desert teal + copper + deep indigo accents",
    "haggai": "weathered clay + parchment cream + muted crimson accents, low saturation",
    "hoshea_king": "storm blue + iron gray + muted bronze accents, low saturation",
    "isaiah": "deep indigo + ash gray + ember gold accents, low saturation",
    "jehoiakim": "deep crimson + royal indigo + dark gold trim + ash gray accents, low saturation",
    "jeremiah": "weathered olive + clay brown + muted crimson + parchment cream accents, low saturation",
    "jeroboam": "deep forest green + muted bronze + parchment tan accents, low saturation",
    "jonah": "sea teal + storm gray + parchment cream accents, low saturation",
    "micaiah": "deep olive + muted charcoal + pale parchment + small gold accents, low saturation",
    "rehoboam": "royal indigo + warm gold + muted ivory accents, low saturation",
    "samson": "deep olive + clay brown + muted gold accents",
    "zechariah_prophet": "muted indigo + sage green + parchment cream accents, low saturation",
    "zerubbabel": "deep olive + stone gray + muted gold accents, low saturation",
}

CODE_SIGNATURE_HINTS = {
    "abraham": ["nomadic patriarch silhouette", "travel-worn layered robe"],
    "aaron": ["ceremonial leader silhouette", "priestly layered sash"],
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
    "jeroboam": [
        "ambitious servant of Solomon who will become northern kingdom ruler",
        "deep green official cloak with bronze sash, no crown",
        "small torn cloak piece in one hand as a restrained sign of Ahijah's prophecy",
        "serious alert expression, not a battle scene",
    ],
    "ahijah": [
        "elderly prophet from Shiloh, wise and solemn, clearly distinct from Samuel and Isaiah",
        "clouded blind-looking eyes for the later warning scene, calm but severe expression",
        "plain warm brown prophet mantle with a muted cream inner robe",
        "one hand holding torn cloak pieces as the unmistakable sign of the divided kingdom",
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
    "hagar": [
        "single young adult Egyptian servant woman silhouette, one woman only",
        "plain desert teal ankle-length dress with a simple copper cloth sash",
        "deep indigo head scarf, no jewelry and no ornate headband",
        "small water-skin held at her side, standing alone",
        "humble desert servant presence, not a noble mistress",
        "full body single centered woman, no surrounding characters",
    ],
    "haman": [
        "scheming court-official silhouette",
        "sealed decree scroll and signet ring",
        "single arrogant court-villain presence",
    ],
    "isaiah": [
        "Jerusalem royal-court prophet silhouette, not a listening child-prophet",
        "deep indigo mantle over an ash-gray robe with parchment cream sash",
        "full-body standing figure with visible robe hem, legs, and sandals",
        "small narrow open blank prophecy scroll held upright and a small ember-coal clasp as Isaiah's calling sign",
        "stern visionary presence, uncovered hair, no hooded head covering",
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
        # title 앞 번호 우선, 없으면 story_index 로 fallback.
        number = parse_event_number(str(row.get("title", "")))
        if number == 0 and isinstance(row.get("story_index"), int):
            number = int(row["story_index"])
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
    selected_code_set = set(selected_codes)
    for code in CURATED_AVATAR_ROSTER:
        if code not in selected_code_set:
            selected_codes.append(code)
            selected_code_set.add(code)

    palettes = style_source["palettes"]
    default_style = "patriarch"

    characters: list[dict[str, Any]] = []
    for idx, code in enumerate(selected_codes, start=1):
        template = template_map.get(code, {})
        curated = CURATED_AVATAR_ROSTER.get(code, {})
        template_prompt_source = str(template.get("prompt_source", "")).strip().lower()

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

        appears_in_judges_story = bool(story_profiles.get(code, {}).get("judges"))
        is_active_default = mention_counts[code] >= active_threshold or (
            appears_in_judges_story and mention_counts[code] >= 1
        )
        if code in FORCE_ACTIVE_DEFAULT_CODES:
            is_active_default = True
        if code in FORCE_INACTIVE_DEFAULT_CODES:
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
            "note": (
                "Generated from assets/200_stories with "
                "disciples/apostles/brothers expanded to individuals. "
                f"All characters with mention_count >= {min_mentions} are emitted; "
                f"is_active_default=true when mention_count >= {active_threshold}, "
                "or when a character appears in an era_judges story at least once. "
                "Some codes have explicit visibility overrides, including "
                f"{visibility_override_note}. "
                "Curated avatar roster entries may have mention_count=0 so avatars "
                "can be prepared before their story events are written. Runtime "
                "visibility is controlled by characters.is_active in DB."
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
