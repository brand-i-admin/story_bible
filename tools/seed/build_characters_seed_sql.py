#!/usr/bin/env python3
"""Build SQL seed for the characters table from character meta + stories.

- characters rows are created from tools/seed/character_meta.json (every individual).
- ``is_active`` is taken from each character's ``is_active_default`` so that
  most single-mention newcomers stay hidden until an admin enables them, while
  pipeline-approved active rows can be promoted to visible on seed apply.
- person_eras is no longer materialized here: it is a view derived from
  ``events.character_codes`` (see db_init.sql).
"""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
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
ROSTER_EXCLUDED_CODES = {"dan", "lot_wife"}
FORCE_INACTIVE_CODES = {"elizabeth", "gabriel", "god"}

STYLE_TO_ERA_CODE = {
    "primeval": "era_primeval",
    "patriarch": "era_patriarch",
    "exodus_wilderness": "era_exodus",
    "judges": "era_judges",
    "monarchy": "era_monarchy",
    "divided_kingdom": "era_divided_kingdom",
    "prophets_exile": "era_exile_return",
    "post_exile_return": "era_exile_return",
    "gospels": "era_nt_public_ministry",
    "early_church": "era_nt_apostolic",
}

ERA_ORDER = [
    "era_primeval",
    "era_patriarch",
    "era_exodus",
    "era_judges",
    "era_monarchy",
    "era_divided_kingdom",
    "era_exile_return",
    "era_nt_public_ministry",
    "era_nt_apostolic",
    "era_nt_post_apostolic",
    "era_nt_consummation",
]

ADULT_GUARDRAIL = (
    "all characters are clearly adults age 25+, adult body proportions, "
    "fully clothed, no children, no minors, non-photoreal 2D cartoon "
    "illustration, stylized geometric character, not a real character photo"
)

