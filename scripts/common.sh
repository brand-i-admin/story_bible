#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
DEV_REF="emkoqhnzeiwcwgcaasuh"
REAL_REF="cvnutbizsgeycdjcbled"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

print_target() {
  local runtime_env="$1"
  local project_ref="$DEV_REF"

  if [[ "$runtime_env" != "dev" ]]; then
    project_ref="$REAL_REF"
  fi

  echo "Using Supabase target: $runtime_env ($project_ref)"
}

validate_supabase_env() {
  local runtime_env="$1"
  local url_key="SUPABASE_URL_DEV"
  local anon_key_name="SUPABASE_ANON_KEY_DEV"
  local expected_ref="$DEV_REF"

  if [[ "$runtime_env" != "dev" ]]; then
    url_key="SUPABASE_URL_PROD"
    anon_key_name="SUPABASE_ANON_KEY_PROD"
    expected_ref="$REAL_REF"
  fi

  require_command python3

  python3 - "$ENV_FILE" "$url_key" "$anon_key_name" "$expected_ref" <<'PY'
import base64
import json
import re
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
url_key = sys.argv[2]
anon_key_name = sys.argv[3]
expected_ref = sys.argv[4]

if not env_path.exists():
    raise SystemExit(f"Missing .env file: {env_path}")

values = {}
for raw_line in env_path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    values[key] = value

url = values.get(url_key, "")
anon_key = values.get(anon_key_name, "")

if not url:
    raise SystemExit(f"Missing {url_key} in {env_path}")
if not anon_key:
    raise SystemExit(f"Missing {anon_key_name} in {env_path}")

match = re.match(r"^https://([a-z0-9]+)\.supabase\.co/?$", url)
if not match:
    raise SystemExit(f"{url_key} is not a valid Supabase URL: {url}")

url_ref = match.group(1)
if url_ref != expected_ref:
    raise SystemExit(
        f"{url_key} points to {url_ref}, expected {expected_ref}. "
        f"Update {env_path} before running this script."
    )

parts = anon_key.split(".")
if len(parts) != 3:
    raise SystemExit(f"{anon_key_name} is not a valid Supabase anon key.")

payload = parts[1]
payload += "=" * (-len(payload) % 4)
decoded = json.loads(base64.urlsafe_b64decode(payload))
key_ref = decoded.get("ref")
if key_ref != expected_ref:
    raise SystemExit(
        f"{anon_key_name} points to {key_ref}, expected {expected_ref}. "
        f"Update {env_path} before running this script."
    )
PY
}

## .env 한 줄에서 KEY=VALUE 형식으로 값을 추출한다. 없으면 빈 문자열.
## 양끝 따옴표(`"` 또는 `'`)는 벗겨낸다. 주석(#) 라인은 무시.
## validate_supabase_env 와 같은 파서를 쓰지만 단일 키 조회용.
read_env_value() {
  local key="$1"
  [[ -f "$ENV_FILE" ]] || return 0
  local line
  line=$(grep -E "^${key}=" "$ENV_FILE" | tail -n1 || true)
  [[ -n "$line" ]] || return 0
  local value="${line#${key}=}"
  # 양끝 동일한 따옴표로 감싸여 있으면 제거.
  if [[ ${#value} -ge 2 ]]; then
    local first="${value:0:1}"
    local last="${value: -1}"
    if [[ "$first" == "$last" ]] && [[ "$first" == '"' || "$first" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s' "$value"
}

strip_android_integration_test_registrant() {
  local registrant="$ROOT_DIR/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
  [[ -f "$registrant" ]] || return 0

  python3 - "$registrant" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
block = """    try {
      flutterEngine.getPlugins().add(new dev.flutter.plugins.integration_test.IntegrationTestPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin integration_test, dev.flutter.plugins.integration_test.IntegrationTestPlugin", e);
    }
"""
updated = text.replace(block, "")
if updated != text:
    path.write_text(updated, encoding="utf-8")
    print(f"Removed dev-only integration_test registrant from {path}")
PY
}

prepare_flutter_workspace() {
  require_command flutter
  require_command python3

  cd "$ROOT_DIR"
  echo "Cleaning Flutter build outputs..."
  flutter clean
  echo "Refreshing Flutter package metadata..."
  flutter pub get

  # Flutter can regenerate the dev-only integration_test Android registrant
  # after pub get, but release Android builds do not package that Java class.
  strip_android_integration_test_registrant
}

run_flutter() {
  local runtime_env="$1"
  shift

  require_command flutter
  validate_supabase_env "$runtime_env"
  print_target "$runtime_env"
  prepare_flutter_workspace

  # .env 의 FCM_VAPID_KEY 를 --dart-define 으로 주입 (Flutter Web 전용 키).
  # 값이 비어 있으면 네이티브와 마찬가지로 웹 푸시가 비활성화되며,
  # lib/services/push_service.dart 의 String.fromEnvironment fallback 이 빈
  # 문자열을 반환해 앱은 정상 동작한다.
  local fcm_vapid_key
  fcm_vapid_key="$(read_env_value FCM_VAPID_KEY)"

  local flutter_args=("$@" --no-pub)
  if [[ -n "$fcm_vapid_key" ]]; then
    exec flutter "${flutter_args[@]}" \
      --dart-define=ENV="$runtime_env" \
      --dart-define=FCM_VAPID_KEY="$fcm_vapid_key"
  else
    exec flutter "${flutter_args[@]}" --dart-define=ENV="$runtime_env"
  fi
}

run_app() {
  local runtime_env="$1"
  shift
  run_flutter "$runtime_env" run "$@"
}

build_ios() {
  local runtime_env="$1"
  shift
  run_flutter "$runtime_env" build ipa --release "$@"
}

build_android() {
  local runtime_env="$1"
  shift
  run_flutter "$runtime_env" build appbundle --release "$@"
}
