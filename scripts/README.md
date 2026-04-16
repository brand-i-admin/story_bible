# Scripts

`scripts/`에는 실행 대상 Supabase 환경을 고정해서 `flutter run`과 배포 빌드를 호출하는 스크립트가 들어 있습니다.

## Environments

- `dev`: Supabase project ref `emkoqhnzeiwcwgcaasuh`
- `real`: Supabase project ref `cvnutbizsgeycdjcbled`

스크립트는 실행 전에 [../.env](../.env)의 `SUPABASE_URL_DEV`, `SUPABASE_ANON_KEY_DEV`, `SUPABASE_URL_PROD`, `SUPABASE_ANON_KEY_PROD` 값을 읽고, URL과 anon key 안의 project ref가 기대값과 일치하는지 검사합니다.

## Files

- [common.sh](./common.sh): 공통 환경 검증과 `flutter` 호출 로직
- [run_dev.sh](./run_dev.sh): `ENV=dev`로 `flutter run`
- [run_real.sh](./run_real.sh): `ENV=real`로 `flutter run`
- [build_ios_dev.sh](./build_ios_dev.sh): `ENV=dev`로 iOS IPA release build
- [build_ios_real.sh](./build_ios_real.sh): `ENV=real`로 iOS IPA release build
- [build_android_dev.sh](./build_android_dev.sh): `ENV=dev`로 Android App Bundle release build
- [build_android_real.sh](./build_android_real.sh): `ENV=real`로 Android App Bundle release build

## Usage

프로젝트 루트에서 실행합니다.

```bash
scripts/run_dev.sh
scripts/run_real.sh
scripts/build_ios_dev.sh
scripts/build_ios_real.sh
scripts/build_android_dev.sh
scripts/build_android_real.sh
```

추가 Flutter 인자가 필요하면 뒤에 그대로 붙이면 됩니다.

```bash
scripts/run_dev.sh -d chrome
scripts/run_real.sh -d ios
scripts/build_android_real.sh --build-number=42
scripts/build_ios_dev.sh --export-method=ad-hoc
```

## Notes

- `run_*` 스크립트는 `flutter run --dart-define=ENV=...`를 호출합니다.
- `build_ios_*` 스크립트는 `flutter build ipa --release --dart-define=ENV=...`를 호출합니다.
- `build_android_*` 스크립트는 `flutter build appbundle --release --dart-define=ENV=...`를 호출합니다.
- 로컬에 `flutter`와 `python3`가 설치되어 있어야 합니다.