PERSON_DESCRIPTION_OVERRIDES = {
    "god": "하나님은 세상을 창조하시고 역사를 주관하시는 분이다. 성경의 모든 이야기는 하나님의 뜻과 구원 계획 안에서 이어진다.",
    "jesus": "예수님은 하나님의 아들로, 사람들에게 하나님 나라를 가르치고 병든 자를 고치셨다. 십자가와 부활로 구원의 길을 여신 분이다.",
    "mary": "마리아는 예수님의 어머니로, 하나님의 부르심에 믿음으로 응답한 인물이다.",
    "gabriel": "가브리엘은 하나님의 소식을 전하는 천사로, 세례 요한과 예수님의 탄생 예고 장면에 등장한다.",
    "moses": "모세는 이스라엘 백성을 이집트에서 이끌어 낸 출애굽의 지도자다. 시내산에서 율법을 받아 백성에게 전했다.",
    "aaron": "아론은 모세의 형으로, 출애굽 과정에서 모세를 도왔다. 이스라엘의 첫 대제사장으로도 중요한 위치를 차지한다.",
    "joshua": "여호수아는 모세의 뒤를 이어 이스라엘 백성을 가나안으로 이끈 지도자다. 믿음과 순종으로 약속의 땅 정복을 이끌었다.",
    "samuel": "사무엘은 사사이자 예언자로, 이스라엘이 왕정으로 넘어가는 중요한 시기를 이끈 인물이다.",
    "saul": "사울은 이스라엘의 첫 번째 왕이다. 처음에는 겸손했지만 점차 하나님께 불순종하며 비극적인 끝을 맞았다.",
    "david": "다윗은 목동 출신으로 골리앗을 물리치고 이스라엘의 왕이 되었다. 시편과 깊이 연결되는 인물이다.",
    "solomon": "솔로몬은 다윗의 아들로, 지혜로 유명한 이스라엘의 왕이다. 예루살렘 성전을 세운 왕으로도 알려져 있다.",
    "nathan": "나단은 다윗 시대의 예언자로, 다윗의 죄를 책망하고 하나님의 약속을 전한 인물이다.",
    "elijah": "엘리야는 북이스라엘에서 활동한 예언자다. 갈멜산 대결과 하나님의 불 응답 이야기로 잘 알려져 있다.",
    "elisha": "엘리사는 엘리야의 뒤를 이어 활동한 예언자다. 여러 기적 이야기로 잘 알려져 있다.",
    "ahijah": "아히야는 실로 출신 선지자로, 여로보암에게 찢어진 옷의 표징을 보이고 그의 집에 임할 하나님의 경고를 전했다.",
    "micaiah": "미가야는 이믈라의 아들 선지자로, 아합과 여호사밧 앞에서 거짓 예언에 맞서 하나님의 말씀을 곧게 전했다.",
    "jezebel": "이세벨은 시돈 왕가 출신으로 아합과 함께 북이스라엘에 바알 숭배를 깊이 들여온 왕비다. 나봇의 포도원 사건에서도 악한 계략을 꾸민다.",
    "jehoiada": "여호야다는 예루살렘 성전의 제사장으로, 아달랴 시대에 어린 요아스를 보호하고 언약을 새롭게 세워 다윗 왕조를 이어 가게 한 인물이다.",
    "isaiah": "이사야는 유다에서 활동한 예언자로, 심판과 회복 그리고 메시아에 대한 소망을 선포했다.",
    "jeremiah": "예레미야는 예루살렘 멸망 전후에 활동한 예언자다. 눈물의 예언자로 불릴 만큼 아픈 시대에 말씀을 전했다.",
    "ezekiel": "에스겔은 바벨론 포로 시기에 활동한 예언자다. 상징 행동과 환상을 통해 하나님의 말씀을 전했다.",
    "daniel": "다니엘은 바벨론 포로 시기에 하나님께 끝까지 충성한 인물이다. 지혜와 믿음으로 왕들 앞에서도 흔들리지 않았다.",
    "ezra": "에스라는 포로 귀환 이후 백성에게 율법을 가르치고 공동체를 바로 세운 학자 겸 제사장이다.",
    "nehemiah": "느헤미야는 페르시아 궁정에서 일하다가 예루살렘 성벽 재건을 이끈 지도자다.",
    "esther": "에스더는 페르시아 제국의 왕후가 되어 자기 민족을 위기에서 구한 인물이다. 지혜와 용기로 중요한 때를 붙든다.",
    "mordecai": "모르드개는 에스더를 돌보며 유다 민족을 지키기 위해 힘쓴 인물이다. 에스더 이야기에서 중요한 조언자 역할을 한다.",
    "haman": "하만은 페르시아 제국에서 유다인을 없애려 한 악한 고관이다. 에스더 이야기의 주요 대적자로 나온다.",
    "abraham": "아브라함은 하나님의 부르심을 따라 고향을 떠난 믿음의 조상이다. 하나님은 그에게 자손과 땅에 대한 약속을 주셨다.",
    "sarah": "사라는 아브라함의 아내이자 이삭의 어머니이다. 늦은 나이에 약속의 아들을 낳았다.",
    "lot": "롯은 아브라함의 조카로, 소돔과 고모라 이야기에서 잘 알려진다.",
    "hagar": "하갈은 사라의 여종이었고 아브라함을 통해 이스마엘을 낳았다. 광야에서 하나님이 자신을 돌보심을 경험한다.",
    "ishmael": "이스마엘은 아브라함과 하갈 사이에서 태어난 아들이다. 광야로 나가게 되지만 하나님이 그와 그의 어머니를 돌보셨다.",
    "isaac": "이삭은 아브라함과 사라에게 약속으로 주어진 아들이다. 야곱과 에서의 아버지이기도 하다.",
    "rebekah": "리브가는 이삭의 아내이자 야곱과 에서의 어머니이다. 족장 이야기에서 중요한 선택의 순간들과 함께 등장한다.",
    "esau": "에서는 이삭의 아들이자 야곱의 형이다. 장자권을 가볍게 여긴 이야기로 잘 알려져 있다.",
    "jacob": "야곱은 이삭과 리브가의 아들로, 이스라엘 열두 지파의 조상이 되었다. 하나님과 씨름한 뒤 이스라엘이라는 이름을 받았다.",
    "laban": "라반은 리브가의 오빠이자 야곱의 외삼촌이다. 야곱이 그의 집에서 오랫동안 일하며 레아와 라헬을 아내로 맞게 된다.",
    "leah": "레아는 라반의 딸이자 야곱의 아내이다. 여러 아들의 어머니가 되어 이스라엘 가계에서 중요한 위치를 차지한다.",
    "rachel": "라헬은 야곱이 사랑한 아내이며 요셉과 베냐민의 어머니이다.",
    "joseph": "요셉은 야곱의 아들로, 형들에게 팔려 이집트에 갔지만 하나님의 인도 속에 총리가 되었다. 기근 속에서 가족을 살린 인물이다.",
    "judah": "유다는 야곱의 아들 가운데 한 사람으로, 훗날 메시아 계보와 연결되는 지파의 조상이 되었다.",
    "reuben": "르우벤은 야곱의 맏아들이다. 장자의 위치를 가졌지만 그 책임을 끝까지 지키지는 못했다.",
    "simeon": "시므온은 야곱의 아들 가운데 한 사람이다. 레위와 함께 디나 사건에서 강한 분노를 드러낸 인물로 나온다.",
    "levi": "레위는 야곱의 아들 가운데 한 사람이다. 훗날 레위 지파는 성막과 성전 섬김을 맡게 된다.",
    "asher": "아셀은 야곱의 아들 가운데 한 사람이다. 훗날 이스라엘 열두 지파 가운데 하나의 조상이 되었다.",
    "benjamin": "베냐민은 야곱과 라헬 사이에서 태어난 막내아들이다. 요셉 이야기에서 형제들의 변화와 함께 중요한 역할을 한다.",
    "gad": "갓은 야곱의 아들 가운데 한 사람이다. 훗날 이스라엘 열두 지파 가운데 하나의 조상이 되었다.",
    "issachar": "잇사갈은 야곱의 아들 가운데 한 사람이다. 훗날 이스라엘 열두 지파 가운데 하나의 조상이 되었다.",
    "naphtali": "납달리는 야곱의 아들 가운데 한 사람이다. 훗날 이스라엘 열두 지파 가운데 하나의 조상이 되었다.",
    "zebulun": "스불론은 야곱의 아들 가운데 한 사람이다. 훗날 이스라엘 열두 지파 가운데 하나의 조상이 되었다.",
    "pharaoh": "바로는 출애굽 이야기에서 이스라엘 백성을 억압한 이집트의 왕이다. 완고한 마음으로 하나님의 경고를 거듭 거부했다.",
    "gideon": "기드온은 미디안의 압제 아래 있던 이스라엘을 구하도록 부름받은 사사이다. 작은 수의 군사로 하나님의 구원을 경험했다.",
    "abimelech": "아비멜렉은 기드온의 아들로, 스스로 왕이 되려 했던 인물이다. 권력을 향한 욕심이 결국 비극으로 이어졌다.",
    "hezekiah": "히스기야는 유다의 왕으로, 하나님을 의지하며 종교 개혁을 이루려 했던 인물이다.",
    "ahab": "아합은 북이스라엘의 왕으로, 우상숭배와 악한 통치로 자주 언급된다. 엘리야 이야기에서 중요한 대적자로 등장한다.",
    "noah": "노아는 세상이 악해졌을 때 하나님께 순종해 방주를 지은 인물이다. 홍수 심판 가운데 가족과 함께 보존되었다.",
    "adam": "아담은 하나님이 지으신 첫 사람이다. 하와와 함께 에덴동산 이야기의 중심에 선다.",
    "eve": "하와는 하나님이 아담과 함께 살도록 주신 첫 여자이다. 에덴동산에서 뱀의 유혹을 받은 인물로 등장한다.",
    "peter": "베드로는 예수님의 열두 제자 중 대표적인 인물로, 원래 갈릴리의 어부였다. 복음서와 초대교회에서 담대하게 복음을 전한다.",
    "andrew": "안드레는 베드로의 형제이자 예수님의 제자였다. 먼저 예수님을 따르고 다른 사람을 데려오는 역할로 기억된다.",
    "john": "요한은 예수님의 열두 제자 중 한 사람이다. 예수님의 사랑을 깊이 전했고 요한복음 전승과도 연결된다.",
    "philip": "빌립은 예수님의 제자 중 한 사람으로, 사람들을 예수님께 인도하는 모습으로 자주 등장한다.",
    "bartholomew": "바돌로매는 예수님의 열두 제자 중 한 사람이다. 전승에서는 나다나엘과 연결해 보기도 한다.",
    "matthew": "마태는 세리 출신으로 예수님의 부르심을 받고 제자가 되었다. 전승에서는 마태복음과 연결된다.",
    "thomas": "도마는 예수님의 제자로, 부활하신 예수님을 확인하려 했던 모습으로 잘 알려져 있다. 이후에는 분명한 믿음의 고백을 남긴다.",
    "james": "야고보는 예수님의 제자 가운데 한 사람으로, 초대교회에서도 중요한 인물로 전해진다.",
    "james_zebedee": "야고보(세베대의 아들)는 요한의 형제이자 예수님의 제자였다. 열정적인 제자 가운데 하나로 기억된다.",
    "james_alphaeus": "야고보(알패오의 아들)는 예수님의 열두 제자 중 한 사람이다. 복음서에서는 조용하지만 끝까지 함께한 제자로 전해진다.",
    "simon_zealot": "시몬(셀롯)은 예수님의 열두 제자 중 한 사람이다. 이름에서 열심당과 관련된 배경을 짐작하게 한다.",
    "thaddaeus": "다대오(유다)는 예수님의 열두 제자 중 한 사람이다. 복음서에서는 유다라는 이름으로도 불린다.",
    "judas": "가룟 유다는 예수님의 열두 제자 중 한 사람이었지만, 예수님을 넘겨준 인물로 기억된다.",
    "paul": "바울은 예수님을 만난 뒤 복음을 널리 전한 사도다. 여러 도시를 다니며 교회를 세우고 서신을 남겼다.",
    "barnabas": "바나바는 초대교회에서 바울을 도와 선교에 함께한 동역자다. 사람을 격려하고 세우는 인물로 알려져 있다.",
    "silas": "실라는 바울과 함께 여러 지역을 다니며 복음을 전한 초대교회 지도자다.",
    "timothy": "디모데는 바울의 젊은 동역자로, 여러 교회를 돌보며 신앙을 이어 간 인물이다.",
    "matthias": "맛디아는 가룟 유다 대신 사도의 자리를 잇도록 뽑힌 인물이다.",
    "ananias": "아나니아는 초대교회에서 헌금 문제로 거짓말한 인물이다. 아내 삽비라와 함께 경고의 사례로 등장한다.",
    "ruth": "룻은 모압 여인이었지만 나오미를 따라 이스라엘로 와 믿음의 길을 택했다. 보아스와의 결혼을 통해 다윗의 계보에 들어간다.",
    "naomi": "나오미는 룻의 시어머니로, 깊은 상실 속에서도 하나님의 돌보심을 다시 경험한다.",
    "boaz": "보아스는 룻을 선대하고 보호한 친족 기업 무를 자이다. 룻과 결혼해 다윗 가문의 조상이 된다.",
    "elizabeth": "엘리사벳은 세례 요한의 어머니이며, 제사장 사가랴의 아내이다. 늙은 나이에 아들을 낳는 은혜를 받았다.",
}

