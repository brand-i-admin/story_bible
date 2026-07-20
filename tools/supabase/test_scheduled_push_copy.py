from __future__ import annotations

import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DB_INIT_PATH = REPO_ROOT / "db_init.sql"
PATCH_PATH = (
    REPO_ROOT
    / "supabase"
    / "patches"
    / "20260720_1648_update_monday_wednesday_push_copy.sql"
)

MONDAY_PUSH_CALL = """perform public._fire_push_broadcast(
    '좋은 한주의 시작입니다!',
    '이번주도 하나님과 친밀한 동행하는 한주 되세요!',
    null,
    'weekly_exploration'
  );"""

WEDNESDAY_PUSH_CALL = """perform public._fire_push_broadcast(
    '한주도 잘 보내고 계신가요!?',
    '이야기 탐험으로 하나님의 이야기를 탐험해보세요!',
    '/daily-exploration',
    'daily_exploration'
  );"""

REMOVED_PUSH_COPY = (
    "이번 주 미션이 열렸어요",
    "주간 미션을 시작해 보세요",
    "오늘의 미션이 열렸어요",
    "사건을 함께 미션으로 만나봐요",
)


def _function_sql(sql: str, function_name: str) -> str:
    start = sql.index(f"create or replace function public.{function_name}()")
    end = sql.index("$$;", start) + len("$$;")
    return sql[start:end]


class ScheduledPushCopyTests(unittest.TestCase):
    def test_db_init_uses_new_monday_and_wednesday_push_copy(self) -> None:
        sql = DB_INIT_PATH.read_text(encoding="utf-8")
        monday_sql = _function_sql(sql, "pick_weekly_character")
        wednesday_sql = _function_sql(sql, "dispatch_daily_exploration_push")

        self.assertIn(MONDAY_PUSH_CALL, monday_sql)
        self.assertIn(WEDNESDAY_PUSH_CALL, wednesday_sql)
        for removed_copy in REMOVED_PUSH_COPY:
            self.assertNotIn(removed_copy, monday_sql + wednesday_sql)

    def test_operational_patch_matches_canonical_push_copy(self) -> None:
        sql = PATCH_PATH.read_text(encoding="utf-8")

        self.assertIn(MONDAY_PUSH_CALL, sql)
        self.assertIn(WEDNESDAY_PUSH_CALL, sql)
        for removed_copy in REMOVED_PUSH_COPY:
            self.assertNotIn(removed_copy, sql)


if __name__ == "__main__":
    unittest.main()
