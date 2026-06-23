#!/usr/bin/env python3
"""Build developer guide artifacts from current repository sources.

Outputs:
- docs/guides/story_guide.md from assets/200_stories/*.json
- docs/guides/html/*.html from docs/guides/*.md

The HTML renderer intentionally uses only the Python standard library. It is
not a full CommonMark implementation; it supports the Markdown structures used
by this repository's guide files and preserves unknown inline HTML as text.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]
GUIDES_DIR = ROOT / "docs" / "guides"
HTML_DIR = GUIDES_DIR / "html"
HTML_ASSET_DIR = HTML_DIR / "assets"
STORY_GUIDE = GUIDES_DIR / "story_guide.md"


@dataclass(frozen=True)
class EraMeta:
    code: str
    name: str
    testament: str
    order: int
    start_year: int | None
    end_year: int | None
    hidden_in_app: bool = False


@dataclass(frozen=True)
class GuideEntry:
    filename: str
    level: str


@dataclass(frozen=True)
class GuideGroup:
    label: str
    summary: str
    entries: tuple[GuideEntry, ...]


ERA_ORDER: tuple[EraMeta, ...] = (
    EraMeta("era_primeval", "원역사", "구약", 1, -4000, -2000),
    EraMeta("era_patriarch", "족장", "구약", 2, -2166, -1805),
    EraMeta("era_exodus", "출애굽", "구약", 3, -1446, -1406),
    EraMeta("era_judges", "사사", "구약", 4, -1406, -1050),
    EraMeta("era_monarchy", "통일 왕국", "구약", 5, -1050, -930),
    EraMeta("era_divided_kingdom", "분열왕국", "구약", 6, -930, -586),
    EraMeta("era_exile_return", "포로 및 포로 후기", "구약", 7, -586, -430),
    EraMeta("era_nt_public_ministry", "예수님의 공생애", "신약", 8, 27, 33),
    EraMeta("era_nt_apostolic", "사도", "신약", 9, 33, 70),
    EraMeta("era_nt_post_apostolic", "후기 사도", "신약", 10, 45, 100),
    EraMeta("era_nt_consummation", "역사의 종결", "신약", 11, None, None, True),
)

GUIDE_GROUPS: tuple[GuideGroup, ...] = (
    GuideGroup(
        "문서 지도",
        "전체 문서의 역할과 읽는 순서를 먼저 잡는 진입점",
        (GuideEntry("README.md", "main"),),
    ),
    GuideGroup(
        "개발/배포 Flow",
        "일상 개발, real 배포, 콘텐츠 반영, Make target 원리",
        (
            GuideEntry("develop-flow.md", "main"),
            GuideEntry("CONTENT_UPDATE.md", "sub"),
            GuideEntry("MAKE_TARGETS.md", "sub"),
        ),
    ),
    GuideGroup(
        "인프라 세팅/구축",
        "현재 Supabase/Firebase/GCP 구조와 새 환경 구축 절차",
        (
            GuideEntry("INFRA_GUIDE.md", "main"),
            GuideEntry("DB_SETUP.md", "sub"),
            GuideEntry("LOCAL_ENV_FILES.md", "sub"),
        ),
    ),
    GuideGroup(
        "기능 가이드",
        "앱 기능별 운영/설정 문서",
        (GuideEntry("PUSH_SETUP.md", "main"),),
    ),
    GuideGroup(
        "테스트 가이드",
        "변경 유형별 검증 범위와 현재 테스트 지도",
        (GuideEntry("TEST_GUIDE.md", "main"),),
    ),
    GuideGroup(
        "부록/참고",
        "메인 문서를 보조하는 긴 레퍼런스와 생성 카탈로그",
        (
            GuideEntry("WORKFLOW_GUIDE.md", "appendix"),
            GuideEntry("story_guide.md", "appendix"),
        ),
    ),
)

GUIDE_ORDER = tuple(entry.filename for group in GUIDE_GROUPS for entry in group.entries)

GUIDE_DESCRIPTIONS = {
    "README.md": ("문서 허브", "중복된 운영 문서의 역할과 읽는 순서를 묶은 진입점"),
    "develop-flow.md": ("개발/배포", "dev/real 실행, 검증, patch, real 배포 판단"),
    "CONTENT_UPDATE.md": ("콘텐츠 운영", "새 이야기, 퀴즈, 이미지, pubspec 반영 절차"),
    "MAKE_TARGETS.md": (
        "Make target",
        "각 make 명령의 입력, 출력, 원격 영향, 중간 삽입 주의점",
    ),
    "LOCAL_ENV_FILES.md": (
        "환경 파일",
        "git에 올리는 예제 파일과 별도 공유가 필요한 secret 구분",
    ),
    "DB_SETUP.md": ("구축 절차", "Supabase 신규/복구 환경의 Auth, secret, seed 세팅"),
    "INFRA_GUIDE.md": ("인프라", "Supabase, Firebase, GCP, Apple, OAuth 현재 구조"),
    "PUSH_SETUP.md": ("푸시 알림", "Firebase와 send-push를 처음 연결하는 체크리스트"),
    "TEST_GUIDE.md": ("테스트", "현재 테스트 파일과 검증 책임 카탈로그"),
    "WORKFLOW_GUIDE.md": ("레퍼런스", "Codex 작업 루프와 웹 제안 기능의 구조 참고"),
    "story_guide.md": ("카탈로그", "현재 JSON 기준 전체 사건, 인물, 장소, 본문"),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--story-guide-only", action="store_true")
    parser.add_argument("--html-only", action="store_true")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit non-zero if generated files differ from the working tree.",
    )
    return parser.parse_args()


def md_escape(value: object) -> str:
    text = str(value if value is not None else "").replace("\n", " ").strip()
    return text.replace("|", "\\|")


def anchor_slug(text: str) -> str:
    raw = text.strip().lower()
    raw = re.sub(r"<[^>]+>", "", raw)
    raw = re.sub(r"[`*_~\[\]().,:;!?\"'“”‘’/\\]+", " ", raw)
    raw = re.sub(r"\s+", "-", raw).strip("-")
    return raw or "section"


def era_anchor(code: str) -> str:
    return code.replace("_", "-")


def story_anchor(era_code: str, story_index: int) -> str:
    return f"{era_anchor(era_code)}-{story_index:03d}"


def format_year(year: int | None) -> str:
    if year is None:
        return "—"
    if year < 0:
        return f"B.C. {abs(year)}"
    return f"A.D. {year}"


def format_year_range(start: int | None, end: int | None) -> str:
    if start is None and end is None:
        return "—"
    if start == end or end is None:
        return f"{format_year(start)}경" if start is not None else "—"
    return f"{format_year(start)} ~ {format_year(end)}경"


def format_refs(refs: object) -> str:
    if not isinstance(refs, list) or not refs:
        return "—"
    parts: list[str] = []
    for ref in refs:
        if not isinstance(ref, dict):
            continue
        book = str(ref.get("book") or "").strip()
        start = str(ref.get("from") or "").strip()
        end = str(ref.get("to") or "").strip()
        if not book or not start:
            continue
        if end and end != start:
            parts.append(f"{book} {start}~{end}")
        else:
            parts.append(f"{book} {start}")
    return ", ".join(parts) if parts else "—"


def load_character_names() -> dict[str, str]:
    meta_path = ROOT / "tools" / "seed" / "character_meta.json"
    payload = json.loads(meta_path.read_text(encoding="utf-8"))
    names: dict[str, str] = {}
    for item in payload.get("characters", []):
        if not isinstance(item, dict):
            continue
        code = str(item.get("code") or "").strip()
        name = str(item.get("name_ko") or item.get("name_en") or code).strip()
        if code:
            names[code] = name
    return names


def load_event_mapping() -> dict[tuple[str, int], dict]:
    path = ROOT / "assets" / "landmarks" / "event_region_mapping.json"
    if not path.exists():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    rows = payload.get("rows", [])
    result: dict[tuple[str, int], dict] = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        era = str(row.get("era") or "")
        try:
            index = int(row.get("story_index"))
        except (TypeError, ValueError):
            continue
        result[(era, index)] = row
    return result


def load_stories_by_era() -> dict[str, list[dict]]:
    result: dict[str, list[dict]] = {}
    for path in sorted((ROOT / "assets" / "200_stories").glob("*.json")):
        events = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(events, list):
            raise ValueError(f"{path} must contain a JSON list")
        for event in events:
            if not isinstance(event, dict):
                raise ValueError(f"{path} contains a non-object event")
            era = str(event.get("era") or path.stem)
            result.setdefault(era, []).append(event)
    for events in result.values():
        events.sort(key=lambda item: int(item.get("story_index") or 0))
    return result


def names_for_codes(codes: object, name_map: dict[str, str]) -> str:
    if not isinstance(codes, list) or not codes:
        return "—"
    return ", ".join(name_map.get(str(code), str(code)) for code in codes)


def build_story_guide_text() -> str:
    stories_by_era = load_stories_by_era()
    name_map = load_character_names()
    mapping = load_event_mapping()
    total_events = sum(len(stories_by_era.get(era.code, [])) for era in ERA_ORDER)
    total_eras = sum(1 for era in ERA_ORDER if stories_by_era.get(era.code))
    hidden_count = len(stories_by_era.get("era_nt_consummation", []))

    lines: list[str] = [
        "# 이야기 가이드 (Story Guide)",
        "",
        "> 현재 `assets/200_stories/*.json` 기준으로 자동 생성한 검수용 카탈로그다.",
        "> 사건 제목, 시대, 등장 인물, 위치 매핑, 성경 본문, 장면 구성이 UI와 맞는지 확인할 때 쓴다.",
        "",
        f"**총 사건 수**: {total_events}개  ·  **시대 수**: {total_eras}개",
        "",
        "> 자동 생성 소스: `assets/200_stories/*.json`, `assets/landmarks/event_region_mapping.json`, `tools/seed/character_meta.json`.",
        "> 데이터 변경 후 `make build-guides`를 실행해 이 문서와 HTML 가이드를 함께 갱신한다.",
        "",
    ]
    if hidden_count:
        lines.extend(
            [
                f"> 참고: `era_nt_consummation` {hidden_count}개 사건은 현재 앱에서 숨김 era로 취급된다.",
                "",
            ]
        )

    lines.extend(["## 목차", ""])
    for era in ERA_ORDER:
        events = stories_by_era.get(era.code, [])
        if not events:
            continue
        hidden_note = " · 앱 숨김" if era.hidden_in_app else ""
        lines.append(
            f"- [{era.name} ({len(events)}개)](#{era_anchor(era.code)}) — "
            f"{era.testament}, {format_year_range(era.start_year, era.end_year)}{hidden_note}"
        )
    lines.append("")

    for era in ERA_ORDER:
        events = stories_by_era.get(era.code, [])
        if not events:
            continue
        lines.extend(
            [
                "---",
                "",
                f'<a id="{era_anchor(era.code)}"></a>',
                f"## {era.name}",
                "",
                f"- **시대 코드**: `{era.code}`",
                f"- **언약**: {era.testament}",
                f"- **추정 연대**: {format_year_range(era.start_year, era.end_year)}",
                f"- **사건 수**: {len(events)}",
            ]
        )
        if era.hidden_in_app:
            lines.append("- **앱 노출**: `hiddenEraCodes`로 숨김")
        lines.extend(
            [
                "",
                "| # | 제목 | 구간 | 인물 | 장소 | 연대 | 성경 |",
                "|---|------|------|------|------|------|------|",
            ]
        )
        for event in events:
            idx = int(event.get("story_index") or 0)
            title = str(event.get("title") or "").strip()
            unit = str(event.get("unit_title") or "전체 흐름").strip()
            people = names_for_codes(event.get("characters"), name_map)
            refs = format_refs(event.get("bible_ref") or event.get("bible_refs"))
            years = format_year_range(event.get("start_year"), event.get("end_year"))
            lines.append(
                "| "
                + " | ".join(
                    [
                        str(idx),
                        f"[{md_escape(title)}](#{story_anchor(era.code, idx)})",
                        md_escape(unit),
                        md_escape(people),
                        md_escape(event.get("place_name") or "—"),
                        md_escape(years),
                        md_escape(refs),
                    ]
                )
                + " |"
            )

        lines.extend(["", "### 사건별 상세", ""])
        for event in events:
            idx = int(event.get("story_index") or 0)
            title = str(event.get("title") or "").strip()
            key = (era.code, idx)
            row = mapping.get(key, {})
            refs = format_refs(event.get("bible_ref") or event.get("bible_refs"))
            people = names_for_codes(event.get("characters"), name_map)
            years = format_year_range(event.get("start_year"), event.get("end_year"))
            lat = event.get("lat")
            lng = event.get("lng")
            coord = f"{lat}, {lng}" if lat is not None and lng is not None else "—"
            landmark = row.get("landmark_code") or "—"
            region = row.get("region_code") or "—"

            lines.extend(
                [
                    f'<a id="{story_anchor(era.code, idx)}"></a>',
                    f"#### {idx}. {title}",
                    "",
                    f"- **구간**: {event.get('unit_title') or '전체 흐름'} (`{event.get('unit_code') or 'default'}`)",
                    f"- **인물**: {people}",
                    f"- **장소**: {event.get('place_name') or '—'} ({coord})",
                    f"- **랜드마크 매핑**: `{landmark}` / `{region}`",
                    f"- **연대**: {years} · `{event.get('time_precision') or 'approx'}`",
                    f"- **성경**: {refs}",
                    f"- **요약**: {event.get('summary') or '—'}",
                    f"- **배경 지식**: {event.get('background_context') or '—'}",
                    "",
                    "- **장면**:",
                ]
            )
            scenes = event.get("story_scenes") or []
            captions = event.get("scene_captions") or []
            scene_characters = event.get("scene_characters") or []
            for scene_index, scene in enumerate(scenes, start=1):
                chars = "—"
                if (
                    isinstance(scene_characters, list)
                    and len(scene_characters) >= scene_index
                ):
                    chars = names_for_codes(scene_characters[scene_index - 1], name_map)
                caption = ""
                if isinstance(captions, list) and len(captions) >= scene_index:
                    caption_text = str(captions[scene_index - 1]).strip()
                    if caption_text and caption_text != str(scene).strip():
                        caption = f" / 캡션: {caption_text}"
                lines.append(
                    f"  {scene_index}. ({chars}) {str(scene).strip()}{caption}"
                )
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def guide_files() -> list[Path]:
    files = {path.name: path for path in GUIDES_DIR.glob("*.md")}
    ordered = [files[name] for name in GUIDE_ORDER if name in files]
    remaining = sorted(path for name, path in files.items() if name not in GUIDE_ORDER)
    return ordered + remaining


def guide_groups() -> list[tuple[GuideGroup, list[tuple[GuideEntry, Path]]]]:
    files = {path.name: path for path in GUIDES_DIR.glob("*.md")}
    groups: list[tuple[GuideGroup, list[tuple[GuideEntry, Path]]]] = []
    for group in GUIDE_GROUPS:
        existing_entries: list[tuple[GuideEntry, Path]] = []
        for entry in group.entries:
            path = files.get(entry.filename)
            if path is not None:
                existing_entries.append((entry, path))
        if existing_entries:
            groups.append((group, existing_entries))
    return groups


def read_title(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return path.stem


def html_name_for_md(path: Path) -> str:
    if path.name == "README.md":
        return "readme.html"
    return path.stem.lower().replace("_", "-") + ".html"


def split_href_anchor(href: str) -> tuple[str, str]:
    if "#" not in href:
        return href, ""
    base, anchor = href.split("#", 1)
    return base, "#" + anchor


class MarkdownRenderer:
    def __init__(self, source: Path, guide_map: dict[Path, str]):
        self.source = source
        self.guide_map = guide_map
        self.toc: list[tuple[int, str, str]] = []
        self.slug_counts: dict[str, int] = {}

    def unique_slug(self, text: str) -> str:
        base = anchor_slug(text)
        count = self.slug_counts.get(base, 0)
        self.slug_counts[base] = count + 1
        if count:
            return f"{base}-{count + 1}"
        return base

    def resolve_href(self, href: str) -> str:
        if (
            href.startswith("#")
            or re.match(r"^[a-z][a-z0-9+.-]*:", href)
            or href.startswith("mailto:")
        ):
            return href
        base, anchor = split_href_anchor(href)
        if not base:
            return href
        target = (self.source.parent / unquote(base)).resolve()
        if base.lower().endswith(".md"):
            html_target = self.guide_map.get(target)
            if html_target:
                return html_target + anchor
        try:
            rel = os.path.relpath(target, HTML_DIR)
            return rel + anchor
        except ValueError:
            return href

    def inline(self, raw: str) -> str:
        placeholders: list[str] = []

        def stash(value: str) -> str:
            placeholders.append(value)
            return f"\u0000{len(placeholders) - 1}\u0000"

        def code_repl(match: re.Match[str]) -> str:
            return stash(f"<code>{html.escape(match.group(1))}</code>")

        def link_repl(match: re.Match[str]) -> str:
            label = html.escape(match.group(1))
            href = html.escape(self.resolve_href(match.group(2)), quote=True)
            return stash(f'<a href="{href}">{label}</a>')

        text = re.sub(r"`([^`]+)`", code_repl, raw)
        text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link_repl, text)
        escaped = html.escape(text)
        escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
        escaped = re.sub(r"__([^_]+)__", r"<strong>\1</strong>", escaped)
        escaped = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", escaped)
        for index, value in enumerate(placeholders):
            escaped = escaped.replace(f"\u0000{index}\u0000", value)
        return escaped

    def render_table(self, lines: list[str]) -> str:
        rows: list[list[str]] = []
        for line in lines:
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            rows.append(cells)
        if len(rows) < 2:
            return ""
        header = rows[0]
        body = rows[2:]
        out = ['<div class="table-wrap"><table>', "<thead><tr>"]
        out.extend(f"<th>{self.inline(cell)}</th>" for cell in header)
        out.append("</tr></thead><tbody>")
        for row in body:
            out.append("<tr>")
            out.extend(f"<td>{self.inline(cell)}</td>" for cell in row)
            out.append("</tr>")
        out.append("</tbody></table></div>")
        return "\n".join(out)

    def render(self, markdown: str) -> str:
        lines = markdown.splitlines()
        output: list[str] = []
        index = 0
        while index < len(lines):
            line = lines[index]
            stripped = line.strip()
            if not stripped:
                index += 1
                continue

            fence = re.match(r"^```(\w+)?\s*$", stripped)
            if fence:
                language = fence.group(1) or ""
                index += 1
                code_lines: list[str] = []
                while index < len(lines) and not lines[index].strip().startswith("```"):
                    code_lines.append(lines[index])
                    index += 1
                index += 1
                output.append(
                    f'<pre><code class="language-{html.escape(language)}">'
                    + html.escape("\n".join(code_lines))
                    + "</code></pre>"
                )
                continue

            if stripped.startswith("<a id=") or stripped in {"---", "<hr>"}:
                if stripped == "---":
                    output.append("<hr>")
                else:
                    output.append(stripped)
                index += 1
                continue

            heading = re.match(r"^(#{1,6})\s+(.+)$", line)
            if heading:
                level = len(heading.group(1))
                text = heading.group(2).strip()
                slug = self.unique_slug(text)
                if level <= 3:
                    self.toc.append((level, text, slug))
                output.append(f'<h{level} id="{slug}">{self.inline(text)}</h{level}>')
                index += 1
                continue

            if (
                stripped.startswith("|")
                and index + 1 < len(lines)
                and re.match(
                    r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$",
                    lines[index + 1],
                )
            ):
                table_lines = [line, lines[index + 1]]
                index += 2
                while index < len(lines) and lines[index].strip().startswith("|"):
                    table_lines.append(lines[index])
                    index += 1
                output.append(self.render_table(table_lines))
                continue

            if stripped.startswith(">"):
                quote_lines: list[str] = []
                while index < len(lines) and lines[index].strip().startswith(">"):
                    quote_lines.append(lines[index].strip()[1:].strip())
                    index += 1
                output.append(
                    "<blockquote>"
                    + "\n".join(
                        f"<p>{self.inline(item)}</p>" for item in quote_lines if item
                    )
                    + "</blockquote>"
                )
                continue

            if re.match(r"^\s*[-*]\s+", line):
                items: list[str] = []
                while index < len(lines) and re.match(r"^\s*[-*]\s+", lines[index]):
                    items.append(re.sub(r"^\s*[-*]\s+", "", lines[index]).strip())
                    index += 1
                output.append(
                    "<ul>"
                    + "".join(f"<li>{self.inline(item)}</li>" for item in items)
                    + "</ul>"
                )
                continue

            if re.match(r"^\s*\d+\.\s+", line):
                items = []
                while index < len(lines) and re.match(r"^\s*\d+\.\s+", lines[index]):
                    items.append(re.sub(r"^\s*\d+\.\s+", "", lines[index]).strip())
                    index += 1
                output.append(
                    "<ol>"
                    + "".join(f"<li>{self.inline(item)}</li>" for item in items)
                    + "</ol>"
                )
                continue

            paragraph = [line.strip()]
            index += 1
            while (
                index < len(lines)
                and lines[index].strip()
                and not re.match(r"^(#{1,6})\s+", lines[index])
                and not lines[index].strip().startswith(("```", ">", "|", "- ", "* "))
                and not re.match(r"^\s*\d+\.\s+", lines[index])
            ):
                paragraph.append(lines[index].strip())
                index += 1
            output.append(f"<p>{self.inline(' '.join(paragraph))}</p>")

        return "\n".join(output)


def collect_stats() -> dict:
    stories = load_stories_by_era()
    dart_tests = 0
    dart_test_files = 0
    per_test_dir: dict[str, tuple[int, int]] = {}
    for path in sorted((ROOT / "test").rglob("*_test.dart")):
        dart_test_files += 1
        text = path.read_text(encoding="utf-8")
        count = len(re.findall(r"\btest(?:Widgets|Goldens)?\s*\(", text))
        dart_tests += count
        key = (
            path.parts[path.parts.index("test") + 1] if len(path.parts) > 2 else "root"
        )
        files, tests = per_test_dir.get(key, (0, 0))
        per_test_dir[key] = (files + 1, tests + count)
    helper_path = ROOT / "test" / "state" / "story_controller_test_groups.dart"
    if helper_path.exists():
        dart_tests += len(
            re.findall(
                r"\btest(?:Widgets|Goldens)?\s*\(",
                helper_path.read_text(encoding="utf-8"),
            )
        )

    python_test_files = list((ROOT / "tools").rglob("test_*.py"))
    python_tests = 0
    for path in python_test_files:
        python_tests += len(
            re.findall(r"\bdef\s+test_", path.read_text(encoding="utf-8"))
        )

    return {
        "guide_count": len(guide_files()),
        "event_count": sum(len(events) for events in stories.values()),
        "era_counts": {era.code: len(stories.get(era.code, [])) for era in ERA_ORDER},
        "dart_test_files": dart_test_files,
        "dart_tests": dart_tests,
        "python_test_files": len(python_test_files),
        "python_tests": python_tests,
        "per_test_dir": per_test_dir,
    }


def css_text() -> str:
    return """