PERSON_TAGLINE_OVERRIDES = {
    # Core primeval / patriarch stories
    "adam": "첫 사람",
    "eve": "첫 여자",
    "cain": "아담의 아들",
    "abel": "아담의 아들",
    "noah": "방주로 구원받은 의인",
    "abraham": "믿음의 조상",
    "sarah": "약속의 어머니",
    "lot": "소돔에서 건짐받은 조카",
    "hagar": "이스마엘의 어머니",
    "ishmael": "아브라함의 아들",
    "isaac": "약속의 아들",
    "rebekah": "이삭의 아내",
    "esau": "야곱의 형",
    "jacob": "이스라엘의 조상",
    "laban": "야곱의 외삼촌",
    "leah": "야곱의 아내",
    "rachel": "야곱의 아내",
    "joseph": "꿈으로 이집트를 살린 총리",
    "reuben": "야곱의 맏아들",
    "simeon": "야곱의 아들",
    "levi": "레위 지파의 조상",
    "judah": "유다 지파의 조상",
    "gad": "이스라엘 지파의 조상",
    "asher": "이스라엘 지파의 조상",
    "issachar": "이스라엘 지파의 조상",
    "zebulun": "이스라엘 지파의 조상",
    "naphtali": "이스라엘 지파의 조상",
    "benjamin": "야곱의 막내아들",
    "dinah": "야곱의 딸",
    # Exodus / conquest
    "pharaoh": "출애굽을 막은 이집트 왕",
    "moses": "출애굽의 지도자",
    "aaron": "이스라엘의 첫 대제사장",
    "miriam": "출애굽의 여선지자",
    "caleb": "믿음의 정탐꾼",
    "joshua": "가나안 정복 지도자",
    "achan": "아이 성 패배의 죄인",
    # Judges
    "othniel": "갈렙 집안 첫 승리 사사",
    "ehud": "에글론을 쓰러뜨린 왼손 사사",
    "shamgar": "블레셋을 막은 막대기 사사",
    "deborah": "바락과 승리한 여사사",
    "gideon": "300명으로 미디안 이긴 사사",
    "abimelech": "세겜에서 스스로 왕 된 자",
    "tola": "아비멜렉 뒤 평화 사사",
    "jair": "길르앗을 다스린 사사",
    "jephthah": "암몬과 싸운 서원 사사",
    "ibzan": "베들레헴의 가문 사사",
    "elon": "스불론의 평화 사사",
    "abdon": "비라돈의 많은 자손 사사",
    "samson": "들릴라에게 무너진 힘의 사사",
    "delilah": "삼손을 속인 여인",
    "ruth": "모압 출신 믿음의 여인",
    "naomi": "룻의 시어머니",
    "boaz": "룻을 보호한 기업 무를 자",
    "eli": "실로의 제사장",
    "hannah": "사무엘의 어머니",
    "samuel": "사울과 다윗을 세운 선지자",
    # United monarchy
    "saul": "불순종한 초대 왕",
    "jonathan": "사울의 아들",
    "jesse": "다윗의 아버지",
    "david": "언약을 받은 왕",
    "goliath": "블레셋 장수",
    "nathan": "다윗을 책망한 선지자",
    "bathsheba": "솔로몬의 어머니",
    "absalom": "다윗의 반역한 아들",
    "solomon": "성전을 세운 지혜 왕",
    # Divided kingdom kings: Northern Israel
    "jeroboam": "북이스라엘 1대 왕 금송아지 죄",
    "nadab": "북이스라엘 2대 왕 짧은 통치",
    "baasha": "북이스라엘 3대 왕 나답을 친 왕",
    "elah_king": "북이스라엘 4대 왕 술자리 몰락",
    "zimri": "북이스라엘 5대 왕 7일 왕",
    "omri": "북이스라엘 6대 왕 사마리아 건설",
    "ahab": "북이스라엘 7대 왕 바알 숭배",
    "jezebel": "아합을 부추긴 시돈 왕비",
    "ahaziah_israel": "북이스라엘 8대 왕 우상 의지",
    "joram_israel": "북이스라엘 9대 왕 예후에게 몰락",
    "jehu": "북이스라엘 10대 왕 아합 집 심판",
    "jehoahaz_israel": "북이스라엘 11대 왕 아람 압박",
    "jehoash_israel": "북이스라엘 12대 왕 엘리사 문병",
    "jeroboam_ii": "북이스라엘 13대 왕 영토 회복",
    "zechariah_king": "북이스라엘 14대 왕 예후 왕조 끝",
    "shallum": "북이스라엘 15대 왕 한 달 왕",
    "menahem": "북이스라엘 16대 왕 앗수르 조공",
    "pekahiah": "북이스라엘 17대 왕 반역에 몰락",
    "pekah": "북이스라엘 18대 왕 아람 동맹",
    "hoshea_king": "북이스라엘 19대 마지막 왕",
    # Divided kingdom kings: Judah
    "rehoboam": "남유다 1대 왕 왕국 분열",
    "abijah_judah": "남유다 2대 왕 북왕국 전쟁",
    "asa": "남유다 3대 왕 우상 개혁",
    "jehoshaphat": "남유다 4대 왕 말씀 개혁",
    "jehoram_judah": "남유다 5대 왕 악한 길",
    "ahaziah_judah": "남유다 6대 왕 아합 집 동맹",
    "athaliah": "남유다 7대 여왕 왕손 학살",
    "joash_judah": "남유다 8대 왕 성전 보수",
    "amaziah_judah": "남유다 9대 왕 에돔 승리",
    "uzziah": "남유다 10대 왕 강한 나라",
    "jotham": "남유다 11대 왕 성문 건축",
    "ahaz": "남유다 12대 왕 앗수르 의지",
    "hezekiah": "남유다 13대 왕 기도와 개혁",
    "manasseh": "남유다 14대 왕 깊은 타락",
    "amon_judah": "남유다 15대 왕 우상 숭배",
    "josiah": "남유다 16대 왕 율법 개혁",
    "jehoahaz_judah": "남유다 17대 왕 석 달 왕",
    "jehoiakim": "남유다 18대 왕 두루마리 불태움",
    "jehoiachin": "남유다 19대 왕 포로 왕",
    "zedekiah": "남유다 20대 마지막 왕",
    # Prophets / exile / return
    "elijah": "아합과 맞선 불 선지자",
    "elisha": "엘리야를 이은 기적 선지자",
    "ahijah": "여로보암에게 경고한 실로 선지자",
    "jonah": "니느웨에 보낸 회개 선지자",
    "micaiah": "아합 앞 진실 선지자",
    "jehoiada": "요아스를 보호한 성전 제사장",
    "isaiah": "히스기야를 도운 예루살렘 선지자",
    "jeremiah": "시드기야에게 경고한 눈물 선지자",
    "ezekiel": "포로 백성에게 환상 보인 선지자",
    "daniel": "포로기 궁정 인물",
    "haggai": "스룹바벨을 격려한 성전 선지자",
    "zechariah_prophet": "스룹바벨 시대 환상 선지자",
    "zerubbabel": "성전 재건 총독",
    "cyrus": "귀환을 허락한 페르시아 왕",
    "ezra": "율법을 가르친 학자",
    "nehemiah": "예루살렘 성벽 재건자",
    "esther": "페르시아 왕후",
    "mordecai": "에스더의 조언자",
    "haman": "유다인을 대적한 고관",
    # Gospels
    "jesus": "하나님의 아들",
    "mary": "예수님의 어머니",
    "joseph_nazareth": "예수님의 양아버지",
    "john_the_baptist": "광야의 세례자",
    "elizabeth": "세례 요한의 어머니",
    "zechariah": "세례 요한의 아버지",
    "gabriel": "하나님의 소식을 전한 천사",
    "peter": "예수님의 열두 제자",
    "andrew": "예수님의 열두 제자",
    "james_zebedee": "예수님의 열두 제자",
    "john": "예수님의 열두 제자",
    "philip": "예수님의 열두 제자",
    "bartholomew": "예수님의 열두 제자",
    "matthew": "예수님의 열두 제자",
    "thomas": "예수님의 열두 제자",
    "james_alphaeus": "예수님의 열두 제자",
    "thaddaeus": "예수님의 열두 제자",
    "simon_zealot": "예수님의 열두 제자",
    "judas": "예수님을 배신한 제자",
    "mary_magdalene": "예수님을 따른 여인",
    "martha": "베다니의 마르다",
    "lazarus": "예수님이 살리신 친구",
    "jairus": "회당장 야이로",
    "herod": "유대 지역 왕",
    "pilate": "로마 총독",
    # Early church
    "stephen": "초대교회 첫 순교자",
    "paul": "이방인을 위한 사도",
    "barnabas": "초대교회 선교 동역자",
    "silas": "바울의 선교 동역자",
    "timothy": "바울의 젊은 동역자",
    "john_mark": "초대교회 동역자",
    "matthias": "새로 세워진 사도",
    "ananias": "초대교회 경고의 인물",
    "sapphira": "초대교회 경고의 인물",
    "cornelius": "복음을 들은 로마 백부장",
    "lydia": "빌립보의 신자",
    "aquila": "바울의 동역자",
    "priscilla": "바울의 동역자",
    "agrippa": "바울을 심문한 왕",
    "festus": "로마 총독",
    "naaman": "아람 군대 장관",
}

