# Story Import - Edge Functions 아키텍처

## 개요

스토리 임포트 시스템을 Supabase Edge Functions로 간소화했습니다. Trigger.dev 대신 직접 Edge Functions를 체인 호출하는 구조입니다.

## Edge Functions

### 1. story-import-intake

**역할**: 외부 요청을 받아 import job을 생성하고 validate 함수 호출

**입력**:
```json
{
  "sourceName": "my-stories.json",
  "stories": [...],
  "note": "optional note",
  "externalRequester": {
    "name": "John Doe",
    "email": "john@example.com"
  }
}
```

**출력**:
```json
{
  "ok": true,
  "jobId": "uuid",
  "status": "received",
  "sourceStoragePath": "raw/uuid/my-stories.json"
}
```

**다음 단계**: 자동으로 `story-import-validate` 호출

---

### 2. story-import-validate

**역할**: JSON 형식 검증 및 중복 코드 체크

**입력**:
```json
{
  "jobId": "uuid",
  "sourceStoragePath": "raw/uuid/my-stories.json"
}
```

**검증 항목**:
- JSON이 배열인지 확인
- 각 항목이 객체인지 확인
- code 필드 중복 체크

**출력**:
```json
{
  "ok": true,
  "storyCount": 10
}
```

**Job 상태 변경**: `received` → `validated` 또는 `failed_validation`

**다음 단계**:
- ✅ 성공 시: `validated` 상태로 대기 (수동 build 트리거 필요)
- ❌ 실패 시: `failed_validation` 상태로 종료

---

### 3. story-import-promote

**역할**: 승인된 import job의 SQL을 실행하여 데이터베이스에 반영

**입력**:
```json
{
  "jobId": "uuid",
  "seedSqlPath": "build/uuid/200_stories_seed.sql",
  "environment": "production",
  "approvedBy": "user-id"
}
```

**동작**:
1. `ENABLE_STORY_IMPORT_PROMOTE` 환경변수 확인
2. Storage에서 seed SQL 다운로드
3. SQL 실행 (트랜잭션 포함)
4. 성공 시 job 상태를 `promoted`로 변경

**출력**:
```json
{
  "ok": true,
  "skipped": false,
  "environment": "production",
  "rowsAffected": 150
}
```

**Job 상태 변경**: `approved` → `promoted` 또는 `failed`

---

## 워크플로우

```
1. 외부 요청
   └─> intake (Edge Function)
       ├─> import_jobs 테이블에 job 생성
       ├─> Storage에 JSON 업로드
       └─> validate 함수 호출 (비동기)

2. 검증
   └─> validate (Edge Function)
       ├─> JSON 형식 및 중복 체크
       └─> Job 상태: validated 또는 failed_validation

3. 빌드 (수동 트리거 필요)
   └─> GitHub Actions 또는 로컬 스크립트
       ├─> tools/prepare_story_import_job.py 실행
       ├─> Seed SQL 생성
       └─> Storage에 업로드

4. 검토 및 승인 (수동)
   └─> 관리자가 diff 확인 후 승인

5. 반영
   └─> promote (Edge Function)
       ├─> Seed SQL 다운로드
       ├─> SQL 실행
       └─> Job 상태: promoted
```

---

## 장기 작업 처리

### Build Bundle (Python 스크립트)

Edge Function은 실행시간 제한(50~150초)이 있어 Python 스크립트 실행이 어렵습니다.

**옵션 1: GitHub Actions (권장)**

`.github/workflows/story-import-build.yml`:
```yaml
name: Story Import Build

on:
  workflow_dispatch:
    inputs:
      jobId:
        required: true
        type: string

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Download input JSON
        run: |
          # Supabase CLI로 storage에서 다운로드

      - name: Run prepare script
        run: |
          python tools/prepare_story_import_job.py \
            --input-json input.json \
            --job-id ${{ inputs.jobId }}

      - name: Upload artifacts
        run: |
          # Supabase CLI로 storage에 업로드
```

**트리거 방법**:
```bash
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/OWNER/REPO/actions/workflows/story-import-build.yml/dispatches \
  -d '{"ref":"main","inputs":{"jobId":"uuid"}}'
```

