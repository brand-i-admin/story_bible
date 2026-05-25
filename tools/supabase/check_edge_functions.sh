#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v deno >/dev/null 2>&1; then
  echo "deno is not installed. Install Deno to run local Edge Function checks."
  echo "See: https://docs.deno.com/runtime/getting_started/installation/"
  exit 127
fi

functions=(
  "generate-proposal-character"
  "generate-proposal-scene"
  "send-push"
)

for fn in "${functions[@]}"; do
  echo "==> deno check supabase/functions/${fn}/index.ts"
  deno check "${ROOT_DIR}/supabase/functions/${fn}/index.ts"
done

echo "Edge Function checks passed."