ROLE_PHRASE_TO_KO = {
    "calm teacher-and-healer silhouette": "차분한 치유자이자 스승",
    "quiet contemplative disciple silhouette": "조용하고 묵상적인 제자",
    "fisherman-apostle turned reflective writer": "어부 출신이며 기록자 성향의 사도",
    "young fisherman-apostle turned reflective writer silhouette": "젊은 어부 출신이며 기록자 성향의 사도",
    "dream-marked survivor silhouette": "꿈과 시련을 지나온 인물",
    "graceful first-woman silhouette": "부드럽고 여성적인 첫 여인",
    "humble courageous mother silhouette": "겸손하면서도 담대한 어머니",
    "liberator silhouette shaped by wilderness": "광야가 만든 해방의 지도자",
    "road-worn missionary silhouette": "길 위를 걷는 선교사",
    "first king silhouette": "이스라엘의 첫 왕",
    "sturdy fisherman-apostle silhouette": "든든한 어부 사도",
    "fisherman-apostle silhouette with rope-belt layers": "어부 출신 사도",
    "rope-belt fisherman-apostle silhouette": "밧줄 띠를 두른 어부 사도",
    "boat-working fisherman-apostle silhouette": "배에서 일하던 어부 사도",
    "travel-guide disciple silhouette": "길 안내자 같은 제자",
    "road-guide messenger disciple silhouette": "길을 안내하고 소식을 전하는 제자",
    "scripture-student disciple silhouette": "말씀을 가까이한 제자",
    "scripture scholar disciple silhouette": "말씀을 익힌 학자형 제자",
    "tax-collector disciple silhouette": "세리 출신 제자",
    "tax-collector record-keeper disciple silhouette": "세리 출신의 기록자 제자",
    "craftsman-like disciple silhouette": "장인 같은 제자",
    "builder-craftsman disciple silhouette": "건축과 손일에 익숙한 장인형 제자",
    "village-workman disciple silhouette": "마을의 일꾼 같은 제자",
    "village artisan disciple silhouette": "마을에서 손일하던 장인형 제자",
    "messenger-disciple silhouette": "전갈을 전하는 제자",
    "courier-messenger disciple silhouette": "소식을 들고 다니는 전달자형 제자",
    "zealot-organizer disciple silhouette": "열심당 계열의 조직가 같은 제자",
    "zealot organizer disciple silhouette": "열심당 계열의 조직가형 제자",
    "purse-keeping treasurer disciple silhouette": "돈주머니를 맡은 재정 담당 제자",
    "treasurer disciple silhouette": "재정을 맡은 제자",
    "shepherd-king silhouette": "목자이자 왕",
    "nomadic patriarch silhouette": "유목하는 족장",
    "ceremonial leader silhouette": "예식을 이끄는 지도자",
    "court-wise exile silhouette": "지혜로운 포로기 궁정 인물",
    "storm-like prophet silhouette": "강렬한 예언자",
    "courageous queenly silhouette": "용기 있는 왕비",
    "scribe-teacher silhouette": "말씀을 가르치는 학자형 인물",
    "wall-rebuilder silhouette": "성벽을 다시 세우는 재건 지도자",
    "ark-builder silhouette": "방주를 짓는 생존자",
    "loyal field-worker silhouette": "들판에서 성실하게 일하는 인물",
    "listening prophet silhouette": "귀 기울여 듣는 예언자",
    "wise royal silhouette": "지혜로운 왕",
    "simple faceted form of light in the same blocky low-poly biblical illustration style as the cast": "다른 인물들과 같은 그림체의 단순한 빛 형태",
    "fisherman-apostle silhouette with rope-belt layers": "어부 출신 사도",
    "weathered desert-leader silhouette": "광야를 견딘 지도자",
    "regal angular silhouette": "왕실 분위기의 인물",
    "prophetic visionary silhouette": "환상을 보는 예언자",
    "ceremonial temple-robe silhouette": "성전 예복의 인물",
    "sturdy rebuilder silhouette": "재건자",
    "road-worn traveler silhouette": "길 위를 걷는 나그네",
    "protective caregiver silhouette": "돌보고 보호하는 인물",
    "bold warrior silhouette": "전사 같은 인물",
    "mythic early-world silhouette": "태초 시대 인물",
    "mission-era silhouette": "선교 시대 인물",
    "structured royal-era silhouette": "왕정 시대 인물",
    "simple faceted form of light in the same blocky low-poly biblical illustration style as the cast": "다른 인물들과 같은 그림체의 단순한 빛 형태",
}