:root {
  --bg: #f7f3ea;
  --panel: #fffaf0;
  --panel-2: #f0f7f4;
  --ink: #24352f;
  --muted: #68786f;
  --line: #d9cdb8;
  --accent: #3f7f6a;
  --accent-2: #a15c38;
  --accent-3: #405f8f;
  --code-bg: #17211d;
  --code-ink: #eef7ef;
  color-scheme: light;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background:
    linear-gradient(180deg, rgba(63,127,106,.08), transparent 260px),
    var(--bg);
  color: var(--ink);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  line-height: 1.62;
}
a { color: #246a58; text-decoration-thickness: .08em; text-underline-offset: .18em; }
.layout {
  display: grid;
  grid-template-columns: minmax(220px, 300px) minmax(0, 1fr);
  min-height: 100vh;
}
.sidebar {
  position: sticky;
  top: 0;
  align-self: start;
  height: 100vh;
  overflow: auto;
  padding: 28px 18px;
  border-right: 1px solid var(--line);
  background: rgba(255,250,240,.86);
  backdrop-filter: blur(12px);
}
.brand { font-weight: 800; font-size: 18px; margin-bottom: 4px; }
.subtle { color: var(--muted); font-size: 13px; }
.nav { display: grid; gap: 14px; margin-top: 22px; }
.nav-group { display: grid; gap: 4px; }
.nav-heading {
  padding: 2px 10px;
  color: var(--muted);
  font-size: 11px;
  font-weight: 800;
  letter-spacing: .05em;
  text-transform: uppercase;
}
.nav a {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 8px 10px;
  border-radius: 8px;
  color: var(--ink);
  text-decoration: none;
}
.nav a.nav-sub { margin-left: 14px; padding-left: 14px; border-left: 2px solid #d8e4d7; font-size: 14px; }
.nav a.nav-appendix { margin-left: 14px; padding-left: 14px; border-left: 2px dashed #d8d0c1; font-size: 14px; color: #52645c; }
.nav a.active, .nav a:hover { background: #e7efe9; color: #174d40; }
.content { min-width: 0; padding: 32px clamp(18px, 4vw, 56px) 80px; }
.page-shell { max-width: 1180px; margin: 0 auto; }
.hero {
  border: 1px solid var(--line);
  border-radius: 18px;
  padding: clamp(20px, 4vw, 38px);
  background: linear-gradient(135deg, #fffdf7, #eef6f0);
  box-shadow: 0 18px 50px rgba(57, 75, 64, .10);
}
.eyebrow { color: var(--accent); font-weight: 700; text-transform: uppercase; letter-spacing: .08em; font-size: 12px; }
h1, h2, h3, h4 { line-height: 1.22; letter-spacing: 0; }
h1 { margin: 8px 0 10px; font-size: clamp(32px, 5vw, 58px); }
h2 { margin-top: 44px; padding-top: 8px; border-top: 1px solid var(--line); }
h3 { margin-top: 30px; color: #2f5f51; }
h4 { margin-top: 24px; }
.grid { display: grid; gap: 16px; }
.cards { grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); margin-top: 22px; }
.card {
  border: 1px solid var(--line);
  border-radius: 14px;
  background: rgba(255,255,255,.62);
  padding: 16px;
}
.card strong { display: block; font-size: 18px; }
.guide-family {
  border: 1px solid var(--line);
  border-radius: 16px;
  background: rgba(255,255,255,.62);
  padding: 18px;
  margin: 18px 0;
}
.family-head {
  display: flex;
  gap: 12px;
  justify-content: space-between;
  align-items: baseline;
  border-bottom: 1px solid #e3d8c5;
  padding-bottom: 10px;
  margin-bottom: 12px;
}
.family-head h3 { margin: 0; color: var(--ink); }
.family-head p { margin: 0; color: var(--muted); }
.family-docs { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 10px; }
.guide-doc {
  display: block;
  border: 1px solid #ded3bf;
  border-radius: 12px;
  padding: 12px;
  background: rgba(250,247,239,.76);
  color: var(--ink);
  text-decoration: none;
}
.guide-doc.main { background: #edf7f1; border-color: #bfd7c9; }
.guide-doc.appendix { background: #f7f2e8; border-style: dashed; }
.guide-doc .doc-type { display: inline-block; margin-bottom: 5px; color: var(--muted); font-size: 11px; font-weight: 800; }
.guide-doc strong { display: block; font-size: 16px; }
.guide-doc p { margin: 5px 0 0; color: var(--muted); font-size: 13px; }
.metric { font-size: 34px; font-weight: 800; color: #275b4d; }
.flow {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 10px;
  margin: 18px 0 4px;
}
.step {
  border: 1px solid #cddccc;
  border-radius: 12px;
  background: #fbfff9;
  padding: 14px;
  min-height: 98px;
}
.step span { display: block; color: var(--muted); font-size: 12px; font-weight: 700; }
.bar-row { display: grid; grid-template-columns: 170px 1fr 48px; gap: 10px; align-items: center; margin: 8px 0; }
.bar { height: 12px; border-radius: 99px; background: #e4dccd; overflow: hidden; }
.bar > i { display: block; height: 100%; background: linear-gradient(90deg, var(--accent), #8fb66f); }
.toc {
  margin-top: 20px;
  padding: 16px;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: rgba(255,255,255,.58);
}
.toc a { display: block; text-decoration: none; padding: 3px 0; }
.toc .level-3 { padding-left: 18px; color: var(--muted); }
.doc-body {
  margin-top: 28px;
  border: 1px solid var(--line);
  border-radius: 18px;
  padding: clamp(18px, 3vw, 34px);
  background: rgba(255,253,247,.82);
}
.table-wrap { overflow-x: auto; margin: 18px 0; }
table { width: 100%; border-collapse: collapse; font-size: 14px; }
th, td { border: 1px solid #ded3bf; padding: 9px 10px; vertical-align: top; }
th { background: #edf4ed; text-align: left; }
tr:nth-child(even) td { background: rgba(245,239,229,.55); }
pre {
  overflow: auto;
  padding: 16px;
  border-radius: 12px;
  background: var(--code-bg);
  color: var(--code-ink);
}
code {
  padding: 2px 5px;
  border-radius: 5px;
  background: #edf2ec;
}
pre code { padding: 0; background: transparent; color: inherit; }
blockquote {
  margin: 18px 0;
  padding: 12px 16px;
  border-left: 4px solid var(--accent);
  background: #f0f7f2;
  color: #315348;
}
hr { border: 0; border-top: 1px solid var(--line); margin: 36px 0; }
.notice {
  border-left: 5px solid var(--accent-2);
  background: #fff4eb;
  padding: 14px 16px;
  border-radius: 12px;
}
.top-link { margin-top: 24px; display: inline-block; }
@media (max-width: 860px) {
  .layout { display: block; }
  .sidebar { position: relative; height: auto; border-right: 0; border-bottom: 1px solid var(--line); }
  .nav { grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); }
  .nav a.nav-sub, .nav a.nav-appendix { margin-left: 0; }
  .bar-row { grid-template-columns: 110px 1fr 42px; }
}
""".strip()


def js_text() -> str:
    return """
document.querySelectorAll('pre code').forEach((block) => {
  block.parentElement.setAttribute('tabindex', '0');
});
""".strip()


def stats_panel(stats: dict) -> str:
    return f"""
<div class="grid cards">
  <div class="card"><span class="subtle">Guide files</span><div class="metric">{stats['guide_count']}</div><strong>역할별 문서</strong></div>
  <div class="card"><span class="subtle">Story events</span><div class="metric">{stats['event_count']}</div><strong>현재 JSON 사건</strong></div>
  <div class="card"><span class="subtle">Dart tests</span><div class="metric">{stats['dart_tests']}</div><strong>{stats['dart_test_files']}개 테스트 파일 + helper</strong></div>
  <div class="card"><span class="subtle">Python tool tests</span><div class="metric">{stats['python_tests']}</div><strong>{stats['python_test_files']}개 파일</strong></div>
</div>
"""


def era_bars(stats: dict) -> str:
    counts = stats["era_counts"]
    max_count = max(counts.values()) or 1
    rows = []
    for era in ERA_ORDER:
        count = counts.get(era.code, 0)
        width = int(count / max_count * 100)
        rows.append(
            f'<div class="bar-row"><span>{html.escape(era.name)}</span>'
            f'<div class="bar"><i style="width:{width}%"></i></div><b>{count}</b></div>'
        )
    return (
        '<div class="card"><strong>시대별 사건 수</strong>' + "".join(rows) + "</div>"
    )


def test_bars(stats: dict) -> str:
    per_dir = stats["per_test_dir"]
    max_count = max((value[1] for value in per_dir.values()), default=1)
    rows = []
    for name, (files, tests) in sorted(per_dir.items()):
        width = int(tests / max_count * 100)
        rows.append(
            f'<div class="bar-row"><span>test/{html.escape(name)}</span>'
            f'<div class="bar"><i style="width:{width}%"></i></div><b>{tests}</b></div>'
        )
    return (
        '<div class="card"><strong>Dart 테스트 분포</strong>' + "".join(rows) + "</div>"
    )


def flow_panel(stem: str, stats: dict) -> str:
    if stem == "story_guide":
        return era_bars(stats)
    if stem == "TEST_GUIDE":
        return test_bars(stats)
    flows = {
        "CONTENT_UPDATE": [
            ("1", "JSON", "assets/200_stories + event_region_mapping"),
            ("2", "Seed", "seed-stories-characters / seed-quizzes"),
            ("3", "Assets", "generate-story-images / thumbnails"),
            ("4", "Bundle", "update-pubspec-assets + real build"),
            ("5", "Publish", "real seed 적용 시점 조절"),
        ],
        "MAKE_TARGETS": [
            ("local", "로컬 생성", "seed / thumbnails / pubspec"),
            ("db", "DB 적용", "apply-seeds-* ENV=real"),
            ("storage", "Storage", "avatars만 자동 업로드"),
            ("insert", "중간 삽입", "event_id 보존 후 seed"),
        ],
        "develop-flow": [
            ("dev", "개발", "scripts/run_dev.sh"),
            ("check", "검증", "format / analyze / test / asset checks"),
            ("patch", "DB 변경", "db_init + idempotent patch"),
            ("real", "운영", "ENV=real 명시 적용"),
        ],
        "DB_SETUP": [
            ("env", ".env", "공개 URL / anon / VAPID"),
            ("ops", ".env.ops", "service role / DB URL"),
            ("vault", "Vault", "DB 함수가 send-push 호출"),
            ("edge", "Secrets", "Edge Function 외부 API 키"),
        ],
        "INFRA_GUIDE": [
            ("app", "Flutter", "Supabase + Firebase SDK"),
            ("db", "Supabase", "Auth / Postgres / Storage / RPC"),
            ("edge", "Edge Functions", "Vertex / FCM 서버 호출"),
            ("device", "Devices", "iOS / Android / Web 알림"),
        ],
        "PUSH_SETUP": [
            ("firebase", "Firebase", "앱 등록 + VAPID + APNs"),
            ("edge", "send-push", "FIREBASE_SERVICE_ACCOUNT"),
            ("db", "pg_net", "Vault secret으로 함수 호출"),
            ("phone", "Device", "register_push_token 후 수신"),
        ],
        "WORKFLOW_GUIDE": [
            ("plan", "Plan", "영향 범위와 테스트 찾기"),
            ("do", "Do", "작게 수정하고 문서 동기화"),
            ("check", "Check", "diff / test / secret 점검"),
            ("act", "Act", "실패 반영과 최종 보고"),
        ],
        "README": [
            ("route", "읽을 문서 선택", "허브에서 canonical 문서 결정"),
            ("work", "작업", "개발/콘텐츠/DB/푸시/테스트"),
            ("html", "HTML", "시각화된 보조 문서 확인"),
        ],
    }
    items = flows.get(stem, [])
    if not items:
        return ""
    steps = "\n".join(
        f'<div class="step"><span>{html.escape(label)}</span><strong>{html.escape(title)}</strong><p>{html.escape(body)}</p></div>'
        for label, title, body in items
    )
    return f'<div class="flow">{steps}</div>'


def navigation_html(active: str) -> str:
    groups_html: list[str] = []
    for group, entries in guide_groups():
        links: list[str] = []
        for entry, path in entries:
            target = html_name_for_md(path)
            classes = ["active"] if target == active else []
            classes.append(f"nav-{entry.level}")
            links.append(
                f'<a class="{" ".join(classes)}" href="{target}">'
                f"<span>{html.escape(read_title(path))}</span>"
                "</a>"
            )
        groups_html.append(
            '<div class="nav-group">'
            f'<div class="nav-heading">{html.escape(group.label)}</div>'
            + "".join(links)
            + "</div>"
        )
    return "\n".join(groups_html)


def grouped_guide_cards() -> str:
    groups: list[str] = []
    for group, entries in guide_groups():
        docs: list[str] = []
        for entry, path in entries:
            role, desc = GUIDE_DESCRIPTIONS.get(path.name, ("문서", ""))
            docs.append(
                f'<a class="guide-doc {html.escape(entry.level)}" href="{html_name_for_md(path)}">'
                f'<span class="doc-type">{html.escape(role)}</span>'
                f"<strong>{html.escape(read_title(path))}</strong>"
                f"<p>{html.escape(desc)}</p>"
                "</a>"
            )
        groups.append(
            '<section class="guide-family">'
            '<div class="family-head">'
            f"<div><h3>{html.escape(group.label)}</h3><p>{html.escape(group.summary)}</p></div>"
            "</div>"
            f'<div class="family-docs">{"".join(docs)}</div>'
            "</section>"
        )
    return "\n".join(groups)


def page_shell(
    *,
    title: str,
    active: str,
    body: str,
    toc: list[tuple[int, str, str]],
    intro: str,
    visual: str,
    stats: dict,
) -> str:
    nav = navigation_html(active)
    toc_html = ""
    if toc:
        toc_html = (
            '<div class="toc"><strong>On this page</strong>'
            + "".join(
                f'<a class="level-{level}" href="#{slug}">{html.escape(text)}</a>'
                for level, text, slug in toc[:80]
            )
            + "</div>"
        )
    return f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)} · Story Bible Guides</title>
  <link rel="stylesheet" href="assets/guide.css">
</head>
<body>
  <div class="layout">
    <aside class="sidebar">
      <div class="brand">Story Bible Guides</div>
      <div class="subtle">{stats['event_count']} events · {stats['dart_tests']} Dart tests</div>
      <nav class="nav">
        <a class="{"active" if active == "index.html" else ""}" href="index.html">가이드 인덱스</a>
        {nav}
      </nav>
    </aside>
    <main class="content">
      <div class="page-shell">
        <section class="hero">
          <div class="eyebrow">Developer documentation</div>
          <h1>{html.escape(title)}</h1>
          <p>{html.escape(intro)}</p>
          {visual}
          {toc_html}
        </section>
        <article class="doc-body">
          {body}
          <a class="top-link" href="#top">맨 위로</a>
        </article>
      </div>
    </main>
  </div>
  <script src="assets/guide.js"></script>
</body>
</html>
"""


def index_html(stats: dict) -> str:
    guide_cards = grouped_guide_cards()
    visual = """
<div class="flow">
  <div class="step"><span>Daily work</span><strong>develop-flow</strong><p>코드, seed, patch, real 배포 판단</p></div>
  <div class="step"><span>Content</span><strong>CONTENT_UPDATE</strong><p>새 이야기와 이미지 번들 운영</p></div>
  <div class="step"><span>Make</span><strong>MAKE_TARGETS</strong><p>target별 입력, 출력, 원격 영향</p></div>
  <div class="step"><span>Platform</span><strong>DB / Infra / Push</strong><p>신규 환경과 푸시 배관</p></div>
  <div class="step"><span>Quality</span><strong>TEST_GUIDE</strong><p>테스트 영향 범위 탐색</p></div>
</div>
"""
    return f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Story Bible Guides</title>
  <link rel="stylesheet" href="assets/guide.css">
</head>
<body>
  <div class="layout">
    <aside class="sidebar">
      <div class="brand">Story Bible Guides</div>
      <div class="subtle">HTML companion docs</div>
      <nav class="nav">
        <a class="active" href="index.html">가이드 인덱스</a>
        {navigation_html("index.html")}
      </nav>
    </aside>
    <main class="content">
      <div class="page-shell">
        <section class="hero">
          <div class="eyebrow">Developer map</div>
          <h1>Story Bible 개발 문서 지도</h1>
          <p>Markdown 가이드를 시각화된 HTML로 변환한 보조 문서다. 실제 소스는 같은 폴더의 md 파일이며, 이 HTML은 빠른 탐색과 온보딩용으로 쓴다.</p>
          {stats_panel(stats)}
          {visual}
        </section>
        <section class="doc-body">
          <h2>문서 역할</h2>
          {guide_cards}
          <h2>읽는 순서</h2>
          <div class="table-wrap"><table>
            <thead><tr><th>상황</th><th>먼저 볼 문서</th><th>함께 볼 문서</th></tr></thead>
            <tbody>
              <tr><td>개발/배포 판단</td><td>develop-flow.md</td><td>CONTENT_UPDATE.md, MAKE_TARGETS.md</td></tr>
              <tr><td>인프라 현재 구조 파악</td><td>INFRA_GUIDE.md</td><td>DB_SETUP.md, LOCAL_ENV_FILES.md</td></tr>
              <tr><td>기능별 운영</td><td>PUSH_SETUP.md</td><td>INFRA_GUIDE.md의 FCM/secret 원리</td></tr>
              <tr><td>테스트 영향 범위</td><td>TEST_GUIDE.md</td><td>docs/TESTING.md</td></tr>
              <tr><td>긴 레퍼런스 확인</td><td>각 메인 문서</td><td>WORKFLOW_GUIDE.md, story_guide.md</td></tr>
            </tbody>
          </table></div>
          <h2>현재 콘텐츠 분포</h2>
          {era_bars(stats)}
        </section>
      </div>
    </main>
  </div>
  <script src="assets/guide.js"></script>
</body>
</html>
"""


def build_html_pages() -> dict[Path, str]:
    stats = collect_stats()
    guide_paths = guide_files()
    guide_map = {path.resolve(): html_name_for_md(path) for path in guide_paths}
    pages: dict[Path, str] = {}
    pages[HTML_ASSET_DIR / "guide.css"] = css_text() + "\n"
    pages[HTML_ASSET_DIR / "guide.js"] = js_text() + "\n"
    pages[HTML_DIR / "index.html"] = index_html(stats)

    for path in guide_paths:
        renderer = MarkdownRenderer(path.resolve(), guide_map)
        markdown = path.read_text(encoding="utf-8")
        body = renderer.render(markdown)
        role, desc = GUIDE_DESCRIPTIONS.get(path.name, ("문서", ""))
        visual = flow_panel(path.stem, stats)
        pages[HTML_DIR / html_name_for_md(path)] = page_shell(
            title=read_title(path),
            active=html_name_for_md(path),
            body=body,
            toc=renderer.toc,
            intro=f"{role}: {desc}",
            visual=visual,
            stats=stats,
        )
    return pages


def write_or_check(outputs: dict[Path, str], *, check: bool) -> int:
    changed: list[Path] = []
    for path, content in outputs.items():
        content = "\n".join(line.rstrip() for line in content.splitlines()) + "\n"
        if path.exists():
            current = path.read_text(encoding="utf-8")
            if current == content:
                continue
        changed.append(path)
        if not check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
    if check and changed:
        for path in changed:
            print(f"would update: {path.relative_to(ROOT)}")
        return 1
    return 0


def clean_html_dir() -> None:
    if HTML_DIR.exists():
        for child in HTML_DIR.iterdir():
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()


def main() -> int:
    args = parse_args()
    outputs: dict[Path, str] = {}
    if not args.html_only:
        outputs[STORY_GUIDE] = build_story_guide_text()
    if not args.story_guide_only:
        if not args.check:
            clean_html_dir()
        outputs.update(build_html_pages())
    return write_or_check(outputs, check=args.check)


if __name__ == "__main__":
    sys.exit(main())
