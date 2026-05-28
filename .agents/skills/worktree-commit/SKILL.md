---
name: worktree-commit
description: "현재 작업 내용을 커밋하거나, Codex 임시/보조 worktree의 detached 작업 결과를 안전하게 대상 브랜치에 반영하고 필요한 경우 worktree를 정리하는 스킬이다. 사용자가 '커밋해줘', '현재 작업 커밋', '워크트리 커밋', '원래 브랜치에 반영', '작업트리 정리'를 요청할 때 사용한다."
---

# Worktree Commit

## 목적

현재 위치가 일반 로컬 브랜치인지, 보조 worktree인지, detached HEAD인지 먼저 판별한 뒤
가장 안전한 커밋 흐름을 선택한다. 커밋은 사용자가 명시적으로 요청한 경우에만 만들고,
푸시는 사용자가 따로 요청하지 않는 한 하지 않는다.

## 시작 진단

먼저 다음을 확인한다.

```bash
git rev-parse --show-toplevel
git status --short
git status --branch --short
git branch --show-current
git rev-parse --abbrev-ref HEAD
git worktree list --porcelain
git log --oneline --decorate -8
git diff --stat
git diff --cached --stat
```

판별 기준:

- `git branch --show-current`가 비어 있지 않으면 일반 브랜치 작업으로 본다.
- 현재 repo root가 `git worktree list --porcelain`의 첫 번째 `worktree` 경로와 다르면
  보조 worktree로 본다.
- `git branch --show-current`가 비어 있거나 `rev-parse --abbrev-ref HEAD`가 `HEAD`면
  detached HEAD로 본다.
- 보조 worktree라도 일반 브랜치가 체크아웃되어 있으면 브랜치 작업으로 취급하고,
  사용자가 명시적으로 정리를 요청하지 않는 한 worktree를 삭제하지 않는다.

## 일반 브랜치 커밋 흐름

현재 작업이 일반 브랜치 위에 있으면 다음 순서로 진행한다.

1. 관련 없는 dirty file이 섞였는지 `git status --short`와 diff로 확인한다.
2. 커밋 범위를 좁힌다. 관련 없는 변경은 스테이징하지 않는다.
3. 작업 성격에 맞는 최소 검증을 실행한다. 이 저장소 기본값은 `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, 필요한 focused test다.
4. 검증 결과와 diff를 다시 확인한다.
5. `git add <paths>`로 대상 파일만 스테이징하고 `git diff --cached --stat`를 확인한다.
6. 저장소 스타일에 맞는 명확한 커밋 메시지로 커밋한다.
7. `git status --short`와 `git log -1 --stat`로 결과를 확인한다.

일반 브랜치 커밋 흐름에서는 worktree를 자동 삭제하지 않는다.

## Detached 또는 보조 Worktree 회수 흐름

detached HEAD이거나 Codex가 만든 보조 worktree처럼 보이는 곳에서 커밋 요청을 받으면,
커밋이 유실되지 않도록 먼저 구명용 브랜치를 만든다.

1. 대상 브랜치를 결정한다.
- 사용자가 브랜치를 지정했으면 그 브랜치를 사용한다.
- 사용자가 "원래 브랜치"라고만 말했고 명확히 추론할 수 있으면 그 브랜치를 사용한다.
- `git worktree list --porcelain`, `git branch --contains`, 최근 로그만으로 대상이 애매하면
  추측해서 반영하지 말고 대상 브랜치를 물어본다.

2. 구명용 브랜치를 만든다.
- detached HEAD이면 커밋 전에 `codex/worktree-commit-YYYYMMDD-HHMMSS` 형태의 브랜치를
  현재 HEAD에서 만든다.
- 이미 보조 worktree의 브랜치 위에 있으면 새 브랜치를 만들 필요는 없다.

3. 현재 worktree의 변경을 커밋한다.
- 관련 없는 변경은 제외한다.
- 검증을 실행하고, 실패하면 원인을 보고한 뒤 커밋 여부를 신중히 판단한다.
- 커밋 뒤 `git log -1 --stat`로 실제 커밋을 확인한다.

4. 대상 브랜치에 반영한다.
- 대상 브랜치가 다른 worktree에 체크아웃되어 있으면 그 worktree가 clean인지 먼저 확인하고
  그곳에서 cherry-pick 또는 merge를 수행한다.
- 대상 브랜치가 어디에도 체크아웃되어 있지 않으면 현재 보조 worktree에서 대상 브랜치로
  전환한 뒤 cherry-pick 또는 merge를 수행할 수 있다.
- 충돌이 나면 worktree를 삭제하지 말고, 충돌 파일과 다음 조치를 보고한다.

5. worktree 정리는 성공 조건을 모두 만족할 때만 한다.
- 현재 repo root가 primary worktree가 아니다.
- 작업 커밋이 대상 브랜치에 반영되었다.
- 반영 대상 worktree와 현재 worktree에 남은 unstaged/staged 변경이 없다.
- 사용자가 "워크트리 정리", "작업트리 지워줘", "원래 브랜치에 반영하고 정리"처럼
  정리를 요청했거나, 현재 경로가 명백한 Codex 임시 worktree다.

위 조건 중 하나라도 애매하면 worktree를 남겨 두고 이유를 보고한다.

## 커밋 메시지

- 사용자가 메시지를 주면 그 의도를 보존한다.
- 메시지가 없으면 diff를 보고 한국어 한 줄 요약을 만든다.
- 여러 도메인이 섞이면 한 커밋으로 묶지 말고 범위를 나눌 수 있는지 먼저 확인한다.

## 가드레일

- 사용자가 요청하지 않으면 push하지 않는다.
- 대상 브랜치가 애매하면 원래 브랜치라고 추측하지 않는다.
- primary worktree는 자동 삭제하지 않는다.
- 충돌, 실패한 검증, 남은 dirty state가 있으면 worktree를 삭제하지 않는다.
- detached 상태에서 만든 커밋은 대상 브랜치 반영 전까지 반드시 브랜치나 태그로 붙잡아 둔다.
- 관련 없는 사용자 변경을 스테이징하거나 되돌리지 않는다.
- `git reset --hard`, `git clean`, 광범위한 `rm -rf`는 사용자가 명시적으로 요청하지 않으면 쓰지 않는다.

## 최종 보고

최종 보고에는 다음을 짧게 포함한다.

- 커밋이 만들어진 브랜치와 커밋 해시.
- 대상 브랜치 반영 여부.
- worktree 삭제 여부와 그 이유.
- 실행한 검증 명령.
- 남은 변경이나 사용자가 이어서 결정해야 할 사항.

## 사용 예시

- `$worktree-commit으로 지금 작업 내용을 커밋해줘.`
- `$worktree-commit으로 이 worktree 변경을 원래 브랜치에 반영하고 정리해줘.`
- `$worktree-commit으로 현재 detached 작업을 feat/map-ui 브랜치에 커밋해줘.`
