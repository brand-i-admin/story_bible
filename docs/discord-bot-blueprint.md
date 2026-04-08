# Discord Bot Blueprint

이 문서는 story import 운영용 Discord bot의 최소 책임을 정리한 문서다.

핵심 원칙:

- Discord는 운영자 알림/호출용
- 실제 검토 UI 대체용이 아님
- 실제 반영 로직은 Trigger.dev + GitHub Actions + 내부 review UI가 담당

## 권장 채널

- `#story-imports`
  - 새 job / build_ready / promoted 알림
- `#story-review`
  - 승인 필요 알림
- `#story-import-failures`
  - validation 실패 / promote 실패 알림

## Bot이 해야 할 일

### 1. 상태 알림

다음 상태에 대해 메시지를 전송:

- `received`
- `validated`
- `build_ready`
- `approved`
- `promoted`
- `failed`

### 2. 링크 제공

메시지에 포함할 것:

- `jobId`
- 제출자 또는 requester 정보
- added / changed / unchanged 수
- 내부 review 링크
- promote 결과 요약

### 3. 상태 조회 커맨드

권장 slash commands:

- `/job-status <job_id>`
- `/job-latest`
- `/job-artifacts <job_id>`

Discord 공식 상호작용/명령 문서:

- Application Commands: https://docs.discord.com/developers/interactions/application-commands
- Interactions overview: https://docs.discord.com/developers/platform/interactions

## Bot이 하지 않는 게 좋은 일

- 긴 diff 전체 렌더링
- JSON 수정
- SQL 직접 승인
- 대량 이미지 검수
- production 반영 실행

## 메시지 예시

```text
[story-import] build_ready
job: job_20260408_xxx
requester: Alice (Example Org)
added: 1
changed: 2
review: https://admin.example.com/import-jobs/job_20260408_xxx
```

## 구현 메모

- 첫 단계는 webhook 기반 단순 알림만으로 충분하다.
- slash command는 나중에 상태 조회 위주로 붙이는 게 안전하다.
- 승인 버튼을 Discord 안에 직접 넣기보다 내부 review UI 링크를 보내는 방식이 더 단순하고 안정적이다.