DETAIL_PHRASE_TO_KO = {
    "deep red outer robe over a light inner tunic": "붉은 겉도포를 걸친 모습",
    "both arms gently opened outward in a welcoming gesture": "두 팔을 부드럽게 벌린 환영 자세",
    "rolled scroll or letter satchel": "두루마리나 서신 가방",
    "rolled scroll accent": "두루마리 소품",
    "small net bundle and rolled scroll satchel": "작은 그물 묶음과 두루마리 가방",
    "weathered fisherman's sash": "어부 느낌의 허리띠",
    "shoulder-draped fishing net and rope details": "어깨에 걸친 그물과 밧줄 소품",
    "hand net and rope-belt details": "손그물과 밧줄 허리띠",
    "coiled rope and oar accent": "감긴 밧줄과 노 소품",
    "coiled rope, short oar, and fish basket": "감긴 밧줄, 짧은 노, 물고기 바구니",
    "messenger satchel": "메신저 가방",
    "travel satchel and route scroll": "여행 가방과 길 안내 두루마리",
    "scroll bundle held like a student": "학생처럼 든 두루마리 묶음",
    "coin pouch and writing tablet": "동전 주머니와 기록판",
    "coin pouch, wax tablet, and stylus": "동전 주머니, 기록판, 필기용 펜",
    "measuring cord or tool pouch": "측량 끈이나 도구 주머니",
    "measuring cord and carpenter tool pouch": "측량 끈과 목공 도구 주머니",
    "simple work sash": "소박한 작업용 띠",
    "simple work sash and cloth tool wrap": "소박한 작업 띠와 천 도구 보따리",
    "letter satchel": "편지 가방",
    "letter satchel with a sealed scroll": "봉인된 두루마리가 든 편지 가방",
    "belted travel cloak": "띠를 맨 여행용 망토",
    "belted travel cloak with gathered folds": "띠를 맨 여행 망토와 겹주름",
    "money pouch at the belt": "허리의 돈주머니",
    "money pouch and small account bag": "돈주머니와 작은 회계 가방",
    "wooden staff": "지팡이",
    "sling and small stone pouch": "물매와 돌주머니",
    "simple geometric crown band or royal sash": "왕관 띠나 왕실 띠",
    "net weights and rope details": "그물과 밧줄 소품",
    "patterned robe accent": "무늬 있는 옷",
    "layered travel veil": "겹겹이 내려오는 베일",
    "builder's belt with wooden tools": "건축 도구 허리띠",
    "gathered grain bundle accent": "곡식 다발 소품",
    "priestly layered sash": "제사장 띠",
    "travel-worn layered robe": "나그네 같은 겹옷",
    "rough mantle energy": "거친 예언자 망토",
    "slender graceful build": "가늘고 우아한 실루엣",
    "soft delicate face with gentle feminine features": "섬세하고 온화한 얼굴",
    "long flowing hair with soft faceted strands": "길고 부드럽게 흐르는 머리",
    "one centered light form only": "하나의 중심 빛 형태",
    "simple vertical tapered silhouette made of a few large geometric planes": "몇 개의 큰 면으로 이루어진 단순한 세로형 빛 실루엣",
}

