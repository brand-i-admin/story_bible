# Trigger Automation Workspace

이 작업공간은 story import 파이프라인을 Trigger.dev로 오케스트레이션하기 위한 최소 Node/TypeScript workspace다.

핵심 역할:

- `import_jobs` 상태 전이 관리
- 기존 Python 스크립트 실행 orchestration
- Discord 알림
- 승인 대기 토큰 생성
- promote / rollback 전 단계 orchestration

## 시작

```bash
cd automation/trigger
npm install
cp .env.example .env
npx trigger.dev@latest dev
```

## 중요한 전제

- 이 workspace는 기존 Python 스크립트를 재사용한다.
- 정식 canonical asset 반영은 promote 단계에서만 해야 한다.
- Discord는 알림용으로만 사용하고, 실제 리뷰/승인은 내부 UI 기준으로 진행하는 것이 안전하다.
- 기본값으로 media 생성 / promote task는 비활성화되어 있다.
  - `ENABLE_STORY_IMPORT_MEDIA_TASKS=true`
  - `ENABLE_STORY_IMPORT_PROMOTE=true`
  를 켜야 실제 단계가 실행된다.