**옵션 2: 로컬 실행**

관리자가 로컬에서 직접 실행:
```bash
# 1. JSON 다운로드
supabase storage download import-jobs raw/uuid/stories.json

# 2. 빌드 스크립트 실행
python tools/prepare_story_import_job.py \
  --input-json stories.json \
  --job-id uuid

# 3. 결과 업로드
supabase storage upload import-jobs build/uuid/200_stories_seed.sql
```

---

### Generate Media (이미지 생성)

이미지 생성은 시간이 오래 걸리므로 별도 처리:

**옵션 1: GitHub Actions + Vertex AI**
```yaml
name: Generate Story Media

on:
  workflow_dispatch:
    inputs:
      jobId:
        required: true

jobs:
  generate:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - name: Generate avatars
        run: python tools/generate_avatars_vertex.py

      - name: Generate story scenes
        run: python tools/generate_event_story_images_vertex.py

      - name: Generate thumbnails
        run: python tools/generate_runtime_thumbnails.py
```

**옵션 2: 별도 Cloud Run Job**

긴 작업은 Cloud Run Job으로 분리:
```bash
gcloud run jobs create story-media-gen \
  --image gcr.io/PROJECT/story-media-gen \
  --tasks 1 \
  --max-retries 3
```

---

## 환경 변수

### Supabase Edge Functions

```bash
# .env
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGc...
DEPLOYMENT_ENVIRONMENT=production
ENABLE_STORY_IMPORT_PROMOTE=true  # promote 함수 활성화
```

### 배포

```bash
# 모든 함수 배포
supabase functions deploy story-import-intake
supabase functions deploy story-import-validate
supabase functions deploy story-import-promote

# 환경변수 설정
supabase secrets set ENABLE_STORY_IMPORT_PROMOTE=true
```

---

## 보안

### 인증

- intake: 선택적 Bearer token (user identity 추적용)
- validate, promote: Service Role Key 필요

### 권한

```sql
-- import_jobs 테이블은 서비스 키로만 접근
alter table import_jobs enable row level security;

create policy "Service role only"
on import_jobs
for all
to service_role
using (true);
```

---

## 모니터링

### Job 상태 확인

```sql
select
  id,
  status,
  source_name,
  requested_at,
  validated_at,
  approved_at,
  promoted_at,
  metadata
from import_jobs
order by requested_at desc
limit 10;
```

### 실패한 Job 조회

```sql
select
  id,
  status,
  source_name,
  metadata->>'validationError' as error,
  metadata->>'promotionError' as promo_error
from import_jobs
where status in ('failed_validation', 'failed')
order by requested_at desc;
```

---

## 마이그레이션 가이드

### Trigger.dev에서 전환

1. **코드 삭제**:
   ```bash
   rm -rf automation/trigger
   ```

2. **Edge Functions 배포**:
   ```bash
   supabase functions deploy story-import-intake
   supabase functions deploy story-import-validate
   supabase functions deploy story-import-promote
   ```

3. **환경변수 제거**:
   - `TRIGGER_IMPORT_WEBHOOK_URL` 삭제
   - `ENABLE_STORY_IMPORT_PROMOTE` 추가

4. **Storage bucket 확인**:
   ```sql
   -- import-jobs bucket이 있는지 확인
   select * from storage.buckets where name = 'import-jobs';

   -- 없으면 생성
   insert into storage.buckets (id, name, public)
   values ('import-jobs', 'import-jobs', false);
   ```

---

## 다음 단계

### 단기 (필수)
- [ ] promote 함수의 SQL 실행 로직 구현 완료
- [ ] GitHub Actions workflow 작성
- [ ] 로컬 테스트 환경 구축

### 중기 (권장)
- [ ] Discord bot 통합 (검토 알림)
- [ ] Webhook for approval (자동 approve API)
- [ ] Rollback 함수 구현

### 장기 (선택)
- [ ] Web UI for import management
- [ ] Automated testing pipeline
- [ ] Metrics and monitoring dashboard