MOOD_PHRASE_TO_KO = {
    "warm gentle expression": "온화한 표정",
    "gentle relaxed posture": "편안하고 부드러운 자세",
    "brave forward-leaning stance": "앞으로 나아가는 자세",
    "open-handed compassionate posture": "품어 주듯 손을 펴는 자세",
    "thoughtful calm expression": "차분하고 생각에 잠긴 표정",
    "quiet witness-like presence": "조용히 지켜보는 증인의 분위기",
    "light celebratory posture": "가볍게 기뻐하는 자세",
    "resolute steady posture": "차분하고 단단한 자세",
    "calm dignified bearing": "차분하고 품위 있는 분위기",
    "measured studious bearing": "신중하고 학구적인 분위기",
    "gentle visionary bearing": "온화하면서도 환상을 보는 듯한 분위기",
    "protected-yet-resilient bearing": "보호받으면서도 버텨 온 분위기",
    "calm grounded presence": "차분하고 안정된 분위기",
    "steady leader's presence": "흔들림 없는 지도자 분위기",
    "focused civic resolve": "집중된 재건 의지",
    "weathered survivor presence": "세월을 견딘 생존자의 분위기",
    "intense teacher's focus": "집중력 있는 스승의 분위기",
    "tall commanding presence": "키가 크고 위엄 있는 분위기",
    "broad dependable presence": "든든하고 믿음직한 분위기",
    "weathered fisherman's focus": "현장감 있는 어부의 집중력",
    "bold energetic worker's presence": "힘 있고 활동적인 일꾼의 분위기",
    "practical alert presence": "실무형이고 민첩한 분위기",
    "humble resilient bearing": "겸손하면서도 단단한 분위기",
    "quiet spiritual alertness": "조용히 깨어 있는 영적 분위기",
    "measured thoughtful presence": "차분하게 생각하는 분위기",
    "precise record-keeper presence": "꼼꼼히 기록하는 분위기",
    "solid thoughtful presence": "묵직하고 신중한 분위기",
    "quiet steady presence": "조용하고 안정된 분위기",
    "warm approachable presence": "따뜻하고 다가가기 쉬운 분위기",
    "lean vigilant presence": "날렵하고 경계하는 분위기",
    "guarded calculating presence": "조심스럽고 계산적인 분위기",
    "measured judicial calm": "판단력 있는 차분함",
    "minimal clean composition": "단정하고 깔끔한 구성",
    "gentle warm glow": "부드럽고 따뜻한 빛의 분위기",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build SQL for characters and person_eras from character meta JSON."
    )
    parser.add_argument(
        "--character-meta-json",
        default="tools/seed/character_meta.json",
        help="Character meta JSON path (code, name, is_active_default, avatar prompt, etc.).",
    )
    parser.add_argument(
        "--stories-dir",
        default="assets/200_stories",
        help="Directory containing story JSON files.",
    )
    parser.add_argument(
        "--output",
        default="supabase/200_stories/characters_seed.sql",
        help="Output SQL path.",
    )
    return parser.parse_args()


def parse_event_number(raw_title: str) -> int:
    """제목 앞 3자리 번호 → int. 신 포맷(번호 없음) 은 0 반환."""
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
            raise ValueError(f"JSON root must be list: {path}")
        for item in data:
            if not isinstance(item, dict):
                raise ValueError(f"Story row must be object in {path}: {item!r}")
            rows.append(item)
    # title 에 번호가 없으면 0 → story_index 를 보조 키로.
    rows.sort(
        key=lambda row: (
            int(row["story_index"]) if isinstance(row.get("story_index"), int) else 0,
            str(row.get("title", "")),
        )
    )
    return rows


