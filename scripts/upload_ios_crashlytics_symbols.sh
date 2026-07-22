#!/usr/bin/env bash
set -euo pipefail

# Xcode archive uses ACTION=install. Local builds do not need to export dSYMs
# and must not contact Firebase as a side effect of compiling the app.
if [[ "${SKIP_CRASHLYTICS_SYMBOL_UPLOAD:-NO}" == "YES" ]]; then
  echo "Skipping Crashlytics symbol upload by build setting."
  exit 0
fi

if [[ "${ACTION:-}" != "install" ]]; then
  echo "Skipping Crashlytics symbol upload for Xcode action: ${ACTION:-unset}"
  exit 0
fi

PATH="${PATH}:$FLUTTER_ROOT/bin:${PUB_CACHE:-$HOME/.pub-cache}/bin:$HOME/.pub-cache/bin"

pods_crashlytics_script="${PODS_ROOT:-}/FirebaseCrashlytics/run"
flutter_crashlytics_script="${PROJECT_DIR}/../build/ios/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
xcode_crashlytics_script="${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"

if [[ -x "$pods_crashlytics_script" ]]; then
  crashlytics_upload_script="$pods_crashlytics_script"
elif [[ -x "$flutter_crashlytics_script" ]]; then
  crashlytics_upload_script="$flutter_crashlytics_script"
elif [[ -x "$xcode_crashlytics_script" ]]; then
  crashlytics_upload_script="$xcode_crashlytics_script"
else
  echo "error: Crashlytics upload script was not found in CocoaPods or SwiftPM checkouts." >&2
  exit 1
fi

exec flutterfire upload-crashlytics-symbols \
  --upload-symbols-script-path="$crashlytics_upload_script" \
  --platform=ios \
  --apple-project-path="${SRCROOT}" \
  --env-platform-name="${PLATFORM_NAME}" \
  --env-configuration="${CONFIGURATION}" \
  --env-project-dir="${PROJECT_DIR}" \
  --env-built-products-dir="${BUILT_PRODUCTS_DIR}" \
  --env-dwarf-dsym-folder-path="${DWARF_DSYM_FOLDER_PATH}" \
  --env-dwarf-dsym-file-name="${DWARF_DSYM_FILE_NAME}" \
  --env-infoplist-path="${INFOPLIST_PATH}" \
  --default-config=default
