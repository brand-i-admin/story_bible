---
name: pre-push-pr
description: "깃허브에 푸시하기 전에 현재 브랜치의 변경 사항을 점검하고, pre-commit과 저장소별 lint/test를 실행하고, diff를 검토해 한국어 PR 제목과 본문을 작성한 뒤, commit과 push까지 진행하는 스킬이다. 푸시 전 위생 점검, pre-commit 실행, black 포맷팅, 테스트 확인, PR 초안 작성, 커밋, 브랜치 푸시가 필요할 때 사용한다."
---

# Pre Push Pr

## 개요

현재 브랜치를 GitHub에 올리기 전에 검증, 리뷰, 문서화 단계를 빠뜨리지 않고 처리한다. 저장소에 이미 있는 자동화를 우선 사용하고, 실제로 통과한 검사 결과만 근거로 커밋과 푸시를 진행한다.

## 작업 순서

1. 먼저 저장소 상태를 파악한다.
- `git status --short`, `git branch --show-current`, `git diff --stat`, `git diff --cached --stat`, `git log --oneline --decorate -5`를 확인한다.
- `.pre-commit-config.yaml`, `package.json`, `pyproject.toml`, `pubspec.yaml`, `go.mod`, `Cargo.toml`, `Makefile`, CI 설정, README를 읽고 이 저장소가 기대하는 검사 흐름을 찾는다.
- 현재 작업과 무관한 변경이 섞여 있으면 커밋 범위를 분리한다.

2. 검사는 `pre-commit`을 우선으로 실행한다.
- `.pre-commit-config.yaml`이 있으면 `pre-commit run --all-files`를 가장 먼저 실행한다.
- `pre-commit`이 없거나 설정 파일이 없으면 그 사실을 명확히 보고하고, 저장소 기본 lint/test로 폴백한다.
- Python 파일은 `black`으로 검사하거나 포맷한다.
- Flutter/Dart 파일은 `black` 대상이 아니며, `dart format`으로 포맷 상태를 검사한다.
- 사용자가 Python 포맷만 따로 원하면 `black tools` 또는 대상 Python 파일에 직접 `black`을 실행한 뒤 전체 `pre-commit`을 다시 돌린다.
- 사용자가 Flutter 포맷만 따로 원하면 `dart format`을 실행한 뒤 전체 `pre-commit`을 다시 돌린다.

3. 저장소 유형에 맞는 추가 검사를 실행한다.
- Flutter/Dart 저장소면 `flutter analyze`와 `flutter test`를 기본 검사로 사용한다.
- Flutter/Dart 저장소면 필요 시 `dart format --output=none --set-exit-if-changed`로 포맷 검사도 함께 본다.
- Node 저장소면 `package.json`의 스크립트를 읽고 거기 정의된 lint/test 명령을 사용한다.
- Python 저장소면 `pyproject.toml`, `pytest.ini`, `tox.ini`, `Makefile`에 정의된 lint/test 진입점을 우선 사용한다.
- Go 저장소면 `go test ./...`를 기본으로 보고, Rust 저장소면 `cargo test`와 필요 시 `cargo clippy`를 사용한다.

4. PR 초안은 diff를 읽고 한국어로 작성한다.
- `git diff --stat`와 필요한 파일 본문을 읽고, 사용자 관점에서 바뀐 동작과 내부 구조 변경을 구분해 정리한다.
- PR 제목은 반드시 한국어로 쓴다.
- PR 본문도 반드시 한국어로 쓰고, 기본 섹션은 `## 요약`, `## 테스트`, `## 리스크` 또는 `## 참고`를 사용한다.
- `## 테스트`에는 실제로 실행한 명령만 적는다.
- 테스트를 못 돌렸다면 못 돌린 이유를 한국어로 분명히 적는다.

5. 커밋은 검증 후에만 한다.
- 관련 없는 변경이 섞여 있으면 `git add <paths>`처럼 경로를 좁혀 스테이징한다.
- 커밋 메시지는 저장소의 기존 스타일을 따르되, 명확한 한국어 또는 저장소에서 일관되게 쓰는 영어 imperative 스타일 중 하나로 맞춘다.
- 커밋 뒤에는 `git status --short`와 `git log -1 --stat`로 결과를 다시 확인한다.

6. 푸시는 마지막에 조심해서 한다.
- 현재 브랜치 업스트림이 없으면 `git push -u origin HEAD`, 있으면 `git push`를 사용한다.
- 네트워크나 권한 제한이 있으면 그 사실을 설명하고 필요한 승인을 요청한다.
- 사용자가 실제 GitHub PR 생성까지 원하고 `gh`가 있으면, 작성한 한국어 제목/본문으로 PR 생성까지 진행한다.

## 이 저장소 기본값

- 이 저장소는 Flutter 프로젝트로 취급한다.
- 기본 검사는 `pre-commit run --all-files`로 Python/파일 기본 검사와 Dart 포맷을 확인하고, `pre-commit run --hook-stage pre-push --all-files` 또는 실제 `git push`에서 `flutter analyze`, `flutter test`를 확인한다.
- Python 도구 스크립트는 `tools/*.py` 범위에서 `black`을 적용한다.
- Flutter/Dart 코드는 `black`이 아니라 `dart format`을 적용한다.
- `analysis_options.yaml`은 `flutter_lints`를 사용한다.
- PR 제목과 본문은 기본적으로 한국어로 작성한다.

## 가드레일

- 실행하지 않은 검사를 통과했다고 쓰지 않는다.
- 확인하지 않은 diff를 바탕으로 PR을 쓰지 않는다.
- 관련 없는 변경을 묶어서 커밋하지 않는다.
- 스테이징된 변경과 작업 디렉토리 변경이 다른 작업처럼 보이면 멈추고 범위를 다시 확인한다.
- 최종 보고에는 무엇을 바꿨는지, 어떤 명령을 실행했는지, commit/push가 실제로 일어났는지, PR 초안이 무엇인지 포함한다.

## 한국어 PR 형식

PR 제목 예시:
- `성경 홈 화면 법률 문서 진입 동선 정리`
- `문서 다이얼로그 표시 흐름 개선`

PR 본문 기본 형식:

```md
## 요약
- 사용자 관점 변경 1
- 내부 구조 변경 1

## 테스트
- pre-commit run --all-files
- pre-commit run --hook-stage pre-push --all-files

## 리스크
- 남아 있는 확인 포인트
```

## 사용 예시

- `Use $pre-push-pr to run pre-commit, flutter analyze, flutter test, then write the PR in Korean, commit, and push.`
- `Use $pre-push-pr to inspect the current diff, format Python tools with black, and draft a Korean PR body.`