def dedupe_preserve_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        ordered.append(item)
    return ordered


def story_era_codes_for_character(appearances: list[dict[str, Any]]) -> list[str]:
    """Return era codes where the character actually appears in story data."""
    seen = {
        str(row.get("era", "")).strip()
        for row in appearances
        if str(row.get("era", "")).strip()
    }
    ordered = [era for era in ERA_ORDER if era in seen]
    ordered.extend(sorted(seen - set(ordered)))
    return ordered


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


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def sql_value(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return sql_literal(str(value))


def sql_text_array(values: list[str]) -> str:
    if not values:
        return "ARRAY[]::text[]"
    inner = ", ".join(sql_literal(v) for v in values)
    return f"ARRAY[{inner}]::text[]"


def split_chunks(items: list[Any], size: int) -> list[list[Any]]:
    return [items[i : i + size] for i in range(0, len(items), size)]


def build_final_avatar_prompt(
    raw_prompt: str,
    common_style: str,
    *,
    include_adult_guardrail: bool = True,
    use_common_style: bool = True,
) -> str:
    prompt = raw_prompt.strip()
    if use_common_style and common_style:
        if "COMMON_STYLE" in prompt:
            prompt = prompt.replace("COMMON_STYLE", common_style).strip()
        elif not prompt.startswith(common_style):
            prompt = f"{common_style}, {prompt}"
    else:
        prompt = prompt.replace("COMMON_STYLE", "").strip()

    prompt = ", ".join(part.strip() for part in prompt.split(",") if part.strip())

    if not include_adult_guardrail:
        return prompt

    lower = prompt.lower()
    if "no children" in lower or "no minors" in lower or "age 25+" in lower:
        return prompt
    return f"{prompt}, {ADULT_GUARDRAIL}"


def choose_topic_particle(text: str) -> str:
    if not text:
        return "는"
    last = text[-1]
    if not ("가" <= last <= "힣"):
        return "는"
    return "은" if (ord(last) - ord("가")) % 28 else "는"


def choose_and_particle(text: str) -> str:
    if not text:
        return "와"
    last = text[-1]
    if not ("가" <= last <= "힣"):
        return "와"
    return "과" if (ord(last) - ord("가")) % 28 else "와"


def join_ko_phrases(items: list[str]) -> str:
    if not items:
        return ""
    if len(items) == 1:
        return items[0]
    if len(items) == 2:
        return f"{items[0]}{choose_and_particle(items[0])} {items[1]}"
    return ", ".join(items[:-1]) + f", {items[-1]}"


def extract_prompt_matches(
    prompt: str, mapping: dict[str, str], *, limit: int
) -> list[str]:
    found: list[str] = []
    matched_phrases: list[str] = []
    lower = prompt.lower()
    items = sorted(mapping.items(), key=lambda item: (-len(item[0]), item[0]))
    for phrase, ko_text in items:
        phrase_lower = phrase.lower()
        if phrase_lower not in lower:
            continue
        if any(phrase_lower in matched for matched in matched_phrases):
            continue
        if ko_text in found:
            continue
        matched_phrases.append(phrase_lower)
        found.append(ko_text)
        if len(found) >= limit:
            break
    return found


def pick_representative_story_title(
    code: str,
    character: dict[str, Any],
    story_appearances_by_code: dict[str, list[dict[str, Any]]],
) -> str:
    appearances = story_appearances_by_code.get(code, [])
    if not appearances:
        return ""

    target_era_code = STYLE_TO_ERA_CODE.get(str(character.get("era", "")).strip(), "")
    if target_era_code:
        for row in appearances:
            if str(row.get("era", "")).strip() == target_era_code:
                return str(row.get("title", "")).strip()

    return str(appearances[0].get("title", "")).strip()


def build_person_description(
    code: str,
    name: str,
    representative_story_title: str,
) -> str:
    override = PERSON_DESCRIPTION_OVERRIDES.get(code)
    if override:
        return override

    topic = choose_topic_particle(name)
    if representative_story_title:
        story_title = representative_story_title
        story_title = re.sub(r"^\d{3}\s+", "", story_title).strip()
        return f"{name}{topic} 성경에 등장하는 인물로, 대표적으로 '{story_title}' 이야기와 연결된다."

    return f"{name}{topic} 성경에 등장하는 인물이다."


def build_person_tagline(
    code: str,
    name: str,
    character: dict[str, Any],
) -> str:
    override = PERSON_TAGLINE_OVERRIDES.get(code)
    if override:
        return override

    name_en = str(character.get("name_en", "")).strip().lower()
    if "king of northern israel" in name_en or "king of israel" in name_en:
        return "북이스라엘 왕"
    if "queen of judah" in name_en:
        return "남유다 여왕"
    if "king of judah" in name_en:
        return "남유다 왕"
    if "king" in name_en:
        return "왕"
    if "prophet" in name_en:
        return "선지자"
    if code in DISCIPLES_WITH_JUDAS:
        return "예수님의 열두 제자"

    era_short = str(character.get("era", "")).strip()
    return {
        "primeval": "원역사 인물",
        "patriarch": "족장 시대 인물",
        "exodus_wilderness": "출애굽 시대 인물",
        "judges": "사사 시대 인물",
        "monarchy": "왕정 시대 인물",
        "divided_kingdom": "분열왕국 시대 인물",
        "prophets_exile": "예언자와 포로기 인물",
        "post_exile_return": "포로 귀환 시대 인물",
        "gospels": "복음서 인물",
        "early_church": "초대교회 인물",
    }.get(era_short, f"{name} 관련 인물")


def build_sql(character_rows: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    lines.append("-- Generated by tools/seed/build_characters_seed_sql.py")
    lines.append("-- Target table: characters (person_eras is a view; see db_init.sql)")
    lines.append("begin;")
    lines.append("")

    if ROSTER_EXCLUDED_CODES:
        for chunk in split_chunks(sorted(ROSTER_EXCLUDED_CODES), 120):
            in_values = ", ".join(sql_value(code) for code in chunk)
            lines.append("-- Remove explicitly excluded roster codes")
            lines.append(f"delete from characters where code in ({in_values});")
            lines.append("")

    # 현재 character_meta.json 에 없는 characters 행 삭제. user 가 stories 를
    # 지워서 언급 수 0이 된 인물이 DB 에 남지 않도록 정리.
    # weekly_character_selection 은 character_code 를 cascade 없이 참조하므로
    # FK 위반을 막기 위해 미리 같이 정리한다.
    if character_rows:
        keep_codes = sorted({row["code"] for row in character_rows})
        in_values = ", ".join(sql_value(code) for code in keep_codes)
        lines.append(
            "-- Drop weekly_character_selection rows whose character is being removed"
        )
        lines.append(
            f"delete from weekly_character_selection where character_code not in ({in_values});"
        )
        lines.append("-- Delete characters not in current character_meta.json")
        lines.append(f"delete from characters where code not in ({in_values});")
        lines.append("")

    columns = "code, name, tagline, avatar_url, description, is_active, era_codes"
    for chunk in split_chunks(character_rows, 120):
        lines.append(f"with seed_persons ({columns}) as (")
        lines.append("  values")
        values: list[str] = []
        for row in chunk:
            values.append(
                "    ("
                f"{sql_value(row['code'])}, "
                f"{sql_value(row['name'])}, "
                f"{sql_value(row['tagline'])}, "
                f"{sql_value(row['avatar_url'])}, "
                f"{sql_value(row['description'])}, "
                f"{sql_value(row['is_active'])}, "
                f"{sql_text_array(row.get('era_codes') or [])}"
                ")"
            )
        lines.append(",\n".join(values))
        lines.append(")")
        lines.append(f"insert into characters ({columns})")
        lines.append(f"select {columns} from seed_persons")
        lines.append("on conflict (code) do update set")
        lines.append("  name = excluded.name,")
        lines.append("  tagline = coalesce(excluded.tagline, characters.tagline),")
        lines.append("  avatar_url = excluded.avatar_url,")
        lines.append(
            "  description = coalesce(excluded.description, characters.description),"
        )
        # era_codes 는 파이프라인에서 결정한다 (인물 카드 노출 era).
        # admin override 가 필요하면 별도 마이그레이션으로 처리.
        lines.append("  era_codes = excluded.era_codes,")
        # Pipeline defaults may promote a character to visible, but false
        # defaults do not hide rows that were already enabled at runtime.
        lines.append("  is_active = case")
        if FORCE_INACTIVE_CODES:
            forced_inactive = ", ".join(
                sql_value(code) for code in sorted(FORCE_INACTIVE_CODES)
            )
            lines.append(f"    when excluded.code in ({forced_inactive}) then false")
        lines.append("    when excluded.is_active then true")
        lines.append("    else characters.is_active")
        lines.append("  end")
        lines.append(";")
        lines.append("")

    lines.append("commit;")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    meta_path = Path(args.character_meta_json)
    stories_dir = Path(args.stories_dir)
    output_path = Path(args.output)

    if not meta_path.exists():
        raise FileNotFoundError(f"Character meta JSON not found: {meta_path}")

    meta_data = json.loads(meta_path.read_text(encoding="utf-8"))
    characters = meta_data.get("characters")
    if not isinstance(characters, list):
        raise ValueError(f"Invalid character meta JSON format: {meta_path}")

    selected_codes: list[str] = []
    char_by_code: dict[str, dict[str, Any]] = {}
    for ch in characters:
        if not isinstance(ch, dict):
            continue
        code = str(ch.get("code", "")).strip()
        if not code:
            continue
        if code in ROSTER_EXCLUDED_CODES:
            continue
        if code in char_by_code:
            continue
        selected_codes.append(code)
        char_by_code[code] = ch

    selected_set = set(selected_codes)

    story_rows = load_story_rows(stories_dir)

    story_appearances_by_code: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in story_rows:
        number = parse_event_number(str(row.get("title", "")))
        if number == 0 and isinstance(row.get("story_index"), int):
            number = int(row["story_index"])
        raw_persons = [
            str(code).strip() for code in row.get("characters", []) if str(code).strip()
        ]
        characters = [
            code
            for code in expand_person_codes(number, raw_persons)
            if code in selected_set
        ]
        for code in characters:
            story_appearances_by_code[code].append(row)

    character_rows: list[dict[str, Any]] = []
    for code in selected_codes:
        ch = char_by_code[code]
        name = (
            str(ch.get("name_ko", "")).strip()
            or str(ch.get("name_en", "")).strip()
            or code
        )
        representative_story_title = pick_representative_story_title(
            code,
            ch,
            story_appearances_by_code,
        )
        era_codes = story_era_codes_for_character(
            story_appearances_by_code.get(code, [])
        )
        if not era_codes:
            era_short = str(ch.get("era", "")).strip()
            era_code = STYLE_TO_ERA_CODE.get(era_short, "")
            era_codes = [era_code] if era_code else []
        character_rows.append(
            {
                "code": code,
                "name": name,
                "tagline": str(ch.get("tagline", "")).strip()
                or build_person_tagline(code=code, name=name, character=ch),
                "avatar_url": f"assets/avatars/{code}.png",
                "description": build_person_description(
                    code=code,
                    name=name,
                    representative_story_title=representative_story_title,
                ),
                "is_active": bool(ch.get("is_active_default", True)),
                "era_codes": era_codes,
            }
        )

    sql_text = build_sql(character_rows=character_rows)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(sql_text, encoding="utf-8")

    active_count = sum(1 for row in character_rows if row["is_active"])
    print(f"character meta json   : {meta_path}")
    print(f"stories dir        : {stories_dir}")
    print(f"characters total      : {len(character_rows)}")
    print(f"characters is_active  : {active_count}")
    print(f"output             : {output_path}")
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
