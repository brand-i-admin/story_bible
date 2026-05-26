---
name: testing
description: "Story Bible 테스트 작업 스킬. Flutter unit/widget test, Python 도구 테스트, TDD, coverage, pre-commit hook, CI, mocktail, Riverpod ProviderContainer 테스트, 검증 명령 선택에 사용한다."
---

# Testing

## 작업 순서

1. `docs/TESTING.md`를 읽는다. 커버리지 gap을 볼 때는 `docs/guides/TEST_GUIDE.md`도 읽는다.
2. production code 수정 전 관련 테스트를 찾는다.
3. 새 동작이나 버그 수정은 가능하면 실패 테스트를 먼저 추가한다.
4. 테스트는 source 구조 가까이에 둔다.
   - `test/models/`
   - `test/state/`
   - `test/data/`
   - `test/widgets/`
   - `tools/**/test_*.py`
5. Dart/Riverpod 테스트는 `mocktail`과 `ProviderContainer` override를 사용한다.
6. Python 도구 테스트는 추가 의존성 없이 돌도록 `unittest`를 사용한다. `tools/`가 Python package 계층이 아니므로 `tools/run_unit_tests.py`로 실행한다.

## 명령

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test --coverage
python3 tools/run_unit_tests.py
pre-commit run --all-files
pre-commit run --hook-stage pre-push --all-files
```

## PDCA 적용

- Plan: 어떤 동작을 보장할지, 기존 테스트와 충돌하는지 먼저 확인한다.
- Do: 실패 테스트 → 구현 → green 순서로 진행한다.
- Check: 테스트 변경이 스펙 변경인지 단순 정비인지 구분하고, 실제 검증 명령을 실행한다.
- Act: 실패한 테스트를 반영해 수정하거나, 못 돌린 검사는 이유와 대체 확인 방법을 남긴다.

## 가드레일

- 실행하지 않은 검사를 통과했다고 말하지 않는다.
- unit test가 live Supabase나 원격 API에 의존하지 않게 한다.
- 기존 테스트 수정은 스펙 수정이다. 이유를 명확히 하고 범위를 좁힌다.
- 공유 코드 변경은 focused test 후 전체 suite를 고려한다.

## 함께 갱신할 문서

- `docs/TESTING.md`: 전략, 명령, 구조, hook.
- `docs/guides/TEST_GUIDE.md`: 구체적 커버리지 gap과 알려진 contract.
- `.github/workflows/flutter_ci.yml`, `.pre-commit-config.yaml`: 검증 흐름 변경 시.
