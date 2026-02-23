create extension if not exists pgcrypto;
create extension if not exists vector;

-- Single source of truth for local bootstrap before first production release.
-- Run this file directly to recreate schema + seed data end-to-end.
-- Supabase migration files may lag behind while this mode is enabled.

-- Re-initialize safely when rerunning this script locally or via CI.
-- We keep this as "drop then recreate" for predictable bootstrap.
drop table if exists search_embeddings cascade;
drop table if exists user_event_progress cascade;
drop table if exists quiz_questions cascade;
drop table if exists event_bible_refs cascade;
drop table if exists bible_verses cascade;
drop table if exists event_persons cascade;
drop table if exists person_eras cascade;
drop table if exists events cascade;
drop table if exists persons cascade;
drop table if exists eras cascade;

create table if not exists eras (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  display_order int not null,
  start_year int,
  end_year int,
  theme_color text,
  map_center_lat double precision,
  map_center_lng double precision,
  map_zoom numeric(4,2),
  created_at timestamptz not null default now()
);

create table if not exists persons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  tagline text,
  avatar_url text,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists person_eras (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references persons(id) on delete cascade,
  era_id uuid not null references eras(id) on delete cascade,
  display_order int not null default 0,
  unique (person_id, era_id)
);

create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  era_id uuid not null references eras(id),
  title text not null,
  summary text,
  short_text text,
  story text,
  short_story text,
  start_year int,
  end_year int,
  time_sort_key bigint not null,
  time_precision text not null default 'approx',
  place_name text,
  lat double precision,
  lng double precision,
  is_major boolean not null default false,
  video_url text,
  thumb_url text,
  search_text text,
  created_at timestamptz not null default now()
);

create table if not exists event_persons (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  person_id uuid not null references persons(id) on delete cascade,
  role text,
  person_sequence int,
  unique (event_id, person_id)
);

create table if not exists event_bible_refs (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  book text not null,
  chapter_start int not null,
  verse_start int not null,
  chapter_end int,
  verse_end int,
  display_text text not null
);

create table if not exists bible_verses (
  translation text not null default 'KRV',
  testament text not null check (testament in ('old', 'new')),
  book_no smallint not null check (book_no between 1 and 66),
  book_name text not null,
  chapter_no smallint not null check (chapter_no > 0),
  verse_no smallint not null check (verse_no > 0),
  verse_text text not null,
  primary key (translation, book_no, chapter_no, verse_no)
);

create table if not exists quiz_questions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  question text not null,
  choice_a text not null,
  choice_b text not null,
  choice_c text not null,
  choice_d text,
  answer_index int not null check (answer_index between 0 and 3),
  explanation text,
  display_order int not null default 0
);

create table if not exists user_event_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  event_id uuid not null references events(id) on delete cascade,
  is_completed boolean not null default false,
  score int not null default 0,
  xp_earned int not null default 0,
  completed_at timestamptz,
  unique (user_id, event_id)
);

create table if not exists search_embeddings (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('event', 'person')),
  entity_id uuid not null,
  chunk_text text not null,
  embedding vector(1536) not null,
  updated_at timestamptz not null default now()
);

create index if not exists idx_events_era_time on events (era_id, time_sort_key);
create index if not exists idx_event_persons_person_seq on event_persons (person_id, person_sequence);
create index if not exists idx_event_persons_person_event on event_persons (person_id, event_id);
create index if not exists idx_progress_user_completed on user_event_progress (user_id, is_completed);
create unique index if not exists uidx_quiz_event_order on quiz_questions (event_id, display_order);
create index if not exists idx_embed_ivfflat on search_embeddings using ivfflat (embedding vector_cosine_ops);
create unique index if not exists idx_event_bible_refs_unique on event_bible_refs (event_id, display_text);
create index if not exists idx_bible_verses_lookup on bible_verses (translation, book_no, chapter_no, verse_no);
create index if not exists idx_bible_verses_book_name on bible_verses (translation, book_name, chapter_no, verse_no);

-- -----------------------------------------------------------------------------
-- Public read access + RLS policies
-- -----------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

grant select on table eras to anon, authenticated;
grant select on table persons to anon, authenticated;
grant select on table person_eras to anon, authenticated;
grant select on table events to anon, authenticated;
grant select on table event_persons to anon, authenticated;
grant select on table event_bible_refs to anon, authenticated;
grant select on table bible_verses to anon, authenticated;
grant select on table quiz_questions to anon, authenticated;

grant select, insert, update on table user_event_progress to authenticated;

alter table eras enable row level security;
alter table persons enable row level security;
alter table person_eras enable row level security;
alter table events enable row level security;
alter table event_persons enable row level security;
alter table event_bible_refs enable row level security;
alter table bible_verses enable row level security;
alter table quiz_questions enable row level security;
alter table user_event_progress enable row level security;

drop policy if exists eras_read_all on eras;
create policy eras_read_all on eras for select using (true);

drop policy if exists persons_read_all on persons;
create policy persons_read_all on persons for select using (true);

drop policy if exists person_eras_read_all on person_eras;
create policy person_eras_read_all on person_eras for select using (true);

drop policy if exists events_read_all on events;
create policy events_read_all on events for select using (true);

drop policy if exists event_persons_read_all on event_persons;
create policy event_persons_read_all on event_persons for select using (true);

drop policy if exists event_bible_refs_read_all on event_bible_refs;
create policy event_bible_refs_read_all on event_bible_refs for select using (true);

drop policy if exists bible_verses_read_all on bible_verses;
create policy bible_verses_read_all on bible_verses for select using (true);

drop policy if exists quiz_questions_read_all on quiz_questions;
create policy quiz_questions_read_all on quiz_questions for select using (true);

drop policy if exists user_event_progress_read_own on user_event_progress;
create policy user_event_progress_read_own on user_event_progress
for select using (auth.uid() = user_id);

drop policy if exists user_event_progress_write_own on user_event_progress;
create policy user_event_progress_write_own on user_event_progress
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- Seed: eras
-- -----------------------------------------------------------------------------
insert into eras (
  code,
  name,
  display_order,
  start_year,
  end_year,
  theme_color,
  map_center_lat,
  map_center_lng,
  map_zoom
)
values
  ('era_primeval', '원역사', 1, -4000, -2000, '#6E4A2B', 33.00, 44.00, 4.80),
  ('era_patriarch', '족장 시대', 2, -2166, -1805, '#8B5A2B', 31.50, 35.20, 5.40),
  ('era_exodus', '출애굽 시대', 3, -1446, -1406, '#A66A2C', 29.50, 34.50, 5.20),
  ('era_judges', '사사 시대', 4, -1406, -1050, '#7A5C3A', 31.80, 35.10, 5.40),
  ('era_monarchy', '왕정 시대', 5, -1050, -586, '#73533D', 31.90, 35.20, 5.30),
  ('era_exile_return', '포로 및 포로 후기 시대', 6, -586, -430, '#5D4B3F', 32.20, 38.30, 4.70)
;

-- -----------------------------------------------------------------------------
-- Seed: persons
-- -----------------------------------------------------------------------------
insert into persons (
  code,
  name,
  tagline,
  avatar_url,
  description,
  is_active
)
values
  ('adam', '아담', '첫 사람', 'assets/avatars/adam.png', '창조와 타락 이야기의 시작점이 되는 인물', true),
  ('noah', '노아', '방주의 사람', 'assets/avatars/noah.png', '홍수 심판 속에서 순종으로 방주를 준비한 인물', true),
  ('abraham', '아브라함', '믿음의 조상', 'assets/avatars/abraham.png', '약속의 땅으로 부르심을 받은 족장', true),
  ('isaac', '이삭', '약속의 아들', 'assets/avatars/isaac.png', '약속을 이어받은 두 번째 족장', true),
  ('jacob', '야곱', '이스라엘', 'assets/avatars/jacob.png', '열두 지파의 기초가 된 인물', true),
  ('joseph', '요셉', '섭리의 행정가', 'assets/avatars/joseph.png', '애굽 총리로 가문을 보존한 인물', true),
  ('moses', '모세', '출애굽의 지도자', 'assets/avatars/moses.png', '애굽에서 해방을 이끈 선지자', true),
  ('aaron', '아론', '첫 대제사장', 'assets/avatars/aaron.png', '모세와 함께 백성을 인도한 제사장', true),
  ('joshua', '여호수아', '정복과 분배의 지도자', 'assets/avatars/joshua.png', '가나안 정착을 이끈 후계자', true),
  ('judges', '사사들', '구원과 반복의 시대', 'assets/avatars/judges.png', '이스라엘을 순환적으로 구원한 지도자들', true),
  ('samuel', '사무엘', '전환기의 선지자', 'assets/avatars/samuel.png', '사사 시대에서 왕정 시대로 넘어가는 연결자', true),
  ('saul', '사울', '이스라엘의 첫 왕', 'assets/avatars/saul.png', '초대 왕으로 세워졌으나 불순종으로 몰락한 인물', true),
  ('david', '다윗', '언약의 왕', 'assets/avatars/david.png', '예루살렘을 중심으로 왕국을 세운 왕', true),
  ('solomon', '솔로몬', '성전 건축자', 'assets/avatars/solomon.png', '지혜와 성전 건축으로 대표되는 왕', true),
  ('zerubbabel', '스룹바벨', '귀환 공동체의 총독', 'assets/avatars/zerubbabel.png', '포로 귀환 후 성전 재건을 주도한 인물', true),
  ('ezra', '에스라', '율법 학사', 'assets/avatars/ezra.png', '말씀 개혁을 이끈 지도자', true),
  ('nehemiah', '느헤미야', '성벽 재건자', 'assets/avatars/nehemiah.png', '예루살렘 성벽 재건과 공동체 갱신을 주도한 인물', true)
;

-- -----------------------------------------------------------------------------
-- Seed: person_eras
-- -----------------------------------------------------------------------------
with seed_person_eras (person_code, era_code, display_order) as (
  values
    ('adam', 'era_primeval', 1),
    ('noah', 'era_primeval', 2),
    ('abraham', 'era_patriarch', 1),
    ('isaac', 'era_patriarch', 2),
    ('jacob', 'era_patriarch', 3),
    ('joseph', 'era_patriarch', 4),
    ('moses', 'era_exodus', 1),
    ('aaron', 'era_exodus', 2),
    ('joshua', 'era_judges', 1),
    ('judges', 'era_judges', 2),
    ('samuel', 'era_judges', 3),
    ('saul', 'era_monarchy', 1),
    ('david', 'era_monarchy', 2),
    ('solomon', 'era_monarchy', 3),
    ('zerubbabel', 'era_exile_return', 1),
    ('ezra', 'era_exile_return', 2),
    ('nehemiah', 'era_exile_return', 3)
)
insert into person_eras (person_id, era_id, display_order)
select
  p.id,
  e.id,
  s.display_order
from seed_person_eras s
join persons p on p.code = s.person_code
join eras e on e.code = s.era_code
;

-- -----------------------------------------------------------------------------
-- Seed: events
-- -----------------------------------------------------------------------------
with seed_events (
  code,
  era_code,
  title,
  summary,
  short_text,
  start_year,
  end_year,
  time_precision,
  place_name,
  lat,
  lng,
  is_major,
  search_text
) as (
  values
    ('evt_pri_adam_creation', 'era_primeval', '아담의 창조', '하나님이 사람을 창조하고 에덴을 맡기심', '인류 이야기의 시작으로 하나님 형상을 받은 존재의 사명이 주어진다.', -4000, -4000, 'approx', '에덴(추정)', 33.30, 44.40, true, '아담 창조 에덴 창세기 1장 2장'),
    ('evt_pri_adam_fall', 'era_primeval', '타락', '선악과 사건으로 죄가 세상에 들어옴', '불순종으로 관계가 깨지고 인류의 고난이 시작된다.', -3999, -3999, 'approx', '에덴(추정)', 33.30, 44.40, true, '아담 타락 선악과 창세기 3장'),
    ('evt_pri_adam_cain_abel', 'era_primeval', '가인과 아벨', '형제 갈등과 첫 살인이 발생함', '죄의 확산이 가정과 사회로 번져가는 장면이다.', -3985, -3985, 'approx', '에덴 동쪽(추정)', 33.10, 44.70, true, '아담 가인 아벨 창세기 4장'),
    ('evt_pri_noah_ark', 'era_primeval', '방주 준비', '노아가 하나님의 명령대로 방주를 준비함', '심판 전 긴 시간의 순종이 강조되는 사건이다.', -2500, -2500, 'approx', '아라랏 인근(추정)', 39.70, 44.30, true, '노아 방주 창세기 6장'),
    ('evt_pri_noah_flood', 'era_primeval', '홍수 심판', '홍수로 세상이 심판받고 방주만 보존됨', '악의 심판과 구원의 대비가 나타난다.', -2498, -2498, 'approx', '아라랏 인근(추정)', 39.70, 44.30, true, '노아 홍수 창세기 7장'),
    ('evt_pri_noah_covenant', 'era_primeval', '무지개 언약', '홍수 후 하나님이 다시는 같은 심판을 하지 않겠다고 약속함', '무지개는 자비와 언약의 표징으로 제시된다.', -2497, -2497, 'approx', '아라랏 인근(추정)', 39.70, 44.30, true, '노아 무지개 언약 창세기 9장'),

    ('evt_pat_abraham_call', 'era_patriarch', '아브라함의 부르심', '아브람이 본토를 떠나 약속의 땅으로 이동함', '믿음으로 떠나는 여정의 시작이다.', -2091, -2091, 'approx', '하란', 36.86, 39.03, true, '아브라함 부르심 하란 창세기 12장'),
    ('evt_pat_abraham_covenant', 'era_patriarch', '횃불 언약', '하나님이 아브라함에게 땅과 자손의 언약을 확증함', '언약의 주도권이 하나님께 있음을 보여준다.', -2085, -2085, 'approx', '가나안(헤브론)', 31.53, 35.10, true, '아브라함 언약 창세기 15장'),
    ('evt_pat_isaac_birth', 'era_patriarch', '이삭의 출생', '약속의 아들 이삭이 태어남', '불가능해 보이던 약속이 역사 안에서 성취된다.', -2066, -2066, 'approx', '브엘세바', 31.25, 34.79, true, '아브라함 이삭 출생 창세기 21장'),
    ('evt_pat_abraham_moriah', 'era_patriarch', '모리아 사건', '아브라함이 이삭을 드리라는 시험을 받음', '순종과 신뢰의 정점으로 기억되는 사건이다.', -2050, -2050, 'approx', '모리아(예루살렘 인근)', 31.78, 35.23, true, '아브라함 이삭 제사 창세기 22장'),
    ('evt_pat_isaac_wells', 'era_patriarch', '그랄의 우물 다툼', '이삭이 우물을 파며 갈등을 겪고 평화를 찾음', '약속 계승자의 인내와 화평이 드러난다.', -2000, -2000, 'approx', '그랄', 31.21, 34.57, true, '이삭 우물 그랄 창세기 26장'),
    ('evt_pat_isaac_blessing', 'era_patriarch', '야곱 축복', '이삭이 야곱에게 장자의 축복을 전함', '가문의 언약 계승이 다음 세대로 넘어간다.', -1970, -1970, 'approx', '브엘세바', 31.25, 34.79, true, '이삭 야곱 축복 창세기 27장'),
    ('evt_pat_jacob_bethel', 'era_patriarch', '벧엘의 꿈', '야곱이 벧엘에서 사닥다리 환상을 봄', '도망자의 길에서 언약의 약속을 다시 확인한다.', -1935, -1935, 'approx', '벧엘', 31.94, 35.22, true, '야곱 벧엘 꿈 창세기 28장'),
    ('evt_pat_jacob_haran', 'era_patriarch', '하란 체류', '야곱이 하란에서 라반을 섬기며 가정을 이룸', '긴 기다림 끝에 큰 가문이 형성된다.', -1920, -1910, 'approx', '하란', 36.86, 39.03, true, '야곱 하란 라반 창세기 29장 30장'),
    ('evt_pat_jacob_jabbok', 'era_patriarch', '얍복 강 씨름', '야곱이 하나님과 씨름 후 이스라엘로 불리게 됨', '정체성과 사명이 전환되는 장면이다.', -1908, -1908, 'approx', '얍복 강', 32.16, 35.62, true, '야곱 얍복 이스라엘 창세기 32장'),
    ('evt_pat_jacob_egypt_migration', 'era_patriarch', '야곱 가문의 애굽 이주', '기근 속에서 야곱 가문이 애굽으로 이동함', '족장 시대가 마무리되고 다음 시대의 배경이 형성된다.', -1876, -1876, 'approx', '고센', 30.98, 31.84, true, '야곱 요셉 애굽 이주 창세기 46장'),
    ('evt_pat_joseph_sold', 'era_patriarch', '요셉이 팔려감', '형들의 시기로 요셉이 애굽에 팔려감', '고난이 이후 구원의 통로로 전환되는 출발점이다.', -1898, -1898, 'approx', '도단', 32.45, 35.30, true, '요셉 형제 도단 애굽 창세기 37장'),
    ('evt_pat_joseph_rise', 'era_patriarch', '요셉의 총리 등극', '요셉이 애굽의 총리가 되어 기근에 대비함', '하나님 섭리 아래 준비된 리더십이 드러난다.', -1885, -1885, 'approx', '애굽(멤피스)', 29.85, 31.25, true, '요셉 총리 애굽 창세기 41장'),
    ('evt_pat_joseph_reconcile', 'era_patriarch', '형제와의 화해', '요셉이 형제들에게 자신을 밝히고 화해함', '용서와 회복이 가족 공동체를 다시 세운다.', -1877, -1877, 'approx', '고센', 30.98, 31.84, true, '요셉 화해 형제 창세기 45장'),

    ('evt_ex_moses_burning_bush', 'era_exodus', '떨기나무 소명', '모세가 호렙산에서 소명을 받음', '출애굽 사명의 공식적인 시작점이다.', -1446, -1446, 'approx', '호렙산', 28.54, 33.97, true, '모세 떨기나무 호렙 출애굽기 3장'),
    ('evt_ex_plagues_passover', 'era_exodus', '열 재앙과 유월절', '애굽에 재앙이 임하고 유월절이 제정됨', '해방 사건의 결정적 분기점이다.', -1446, -1446, 'approx', '람세스', 30.81, 31.84, true, '모세 아론 열재앙 유월절 출애굽기 7장 12장'),
    ('evt_ex_red_sea_crossing', 'era_exodus', '홍해 도하', '이스라엘이 바다를 건너 구원을 경험함', '구원과 심판이 동시에 드러나는 사건이다.', -1446, -1446, 'approx', '홍해 연안(추정)', 29.97, 32.55, true, '모세 홍해 출애굽기 14장'),
    ('evt_ex_sinai_covenant', 'era_exodus', '시내산 언약', '율법이 주어지고 언약 공동체가 세워짐', '이스라엘 정체성의 기초를 형성한 사건이다.', -1445, -1445, 'approx', '시내산', 28.54, 33.97, true, '모세 아론 시내산 언약 출애굽기 19장 20장'),
    ('evt_ex_wilderness_serpent', 'era_exodus', '광야의 놋뱀', '불평하는 백성 가운데 놋뱀 사건이 일어남', '심판 중에도 회복의 길이 제시된다.', -1440, -1440, 'approx', '가데스 인근 광야', 30.61, 34.79, true, '모세 놋뱀 민수기 21장'),
    ('evt_ex_moses_death_nebo', 'era_exodus', '모세의 마지막', '모세가 느보산에서 약속의 땅을 바라보고 생을 마침', '출애굽 리더십의 한 시대가 종료된다.', -1406, -1406, 'approx', '느보산', 31.77, 35.73, true, '모세 죽음 느보산 신명기 34장'),
    ('evt_ex_aaron_golden_calf', 'era_exodus', '금송아지 사건', '백성이 금송아지를 만들고 아론이 책임의 중심에 섬', '중보와 거룩의 긴장이 드러나는 사건이다.', -1445, -1445, 'approx', '시내산', 28.54, 33.97, true, '아론 금송아지 출애굽기 32장'),
    ('evt_ex_aaron_rod', 'era_exodus', '아론의 싹 난 지팡이', '제사장 권위를 확인하는 표징이 주어짐', '공동체 질서와 리더십 정당성이 확인된다.', -1443, -1443, 'approx', '가데스', 30.61, 34.79, true, '아론 지팡이 민수기 17장'),
    ('evt_ex_aaron_death_hor', 'era_exodus', '아론의 죽음', '아론이 호르산에서 생을 마치고 직분이 계승됨', '세대 전환과 사명의 계승을 보여준다.', -1406, -1406, 'approx', '호르산', 30.32, 35.44, true, '아론 죽음 민수기 20장'),

    ('evt_jdg_joshua_jordan_crossing', 'era_judges', '요단강 도하', '여호수아가 백성을 이끌고 요단을 건넘', '약속의 땅 진입을 알리는 사건이다.', -1406, -1406, 'approx', '요단강', 31.84, 35.55, true, '여호수아 요단강 수 3장'),
    ('evt_jdg_joshua_jericho', 'era_judges', '여리고 함락', '여리고 성이 무너지고 첫 정복이 이뤄짐', '순종의 전술이 승리로 이어진 상징적 사건이다.', -1406, -1406, 'approx', '여리고', 31.87, 35.44, true, '여호수아 여리고 수 6장'),
    ('evt_jdg_joshua_shechem_covenant', 'era_judges', '세겜 언약 갱신', '여호수아가 세겜에서 언약을 다시 세움', '정복 이후 신앙 정체성을 재확인한다.', -1390, -1390, 'approx', '세겜', 32.21, 35.28, true, '여호수아 세겜 언약 수 24장'),
    ('evt_jdg_cycle_begins', 'era_judges', '사사 시대의 반복', '배교-압제-부르짖음-구원의 순환이 시작됨', '사사기의 신학적 패턴을 보여주는 핵심 사건이다.', -1375, -1375, 'approx', '가나안 중부', 31.80, 35.10, true, '사사 시대 반복 사사기 2장'),
    ('evt_jdg_deborah_victory', 'era_judges', '드보라와 바락의 승리', '드보라와 바락이 시스라를 물리침', '하나님의 구원이 다양한 리더를 통해 임한다.', -1240, -1240, 'approx', '다볼산', 32.69, 35.39, true, '드보라 바락 시스라 사사기 4장'),
    ('evt_jdg_gideon_victory', 'era_judges', '기드온의 300 용사', '기드온이 소수 병력으로 미디안을 격파함', '전쟁의 승패가 숫자가 아닌 하나님께 달려 있음을 보여준다.', -1160, -1160, 'approx', '하롯 샘', 32.55, 35.37, true, '기드온 300 사사기 7장'),
    ('evt_jdg_samson_finale', 'era_judges', '삼손의 마지막', '삼손이 마지막 힘으로 블레셋을 무너뜨림', '불완전한 사사의 삶 속에서도 구원이 나타난다.', -1105, -1105, 'approx', '가사', 31.50, 34.47, true, '삼손 블레셋 사사기 16장'),
    ('evt_jdg_samuel_call', 'era_judges', '사무엘의 소명', '소년 사무엘이 하나님의 부르심을 들음', '말씀 중심 리더십의 출발점이다.', -1105, -1105, 'approx', '실로', 32.05, 35.29, true, '사무엘 소명 사무엘상 3장'),
    ('evt_jdg_samuel_mizpah', 'era_judges', '미스바 회개 운동', '사무엘이 미스바에서 회개와 승리를 이끔', '공동체 회복이 국가적 전환으로 이어진다.', -1080, -1080, 'approx', '미스바', 31.88, 35.16, true, '사무엘 미스바 사무엘상 7장'),
    ('evt_jdg_samuel_anoints_saul', 'era_judges', '사울 기름부음', '사무엘이 사울에게 기름을 부어 왕정 전환을 준비함', '사사 시대에서 왕정 시대로 넘어가는 경계 사건이다.', -1050, -1050, 'approx', '라마', 31.87, 35.20, true, '사무엘 사울 기름부음 사무엘상 10장'),

    ('evt_mon_saul_jabesh_victory', 'era_monarchy', '야베스 구원', '사울이 야베스 길르앗을 구원해 왕권을 확립함', '왕정 초기에 지도력이 공적으로 인정받는 사건이다.', -1049, -1049, 'approx', '야베스 길르앗', 32.35, 35.62, true, '사울 야베스 사무엘상 11장'),
    ('evt_mon_saul_rejected', 'era_monarchy', '사울의 폐위 선언', '사울의 불순종으로 왕권이 다른 이에게 넘어갈 것이 선언됨', '순종 없는 통치의 한계를 보여준다.', -1030, -1030, 'approx', '길갈', 31.84, 35.45, true, '사울 불순종 사무엘상 15장'),
    ('evt_mon_saul_gilboa_death', 'era_monarchy', '길보아 전사', '사울이 길보아 전투에서 생을 마침', '첫 왕의 시대가 비극적으로 막을 내린다.', -1010, -1010, 'approx', '길보아 산', 32.48, 35.39, true, '사울 길보아 사무엘상 31장'),
    ('evt_mon_david_anointed', 'era_monarchy', '다윗 기름부음', '다윗이 베들레헴에서 기름부음을 받음', '하나님 마음에 합한 왕의 이야기가 시작된다.', -1025, -1025, 'approx', '베들레헴', 31.70, 35.20, true, '다윗 기름부음 사무엘상 16장'),
    ('evt_mon_david_jerusalem', 'era_monarchy', '예루살렘 정복', '다윗이 예루살렘을 점령해 수도로 삼음', '통일 왕국의 정치/신앙 중심이 확립된다.', -1003, -1003, 'approx', '예루살렘', 31.78, 35.23, true, '다윗 예루살렘 사무엘하 5장'),
    ('evt_mon_david_covenant', 'era_monarchy', '다윗 언약', '하나님이 다윗의 왕위를 견고히 하겠다고 약속함', '메시아 계보의 핵심 언약으로 이어진다.', -1000, -1000, 'approx', '예루살렘', 31.78, 35.23, true, '다윗 언약 사무엘하 7장'),
    ('evt_mon_solomon_enthroned', 'era_monarchy', '솔로몬 즉위', '솔로몬이 왕으로 세워져 통치를 시작함', '왕권 이양과 새 시대의 시작을 보여준다.', -970, -970, 'approx', '예루살렘', 31.78, 35.23, true, '솔로몬 즉위 열왕기상 1장'),
    ('evt_mon_solomon_temple', 'era_monarchy', '성전 봉헌', '솔로몬이 성전을 완공하고 봉헌함', '이스라엘 예배 중심의 절정 장면이다.', -959, -959, 'approx', '예루살렘', 31.78, 35.23, true, '솔로몬 성전 열왕기상 8장'),
    ('evt_mon_kingdom_divided', 'era_monarchy', '왕국 분열', '솔로몬 이후 왕국이 남북으로 분열됨', '왕정 시대의 구조적 전환이 시작된다.', -931, -931, 'approx', '세겜', 32.21, 35.28, true, '왕국 분열 열왕기상 12장'),

    ('evt_exr_zerubbabel_return', 'era_exile_return', '1차 귀환', '스룹바벨 인도로 귀환 공동체가 예루살렘으로 돌아옴', '포로 이후 회복 역사의 출발점이다.', -538, -538, 'approx', '예루살렘', 31.78, 35.23, true, '스룹바벨 귀환 에스라 2장'),
    ('evt_exr_temple_foundation', 'era_exile_return', '성전 기초 재건', '귀환 공동체가 성전 기초를 놓고 예배를 회복함', '회복의 중심이 성전 예배임을 보여준다.', -536, -536, 'approx', '예루살렘', 31.78, 35.23, true, '성전 기초 에스라 3장'),
    ('evt_exr_temple_completion', 'era_exile_return', '성전 재건 완공', '성전 재건이 완성되어 봉헌이 이뤄짐', '긴 지연 끝에 공동체 재건이 결실을 맺는다.', -516, -516, 'approx', '예루살렘', 31.78, 35.23, true, '성전 완공 에스라 6장'),
    ('evt_exr_ezra_return', 'era_exile_return', '에스라 귀환', '에스라가 율법을 가지고 예루살렘으로 돌아옴', '말씀 개혁이 본격화되는 시작점이다.', -458, -458, 'approx', '예루살렘', 31.78, 35.23, true, '에스라 귀환 에스라 7장'),
    ('evt_exr_ezra_reform', 'era_exile_return', '에스라의 개혁', '공동체가 회개하며 율법에 맞게 삶을 정비함', '정체성 회복이 실천으로 이어진다.', -457, -457, 'approx', '예루살렘', 31.78, 35.23, true, '에스라 개혁 에스라 10장'),
    ('evt_exr_law_reading', 'era_exile_return', '율법 낭독', '백성 앞에서 율법이 공개 낭독되고 해석됨', '말씀 중심 공동체가 다시 세워진다.', -444, -444, 'approx', '예루살렘 수문 앞 광장', 31.78, 35.23, true, '에스라 느헤미야 율법 낭독 느헤미야 8장'),
    ('evt_exr_nehemiah_commission', 'era_exile_return', '느헤미야 파송', '느헤미야가 바사 왕에게 허락을 받아 예루살렘으로 향함', '회복 프로젝트의 행정적 출발점이다.', -445, -445, 'approx', '수산 궁', 32.19, 48.24, true, '느헤미야 수산 파송 느헤미야 2장'),
    ('evt_exr_nehemiah_wall', 'era_exile_return', '성벽 재건 완성', '느헤미야가 짧은 기간에 성벽 재건을 완수함', '공동체 결집과 외적 방어 회복이 동시에 이뤄진다.', -444, -444, 'approx', '예루살렘', 31.78, 35.23, true, '느헤미야 성벽 재건 느헤미야 6장'),
    ('evt_exr_nehemiah_covenant', 'era_exile_return', '언약 재확인', '백성이 언약 문서에 서명하며 공동체 헌신을 새롭게 함', '회복의 완성은 구조가 아닌 언약 충성에 있음을 보여준다.', -444, -444, 'approx', '예루살렘', 31.78, 35.23, true, '느헤미야 언약 갱신 느헤미야 9장 10장')
)
insert into events (
  code,
  era_id,
  title,
  summary,
  story,
  short_story,
  short_text,
  start_year,
  end_year,
  time_sort_key,
  time_precision,
  place_name,
  lat,
  lng,
  is_major,
  search_text
)
select
  s.code,
  e.id,
  s.title,
  s.summary,
  NULL,
  NULL,
  s.short_text,
  s.start_year,
  s.end_year,
  s.start_year::bigint,
  s.time_precision,
  s.place_name,
  s.lat,
  s.lng,
  s.is_major,
  s.search_text
from seed_events s
join eras e on e.code = s.era_code
;

-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
-- Seed: event_persons
-- -----------------------------------------------------------------------------
with seed_event_persons (event_code, person_code, role, person_sequence) as (
  values
    ('evt_pri_adam_creation', 'adam', '주인공', 1),
    ('evt_pri_adam_fall', 'adam', '주인공', 2),
    ('evt_pri_adam_cain_abel', 'adam', '주인공', 3),
    ('evt_pri_noah_ark', 'noah', '주인공', 1),
    ('evt_pri_noah_flood', 'noah', '주인공', 2),
    ('evt_pri_noah_covenant', 'noah', '주인공', 3),

    ('evt_pat_abraham_call', 'abraham', '주인공', 1),
    ('evt_pat_abraham_covenant', 'abraham', '주인공', 2),
    ('evt_pat_isaac_birth', 'abraham', '주인공', 3),
    ('evt_pat_abraham_moriah', 'abraham', '주인공', 4),
    ('evt_pat_isaac_birth', 'isaac', '등장', 1),
    ('evt_pat_isaac_wells', 'isaac', '주인공', 2),
    ('evt_pat_isaac_blessing', 'isaac', '주인공', 3),
    ('evt_pat_jacob_bethel', 'jacob', '주인공', 1),
    ('evt_pat_jacob_haran', 'jacob', '주인공', 2),
    ('evt_pat_jacob_jabbok', 'jacob', '주인공', 3),
    ('evt_pat_jacob_egypt_migration', 'jacob', '주인공', 4),
    ('evt_pat_joseph_sold', 'joseph', '주인공', 1),
    ('evt_pat_joseph_rise', 'joseph', '주인공', 2),
    ('evt_pat_joseph_reconcile', 'joseph', '주인공', 3),
    ('evt_pat_jacob_egypt_migration', 'joseph', '동행', 4),

    ('evt_ex_moses_burning_bush', 'moses', '주인공', 1),
    ('evt_ex_plagues_passover', 'moses', '주인공', 2),
    ('evt_ex_red_sea_crossing', 'moses', '주인공', 3),
    ('evt_ex_sinai_covenant', 'moses', '주인공', 4),
    ('evt_ex_wilderness_serpent', 'moses', '주인공', 5),
    ('evt_ex_moses_death_nebo', 'moses', '주인공', 6),
    ('evt_ex_plagues_passover', 'aaron', '동역자', 1),
    ('evt_ex_red_sea_crossing', 'aaron', '동역자', 2),
    ('evt_ex_sinai_covenant', 'aaron', '동역자', 3),
    ('evt_ex_aaron_golden_calf', 'aaron', '주인공', 4),
    ('evt_ex_aaron_rod', 'aaron', '주인공', 5),
    ('evt_ex_aaron_death_hor', 'aaron', '주인공', 6),

    ('evt_jdg_joshua_jordan_crossing', 'joshua', '주인공', 1),
    ('evt_jdg_joshua_jericho', 'joshua', '주인공', 2),
    ('evt_jdg_joshua_shechem_covenant', 'joshua', '주인공', 3),
    ('evt_jdg_cycle_begins', 'judges', '주인공', 1),
    ('evt_jdg_deborah_victory', 'judges', '주인공', 2),
    ('evt_jdg_gideon_victory', 'judges', '주인공', 3),
    ('evt_jdg_samson_finale', 'judges', '주인공', 4),
    ('evt_jdg_samuel_call', 'samuel', '주인공', 1),
    ('evt_jdg_samuel_mizpah', 'samuel', '주인공', 2),
    ('evt_jdg_samuel_anoints_saul', 'samuel', '주인공', 3),

    ('evt_mon_saul_jabesh_victory', 'saul', '주인공', 1),
    ('evt_mon_saul_rejected', 'saul', '주인공', 2),
    ('evt_mon_saul_gilboa_death', 'saul', '주인공', 3),
    ('evt_mon_david_anointed', 'david', '주인공', 1),
    ('evt_mon_david_jerusalem', 'david', '주인공', 2),
    ('evt_mon_david_covenant', 'david', '주인공', 3),
    ('evt_mon_solomon_enthroned', 'solomon', '주인공', 1),
    ('evt_mon_solomon_temple', 'solomon', '주인공', 2),
    ('evt_mon_kingdom_divided', 'solomon', '주인공', 3),

    ('evt_exr_zerubbabel_return', 'zerubbabel', '주인공', 1),
    ('evt_exr_temple_foundation', 'zerubbabel', '주인공', 2),
    ('evt_exr_temple_completion', 'zerubbabel', '주인공', 3),
    ('evt_exr_ezra_return', 'ezra', '주인공', 1),
    ('evt_exr_ezra_reform', 'ezra', '주인공', 2),
    ('evt_exr_law_reading', 'ezra', '주인공', 3),
    ('evt_exr_nehemiah_commission', 'nehemiah', '주인공', 1),
    ('evt_exr_nehemiah_wall', 'nehemiah', '주인공', 2),
    ('evt_exr_law_reading', 'nehemiah', '동역자', 3),
    ('evt_exr_nehemiah_covenant', 'nehemiah', '주인공', 4)
)
insert into event_persons (event_id, person_id, role, person_sequence)
select
  e.id,
  p.id,
  s.role,
  s.person_sequence
from seed_event_persons s
join events e on e.code = s.event_code
join persons p on p.code = s.person_code
;

-- -----------------------------------------------------------------------------
-- Seed: event_bible_refs
-- -----------------------------------------------------------------------------
with seed_event_refs (
  event_code,
  book,
  chapter_start,
  verse_start,
  chapter_end,
  verse_end,
  display_text
) as (
  values
    ('evt_pri_adam_creation', '창세기', 1, 26, 2, 8, '창 1:26-2:8'),
    ('evt_pri_adam_fall', '창세기', 3, 1, 3, 24, '창 3:1-24'),
    ('evt_pri_adam_cain_abel', '창세기', 4, 1, 4, 16, '창 4:1-16'),
    ('evt_pri_noah_ark', '창세기', 6, 13, 6, 22, '창 6:13-22'),
    ('evt_pri_noah_flood', '창세기', 7, 1, 7, 24, '창 7:1-24'),
    ('evt_pri_noah_covenant', '창세기', 9, 8, 9, 17, '창 9:8-17'),

    ('evt_pat_abraham_call', '창세기', 12, 1, 12, 9, '창 12:1-9'),
    ('evt_pat_abraham_covenant', '창세기', 15, 1, 15, 21, '창 15:1-21'),
    ('evt_pat_isaac_birth', '창세기', 21, 1, 21, 7, '창 21:1-7'),
    ('evt_pat_abraham_moriah', '창세기', 22, 1, 22, 14, '창 22:1-14'),
    ('evt_pat_isaac_wells', '창세기', 26, 12, 26, 25, '창 26:12-25'),
    ('evt_pat_isaac_blessing', '창세기', 27, 1, 27, 29, '창 27:1-29'),
    ('evt_pat_jacob_bethel', '창세기', 28, 10, 28, 22, '창 28:10-22'),
    ('evt_pat_jacob_haran', '창세기', 29, 15, 30, 24, '창 29:15-30:24'),
    ('evt_pat_jacob_jabbok', '창세기', 32, 22, 32, 31, '창 32:22-31'),
    ('evt_pat_jacob_egypt_migration', '창세기', 46, 1, 46, 7, '창 46:1-7'),
    ('evt_pat_joseph_sold', '창세기', 37, 23, 37, 28, '창 37:23-28'),
    ('evt_pat_joseph_rise', '창세기', 41, 37, 41, 46, '창 41:37-46'),
    ('evt_pat_joseph_reconcile', '창세기', 45, 1, 45, 15, '창 45:1-15'),

    ('evt_ex_moses_burning_bush', '출애굽기', 3, 1, 3, 12, '출 3:1-12'),
    ('evt_ex_plagues_passover', '출애굽기', 12, 1, 12, 14, '출 12:1-14'),
    ('evt_ex_red_sea_crossing', '출애굽기', 14, 21, 14, 31, '출 14:21-31'),
    ('evt_ex_sinai_covenant', '출애굽기', 19, 1, 19, 8, '출 19:1-8'),
    ('evt_ex_wilderness_serpent', '민수기', 21, 4, 21, 9, '민 21:4-9'),
    ('evt_ex_moses_death_nebo', '신명기', 34, 1, 34, 8, '신 34:1-8'),
    ('evt_ex_aaron_golden_calf', '출애굽기', 32, 1, 32, 14, '출 32:1-14'),
    ('evt_ex_aaron_rod', '민수기', 17, 1, 17, 10, '민 17:1-10'),
    ('evt_ex_aaron_death_hor', '민수기', 20, 22, 20, 29, '민 20:22-29'),

    ('evt_jdg_joshua_jordan_crossing', '여호수아', 3, 14, 3, 17, '수 3:14-17'),
    ('evt_jdg_joshua_jericho', '여호수아', 6, 1, 6, 20, '수 6:1-20'),
    ('evt_jdg_joshua_shechem_covenant', '여호수아', 24, 14, 24, 28, '수 24:14-28'),
    ('evt_jdg_cycle_begins', '사사기', 2, 16, 2, 19, '삿 2:16-19'),
    ('evt_jdg_deborah_victory', '사사기', 4, 4, 4, 16, '삿 4:4-16'),
    ('evt_jdg_gideon_victory', '사사기', 7, 19, 7, 22, '삿 7:19-22'),
    ('evt_jdg_samson_finale', '사사기', 16, 28, 16, 30, '삿 16:28-30'),
    ('evt_jdg_samuel_call', '사무엘상', 3, 1, 3, 10, '삼상 3:1-10'),
    ('evt_jdg_samuel_mizpah', '사무엘상', 7, 5, 7, 12, '삼상 7:5-12'),
    ('evt_jdg_samuel_anoints_saul', '사무엘상', 10, 1, 10, 9, '삼상 10:1-9'),

    ('evt_mon_saul_jabesh_victory', '사무엘상', 11, 1, 11, 11, '삼상 11:1-11'),
    ('evt_mon_saul_rejected', '사무엘상', 15, 22, 15, 28, '삼상 15:22-28'),
    ('evt_mon_saul_gilboa_death', '사무엘상', 31, 1, 31, 6, '삼상 31:1-6'),
    ('evt_mon_david_anointed', '사무엘상', 16, 11, 16, 13, '삼상 16:11-13'),
    ('evt_mon_david_jerusalem', '사무엘하', 5, 6, 5, 10, '삼하 5:6-10'),
    ('evt_mon_david_covenant', '사무엘하', 7, 8, 7, 16, '삼하 7:8-16'),
    ('evt_mon_solomon_enthroned', '열왕기상', 1, 32, 1, 40, '왕상 1:32-40'),
    ('evt_mon_solomon_temple', '열왕기상', 8, 22, 8, 30, '왕상 8:22-30'),
    ('evt_mon_kingdom_divided', '열왕기상', 12, 16, 12, 20, '왕상 12:16-20'),

    ('evt_exr_zerubbabel_return', '에스라', 2, 1, 2, 2, '스 2:1-2'),
    ('evt_exr_temple_foundation', '에스라', 3, 10, 3, 13, '스 3:10-13'),
    ('evt_exr_temple_completion', '에스라', 6, 14, 6, 16, '스 6:14-16'),
    ('evt_exr_ezra_return', '에스라', 7, 6, 7, 10, '스 7:6-10'),
    ('evt_exr_ezra_reform', '에스라', 10, 10, 10, 17, '스 10:10-17'),
    ('evt_exr_law_reading', '느헤미야', 8, 1, 8, 8, '느 8:1-8'),
    ('evt_exr_nehemiah_commission', '느헤미야', 2, 1, 2, 8, '느 2:1-8'),
    ('evt_exr_nehemiah_wall', '느헤미야', 6, 15, 6, 16, '느 6:15-16'),
    ('evt_exr_nehemiah_covenant', '느헤미야', 9, 38, 10, 29, '느 9:38-10:29')
)
insert into event_bible_refs (
  event_id,
  book,
  chapter_start,
  verse_start,
  chapter_end,
  verse_end,
  display_text
)
select
  e.id,
  s.book,
  s.chapter_start,
  s.verse_start,
  s.chapter_end,
  s.verse_end,
  s.display_text
from seed_event_refs s
join events e on e.code = s.event_code
;

-- Generated: story from KJV refs (auto)
update events e
set story = s.story
from (values
  ('evt_pri_adam_creation', '하나님이 이르시되 우리의 형상을 따라 우리의 모양대로 우리가 사람을 만들고 그로 바다의 고기와 공중의 새와 육축과 온 땅과 땅에 기는 모든 것을 다스리게 하자 하시고 그래서 하나님은 자기 형상대로 사람을 창조하셨습니다. 하나님의 형상대로 사람을 창조하셨습니다. 남자와 여자를 창조하셨느니라. 하나님이 그들에게 복을 주시며 그들에게 이르시되 생육하고 번성하여 땅에 충만하라, 땅을 정복하라, 바다의 물고기와 공중의 새와 땅에 움직이는 모든 생물을 다스리라 하시니라. 하나님이 이르시되 내가 온 지면의 씨 맺는 모든 채소와 씨 가진 열매 맺는 모든 나무를 너희에게 주노니 너희에게 주노라. 너희에게는 그것이 고기가 될 것이다. 또 땅의 모든 짐승과 공중의 모든 새와 생명이 있어 땅에 기는 모든 것에게는 내가 모든 푸른 풀을 먹을 거리로 주노라 하시니 그대로 되니라 그리고 신 그가 만드신 모든 것을 보니, 보라, 아주 좋았더라. 저녁이 되고 아침이 되니 이는 여섯째 날이니라. 그리하여 하늘과 땅과 그 만물이 다 이루었느니라. 그리고 하나님께서 하시던 일을 일곱째 날에 마치셨습니다. 그가 모든 일을 그치고 일곱째 날에 안식하였더라. 하나님이 일곱째 날을 복 주시어 거룩하게 하셨으니 이는 하나님이 창조하시며 만드시던 모든 일을 마치고 그 날에 안식하셨음이니라. 여호와 하나님이 땅과 하늘과 땅에 생기기 전의 모든 채소와 생기기 전의 밭의 모든 채소를 만드시던 날에 천지의 창조 당시의 창조됨은 이러하니라 여호와 하나님이 땅에 비를 내리지 아니하셨고 땅을 경작할 사람도 없었느니라 그러나 안개가 땅에서 올라와 온 지면을 적시더라. 여호와 하나님이 땅의 흙으로 사람을 지으시고 생기를 그 코에 불어넣으시니 그리고 남자 살아있는 영혼이 되었습니다. 여호와 하나님이 동방의 에덴에 동산을 창설하시고 그리고 그 지으신 사람을 거기 두셨습니다.'),
  ('evt_pri_adam_fall', '이제 뱀은 여호와 하나님의 지으신 들짐승 중에 가장 간교하더라. 예수께서 여자에게 이르시되 그러하다 하나님이 너희더러 동산 모든 나무의 실과를 먹지 말라 하시더냐 여자가 뱀에게 이르되 동산 나무의 열매를 우리가 먹을 수 있으나 동산 중앙에 있는 나무의 열매는 하나님의 말씀에 너희는 먹지도 말고 만지지도 말라 너희가 죽을까 하노라 하셨느니라 뱀이 여자에게 이르되 너희가 결코 죽지 아니하리라 너희가 그것을 먹는 날에는 너희 눈이 밝아져 신과 같이 되어 선악을 알 줄을 하나님이 아심이니라 여자가 그 나무를 보니 먹음직도 하고 보암직도 하고 지혜롭게 할 만큼 탐스럽기도 한 나무인지라 여자가 그 열매를 따 먹고 자기와 함께한 남편에게도 주었더니 그리고 그는 먹었습니다. 그러자 두 사람의 눈이 밝아져 자기들이 벌거벗었음을 알게 되었습니다. 그리고 그들은 무화과나무 잎을 엮어 앞치마를 만들었습니다. 그리고 그들은 아담이 날이 서늘할 때에 동산에 거니시는 여호와 하나님의 음성을 듣고 아담과 그 아내가 여호와 하나님의 낯을 피하여 동산 나무 사이에 숨은지라 여호와 하나님이 아담을 부르시며 그에게 이르시되 네가 어디 있느냐? 그가 이르되, 내가 동산에서 당신의 소리를 듣고 내가 벗었으므로 두려워하였나이다. 그리고 나는 숨었습니다. 예수께서 이르시되 누가 너의 벗었음을 네게 알렸느냐? 내가 너더러 먹지 말라 명한 그 나무 실과를 네가 먹었느냐 ? 그 사람이 이르되, 당신께서 나와 함께 하라고 주신 여자가 그 나무 열매를 내게 주므로 내가 먹었나이다. 여호와 하나님이 여자에게 이르시되 네가 어찌하여 이렇게 하였느냐? 여자가 이르되 뱀이 나를 꾀므로 내가 먹었나이다 여호와 하나님이 뱀에게 이르시되 네가 이렇게 하였으니 네가 모든 육축과 들의 모든 짐승보다 더욱 저주를 받아 너는 배로 다니고 평생에 흙을 먹을지니라 내가 너로 여자 사이와 너 사이에 원수가 되게 하리니 너의 씨와 그녀의 씨; 그것은 네 머리를 상하게 할 것이고 너는 그의 발꿈치를 상하게 할 것이다. 여자에게 이르시되 내가 네게 잉태하는 고통과 잉태를 크게 더하게 하리라 당신은 슬픔 속에서 자녀를 낳을 것입니다. 그리고 당신은 남편을 원하고 남편은 당신을 다스릴 것입니다. 아담에게 이르시되 네가 네 아내의 말을 듣고 내가 너더러 먹지 말라 한 나무 실과를 먹었은즉 땅은 너로 말미암아 저주를 받고 너는 너로 말미암아 저주를 받고 너는 종신토록 수고하여야 그 소산을 먹으리라. 너는 평생 수고해야 그 소산을 먹으리라. 그것이 또한 너에게 가시덤불과 엉겅퀴를 낼 것이다. 너는 들판의 채소를 먹을지니라. 네가 땅으로 돌아갈 때까지 얼굴에 땀을 흘려야 식물을 먹으리라. 그것에서 네가 취함을 입었느니라 너는 흙이니 흙으로 돌아갈 것이니라. 아담은 아내의 이름을 하와라고 불렀습니다. 그녀는 모든 산 자의 어머니였기 때문이다. 여호와 하나님이 아담과 그 아내를 위하여 가죽옷을 지어 입히시니라 여호와 하나님이 이르시되 보라 이 사람이니라 선악을 아는 일에 우리 중 하나 같이 되었으니 그가 그 손을 들어 생명나무 실과도 따먹고 영생할까 하노라 그러므로 여호와 하나님이 그 사람을 에덴동산에서 내어 보내어 그의 근본된 땅을 갈게 하시니라. 그래서 그 사람을 쫓아내셨다. 그리고 에덴동산 동쪽에 그룹들과 두루 도는 화염검을 두어 생명나무의 길을 지키게 하셨습니다.'),
  ('evt_pri_adam_cain_abel', '그리고 아담은 하와를 자기 아내로 알았습니다. 그가 잉태하여 가인을 낳고 이르되 내가 여호와께로 말미암아 남자를 얻었도다 하고 그리고 그녀는 다시 그의 동생 아벨을 낳았습니다. 그리고 아벨은 양을 치는 자였고, 가인은 땅을 경작하는 자였습니다. 얼마 후에 가인은 땅의 소산으로 여호와께 제사를 드렸더라. 그리고 아벨은 양 떼의 첫 새끼와 그 기름으로 드렸습니다. 여호와께서 아벨과 그의 제물은 열납하셨으나 가인과 그의 제물은 열납하지 아니하신지라 그러자 가인은 몹시 화가 나서 안색이 변했습니다. 여호와께서 가인에게 이르시되 네가 어찌하여 분내느냐 그런데 네 얼굴은 왜 변색되었느냐? 네가 잘하면 받아들여지지 않겠느냐? 만일 네가 선을 행하지 아니하면 죄가 문 앞에 엎드리느니라. 그리고 그의 소원은 너에게로 돌아갈 것이니 너는 그를 다스릴 것이니라. 가인이 그의 아우 아벨에게 말하고 그들이 들에 있을 때에 가인이 그의 아우 아벨을 쳐죽였더라. 여호와께서 가인에게 이르시되 어디 있느냐 아벨 네 동생이냐? 그가 이르되 나는 알지 못하나이다 내가 내 아우를 지키는 자니이까 그가 이르되, 네가 무슨 짓을 하였느냐? 네 아우의 피 소리가 땅에서부터 내게 호소하느니라. 땅이 입을 벌려 네 손에서 네 아우의 피를 받았으니 이제 네가 땅에서 저주를 받았느니라. 네가 땅을 갈아도 땅이 앞으로는 그 힘을 네게 주지 않을 것이다. 네가 땅에서 도망자와 유리하는 자가 되리라. 가인이 여호와께 아뢰되 내 벌이 너무 중하여 감당치 못하리이다 보라, 주께서 오늘 나를 이 땅에서 쫓아내셨나이다. 그러면 나는 당신의 얼굴에서 숨겨질 것입니다. 그러면 나는 땅에서 도망하고 유리하는 사람이 될 것입니다. 그리고 나를 만나는 사람은 누구나 나를 죽이게 될 것입니다. 여호와께서 그에게 이르시되 그러므로 가인을 죽이는 자는 벌을 칠배나 받으리라 하시니라 여호와께서 가인에게 표를 주사 만나는 자마다 그를 죽이지 못하게 하셨느니라 가인이 여호와 앞을 떠나 나가서 에덴 동편 놋 땅에 거주하니라.'),
  ('evt_pri_noah_ark', '하나님이 노아에게 이르시되 모든 육체의 끝이 내 앞에 이르렀으니 땅은 그들로 인한 폭력으로 가득 차 있습니다. 보라, 내가 그들을 땅과 함께 멸망시키리라. 너는 잣나무로 방주를 만들어라. 너는 방주 안에 방을 만들고 역청으로 방주 안팎을 칠하라. 네가 만들 방주의 제도는 이러하니 장이 삼백 규빗, 광이 오십 규빗, 고가 삼십 규빗이며 방주에 창을 내되 위에서부터 한 규빗에 마무리하라. 방주의 문은 옆으로 내고 낮은 층, 2층, 3층으로 만드세요. 보라, 나 곧 내가 땅에 홍수를 일으켜 생명의 기운이 있는 모든 육체를 천하에서 멸절하느니라. 땅에 있는 모든 것이 죽을 것이다. 그러나 너와는 내 언약을 세우리라. 너와 네 아들들과 네 아내와 네 자부들과 함께 방주로 들어가라. 그리고 모든 것의 혈육 있는 모든 생물을 너는 각기 둘씩 방주로 인도하여 너와 함께 생명을 보존하게 하라. 그들은 남자와 여자가 ​​될 것이다. 새가 그 종류대로, 가축이 그 종류대로, 땅에 기는 모든 것이 그 종류대로, 각기 둘씩 네게로 나아오리니 그 생명을 보존하게 하라. 너는 먹을 모든 식물을 네게로 가져다가 모아두라. 이것이 너와 그들의 식물이 될 것이다. 노아도 그랬다. 하나님이 그에게 명령하신 대로 다 그대로 행하였더라.'),
  ('evt_pri_noah_flood', '여호와께서 노아에게 이르시되 너와 네 온 집은 방주로 들어가라. 당신이 이 세대에서 내 앞에 의로운 것을 내가 보았나이다. 너는 모든 정결한 짐승은 암수 일곱씩, 부정한 짐승은 암수 둘씩 네게로 취하되 공중의 새도 수컷과 암컷이 일곱 마리요. 온 땅 위에 씨가 살아 있게 하려는 것입니다. 앞으로 칠 일 동안 내가 사십 주야를 땅에 비를 내리리라. 그리고 내가 만든 모든 생물을 지면에서 없애버릴 것이다. 노아가 여호와께서 자기에게 명하신 대로 다 준행하였더라. 홍수가 땅에 있을 때에 노아는 육백 세였더라. 노아가 홍수를 피해 아들들과 아내와 자부들과 함께 방주로 들어갔고 정결한 짐승과 부정한 짐승과 새와 땅에 기는 모든 것이 둘씩 노아에게 나아와 하나님이 노아에게 명령하신 대로 암수와 방주를 삼으라 그리고 칠 일 후에 홍수가 땅 위에 있더라. 노아 육백 세 되던 해 이월 곧 그 달 열이렛일이라 그 날에 큰 깊음의 샘들이 터지며 하늘의 창들이 열리니라 그리고 사십 주야를 비가 땅에 쏟아졌습니다. 바로 그 날에 노아와 노아의 아들 셈과 함과 야벳과 노아의 아내와 세 자부가 함께 방주로 들어갔고 그들과 모든 들짐승이 그 종류대로, 모든 육축이 그 종류대로, 땅에 기는 모든 것이 그 종류대로, 모든 새 곧 모든 새가 그 종류대로. 생명의 기운이 있는 육체가 둘씩 노아에게 나아와 방주로 들어갔습니다. 들어간 것들은 모든 것의 암수로 하나님이 그에게 명하신 대로 들어가매 여호와께서 그를 닫아 넣으시니라 지상에서 40일; 물이 많아져서 방주가 떠 올랐고, 방주는 땅 위로 떠올랐습니다. 그리고 물이 넘쳐 땅에 크게 불어났습니다. 방주는 물 표면 위로 나아갔습니다. 그리고 물이 땅에 넘쳤습니다. 온 천하의 높은 산이 다 덮였느니라 물이 15큐빗 위로 솟아올랐습니다. 그리고 산들이 덮였습니다. 땅 위에 움직이는 생물이 다 죽었으니 곧 새와 육축과 들짐승과 땅에 기는 모든 것과 모든 사람이라 육지에 있어 코로 생명의 기운이 있는 것은 다 죽었더라. 그리고 지면의 모든 생물, 곧 사람과 가축과 기는 것과 공중의 새가 다 죽었습니다. 그리고 그들은 땅에서 멸망당했습니다. 오직 노아와 그와 함께 방주에 있던 사람들만 살아 남았습니다. 그리고 물이 땅에 백 번 넘쳤습니다. 50일.'),
  ('evt_pri_noah_covenant', '하나님이 노아와 그와 함께한 아들들에게 말씀하여 이르시되 보라 내가 너희와 너희 후손과 내 언약을 세우리니 너와 함께한 모든 생물 곧 새와 육축과 너와 함께한 땅의 모든 짐승에게니라 방주에서 나가는 모든 것부터 땅의 모든 짐승까지라. 그리고 나는 너와 내 언약을 세우겠다. 더 이상 모든 육체가 홍수로 멸절되지 않을 것입니다. 땅을 멸망시킬 홍수가 다시 있지 않을 것입니다. 하나님이 이르시되 내가 나와 너희와 및 너희와 함께 하는 모든 생물 사이에 대대로 세우는 언약의 증거는 이것이라 내가 내 무지개를 구름 속에 두었나니 이것이 나와 세상 사이의 언약의 증거니라 내가 구름을 땅 위에 가져오면 구름 속에 무지개가 보이리라. 내가 나와 너희와 및 육체를 가진 모든 생물 사이의 내 언약을 기억하리라. 물이 다시는 홍수가 되지 아니하리니 모든 육체를 파괴하십시오. 그리고 활이 구름 속에 있을 것이다. 내가 그것을 살펴 하나님과 땅 위에 있는 모든 육체를 가진 모든 생물 사이의 영원한 언약을 기억하리라. 하나님이 노아에게 이르시되, 이것이 나와 땅 위에 있는 모든 육체 사이에 세운 언약의 증거니라.'),
  ('evt_pat_abraham_call', '여호와께서 아브람에게 이르시되 너는 너의 본토 친척 아비 집을 떠나 내가 네게 지시할 땅으로 가라 내가 너로 큰 민족을 이루고 네게 복을 주어 네 이름을 창대하게 하리니 너를 축복하는 자에게는 내가 복을 내리고 너를 저주하는 자에게는 내가 저주하리니 땅의 모든 족속이 너로 말미암아 복을 얻을 것이라 그리하여 아브람은 여호와께서 그에게 말씀하신 대로 떠났다. 롯도 그와 함께 갔으며 아브람이 하란을 떠날 때에 나이 칠십오 세였더라. 아브람은 그의 아내 사래와 그의 조카 롯과 그들이 모은 모든 재물과 하란에서 얻은 영혼들을 데리고 갔으며 그리고 그들은 가나안 땅으로 가려고 나갔습니다. 그리고 그들은 가나안 땅에 이르렀습니다. 아브람이 그 땅을 통과하여 세겜 땅 모레 평지에 이르니라. 그 때에 가나안 사람이 그 땅에 거주하였더라. 여호와께서 아브람에게 나타나 이르시되 내가 이 땅을 네 자손에게 주리라 하셨으니 거기서도 자기에게 나타나신 여호와를 위하여 제단을 쌓았더라 거기서 벧엘 동쪽 산으로 옮겨 장막을 치니 서쪽은 벧엘이요 동쪽은 아이라 그가 거기서 여호와를 위하여 제단을 쌓고 여호와의 이름을 부르더니. 그리고 아브람은 계속해서 남쪽을 향해 여행하였다.'),
  ('evt_pat_abraham_covenant', '이 일 후에 여호와의 말씀이 이상 중에 아브람에게 임하여 이르시되 아브람아 두려워하지 말라 나는 너의 방패요 너의 지극히 큰 상급이니라 아브람이 이르되 주 여호와여 나는 무자하니 무엇을 주시려나이까 내 집 청지기는 이 다메섹 엘리에셀이니이다 아브람이 이르되 주께서 내게 씨를 주지 아니하셨으니 내 집에서 길린 자가 내 상속자가 될 것이니이다 보라, 여호와의 말씀이 그에게 임하여 이르시되, 이는 네 상속자가 아니라. 그러나 네 몸에서 나올 자가 네 상속자가 될 것이다. 그를 데리고 밖으로 나가 이르시되 하늘을 우러러 뭇별을 셀 수 있나 보라 또 그에게 이르시되 네 자손이 이와 같으리라 그리고 그는 여호와를 믿었습니다. 그리고 그는 그것을 그의 의로 여겼습니다. 또 그에게 이르시되 나는 이 땅을 네게 주어 차지하게 하려고 너를 갈대아 우르에서 이끌어 낸 여호와니라 그가 가로되 주 여호와여 내가 이 땅을 기업으로 받을 줄을 무엇으로 알리이까 그가 그에게 이르되 나를 위하여 암송아지를 가져오라 세 살 된 암염소 한 마리와 세 살 된 숫양 한 마리와 산비둘기와 집비둘기 새끼 한 마리입니다. 그가 그 모든 것을 취하여 그 가운데를 나누고 각 조각을 서로 마주하게 놓았으나 새들은 나누지 아니하였더라. 새들이 그 사체 위에 내려오매 아브람이 그것을 쫓아내니라. 그리고 해가 질 때에 아브람이 깊은 잠에 빠졌습니다. 보라, 큰 어둠의 공포가 그에게 임하였느니라. 그가 아브람에게 이르시되 정녕히 알라 네 자손이 이방 땅에서 객이 되어 그들을 섬기리로다 그들은 사백 년 동안 그들을 괴롭게 할 것이다. 또 그들이 섬기는 그 나라를 내가 심판하리니 그 후에 그들이 큰 재물을 가지고 나오리라. 그러면 너는 평안히 조상들에게로 돌아갈 것이다. 너는 장수하다가 장사될 것이요 그러나 사대 만에 그들이 이리로 돌아오리니 이는 아모리 족속의 죄악이 아직 관영되지 아니하였음이라. 또 이렇게 되었나니 해가 져서 어두울 때에 보라 한 점이 있더라 연기 나는 풀무와 그 쪼개진 틈 사이로 지나는 등불이 있더라 그 날에 여호와께서 아브람과 언약을 세워 이르시되 내가 이 땅을 애굽 강에서부터 그 큰 강 유브라데까지 네 자손에게 주노니 곧 겐 족속과 그니스 족속과 갓몬 족속과 헷 족속과 브리스 족속과 르바 족속과 아모리 족속과 가나안 족속과 기르가스 족속과 여부스 족속이니라.'),
  ('evt_pat_isaac_birth', '여호와께서 그 말씀대로 사라를 돌보셨고 여호와께서 그 말씀대로 사라에게 행하셨느니라. 사라가 임신하여 하나님이 그에게 말씀하신 기한이 되어서 노년의 아브라함에게 아들을 낳으니라 아브라함이 자기에게 낳은 아들 곧 사라가 자기에게 낳은 아들의 이름을 이삭이라 하였더라. 아브라함이 하나님이 그에게 명령하신 대로 그 아들 이삭이 태어난 지 팔 일 만에 할례를 행하였더라. 아브라함이 그의 아들 이삭을 낳았을 때에 백세였더라. 사라가 가로되 하나님이 나로 웃게 하사 듣는 자가 다 나와 함께 웃게 하려 하심이니라 그가 이르되, 사라가 자식들에게 젖을 먹이게 하였더라면 누가 아브라함에게 말하였으리요? 그 노년에 내가 그에게 아들을 낳았음이니라'),
  ('evt_pat_abraham_moriah', '그 일 후에 하나님이 아브라함을 시험하시려고 그를 부르시되 아브라함아 하시니 그가 이르되 내가 여기 있나이다 하니 여호와께서 이르시되 네 아들 네 사랑하는 독자 이삭을 데리고 모리아 땅으로 가라 내가 네게 지시하는 한 산 거기서 그를 번제로 드리라. 아브라함이 아침에 일찍이 일어나 나귀에 안장을 지우고 두 사환과 그 아들 이삭을 데리고 번제에 쓸 나무를 쪼개어 떠나 하나님이 지시하시는 곳으로 가니라. 셋째 날에 아브라함이 눈을 들어 그 곳을 멀리 바라보니라. 아브라함이 그의 젊은이들에게 이르되, 너희는 나귀와 함께 여기 있으라. 나와 그 아이는 저쪽으로 가서 경배하고 너희에게로 다시 오리라. 아브라함이 번제 나무를 취하여 그의 아들 이삭에게 지우니라. 그는 손에 불과 칼을 들고 있었습니다. 그리고 그들은 둘 다 함께 갔다. 이삭이 그 아버지 아브라함에게 말하여 이르되 내 아버지여 그가 이르되, 내 아들아, 내가 여기 있느니라. 그가 이르되 불과 나무는 있거니와 번제할 어린 양은 어디 있느냐? 아브라함이 이르되 내 아들아 번제할 어린 양은 하나님이 자기를 위하여 친히 준비하시리라 하고 두 사람이 함께 가니라 그리고 그들은 하나님이 그에게 지시하신 곳에 이르렀다. 아브라함은 그곳에 제단을 쌓고 나무를 벌여 놓고 그의 아들 이삭을 결박하여 제단 나무 위에 올려 놓았습니다. 그리고 아브라함은 손을 내밀어 칼을 잡고 그의 아들을 죽이려고 했습니다. 여호와의 사자가 하늘에서 그를 불러 이르시되 아브라함아 아브라함아 하시니 그가 이르되 내가 여기 있나이다 이르시되 그 아이에게 네 손을 대지 말라 그에게 아무 일도 하지 말라 네가 네 아들 네 독자라도 내게 아끼지 아니하였으니 내가 이제야 네가 하나님을 경외하는 줄을 아노라 아브라함이 눈을 들어 살펴본즉 한 숫양이 뒤에 있는데 뿔이 수풀에 걸렸는지라 아브라함이 가서 그 숫양을 가져다가 아들을 대신하여 번제로 드렸더라. 그리고 아브라함이 그 곳 이름을 여호와 이레라 하여 오늘날까지 사람들이 이르기를 여호와의 산에서 보이리라 하였더라'),
  ('evt_pat_isaac_wells', '이삭이 그 땅에서 농사하여 그 해에 백배를 얻었고 여호와께서 그에게 복을 주시니라 그 사람이 창대하고 왕성하여 마침내 더욱 창대하니 양 떼와 소 떼와 종이 심히 많으므로 블레셋 사람들이 그를 시기하여 그 아버지 아브라함 때에 그 아버지의 종들이 판 모든 우물을 막고 흙으로 메웠더라. 아비멜렉이 이삭에게 이르되 우리에게서 떠나라. 당신은 우리보다 훨씬 강하기 때문입니다. 이삭이 그곳을 떠나 그랄 골짜기에 장막을 치고 거기 거류하였더니 그리고 이삭은 그의 아버지 아브라함 시대에 그들이 팠던 우물들을 다시 팠습니다. 아브라함이 죽은 후에 블레셋 사람들이 그들을 막았으므로 아브라함이 그의 아버지가 그들을 부르던 이름으로 그들의 이름을 불렀느니라. 이삭의 종들이 골짜기를 파서 거기서 샘물이 나는 것을 발견하고 그랄 목자들이 다투었더니 이삭의 목자들이 이르되 이 물은 우리의 것이라 하고 그 우물 이름을 에섹이라 하였으며 왜냐하면 그들이 그와 다투었기 때문입니다. 그들이 또 다른 우물을 팠고 그것으로도 다투었으므로 그 이름을 싯나라 불렀더라. 그리고 그는 거기서 옮겨 다른 우물을 팠습니다. 그러므로 그들이 다투지 아니하였으므로 그가 그 이름을 르호봇이라 불렀느니라. 그가 이르되 이제 여호와께서 우리를 위하여 공간을 마련하셨으니 이 땅에서 우리가 번성하리라 하였느니라 그리고 그는 거기서 브엘세바로 올라갔다. 그 밤에 여호와께서 그에게 나타나 이르시되 나는 네 아버지 아브라함의 하나님이니 두려워하지 말라 내 종 아브라함을 위하여 내가 너와 함께 있어 네게 복을 주어 네 자손이 번성하게 하리라 하신지라 이삭이 거기 제단을 쌓고 여호와의 이름을 부르며 거기 장막을 쳤더니 이삭의 종들이 거기서도 우물을 팠더라.'),
  ('evt_pat_isaac_blessing', '이삭이 나이 많아 눈이 어두워 잘 보지 못하더니 맏아들 에서를 불러 이르되 내 아들아 하매 그가 이르되 내가 여기 있나이다 이삭이 이르되 내가 이제 늙어서 죽을 날을 알지 못하노니 이제 청컨대 네 무기들 곧 전통과 활을 가지고 들에 가서 나를 위하여 사냥하여라. 내가 좋아하는 별미를 만들어 내게로 가져다가 내가 먹게 하여라. 그러면 내가 죽기 전에 내 영혼이 당신을 축복하게 될 것입니다. 이삭이 그 아들 에서에게 말할 때에 리브가가 들었더라 그리고 에서는 사슴을 사냥해서 가져오려고 들판으로 나갔습니다. 리브가가 그 아들 야곱에게 말하여 이르되 보라 네 아버지가 네 형 에서에게 말씀하시기를 나를 위하여 사냥하여 별미를 만들어 먹게 하여 내가 죽기 전에 여호와 앞에서 네게 축복하게 하라 하신 것을 내가 들었노라 그러므로 내 아들아, 이제 내가 네게 명령하는 대로 내 말을 따르라. 이제 양 떼로 가서 거기에서 좋은 새끼 염소 두 마리를 나를 데려오너라. 그리고 나는 할 것이다 네 아버지가 좋아하시는 별미를 만들어 네 아버지께 가져다 드려서 그가 돌아가시기 전에 네게 축복하기 위하여 잡수시게 하라. 야곱이 그 어머니 리브가에게 이르되 내 형 에서는 털이 많은 사람이요 나는 매끈매끈한 사람이라 아버지께서 혹시 나를 만지시면 나는 아버지를 속이는 자로 보이실까 하노라 그러면 나는 축복이 아니라 저주를 내리게 될 것입니다. 그의 어머니가 그에게 이르되 내 아들아 너의 저주는 내게로 돌리리니 내 말만 듣고 가서 가져오라 그가 가서 그것을 취하여 그의 어머니에게로 가져왔더니 그의 어머니가 그의 아버지가 좋아하는 별미를 만들었더라. 리브가가 집에 있는 큰 아들 에서의 좋은 의복을 취하여 작은 아들 야곱에게 입히고 염소 새끼의 가죽을 그의 손과 목의 매끈매끈한 옷에 입히고 자기가 만든 별미와 떡을 자기 아들 야곱의 손에 맡기고 그가 아버지에게 와서 이르되 내 아버지여 하매 그가 "내가 여기 있습니다." 내 아들아, 너는 누구냐? 야곱이 그의 아버지에게 말했습니다. “나는 당신의 장자 에서입니다. 당신이 나에게 명하신 대로 내가 행하였사오니 일어나 앉아서 내 사냥한 고기를 잡수시고 당신의 마음껏 내게 축복해 주십시오. 이삭이 그 아들에게 이르되 내 아들아 네가 어찌하여 이렇게 빨리 찾았느냐? 그가 이르되 당신의 하나님 여호와께서 이 일을 나에게 이르게 하였음이니라 이삭이 야곱에게 이르되 내 아들아 가까이 오라 네가 내 아들 에서인지 아닌지 내가 너를 만질 수 있기를 원하노라 야곱이 그의 아버지 이삭에게로 가까이 가니라. 그가 그를 만지며 이르되, 소리는 야곱의 소리이거늘 손은 에서의 손이로다. 그 손에 형 에서의 손과 같이 털이 있으므로 분별하지 못하고 축복하였더라. 그가 이르되, 네가 참 내 아들 에서냐? 그리고 그는 말했습니다. 그가 이르되 내게로 가져오라 내가 내 아들의 사냥한 고기를 먹고 내 마음껏 네게 축복하리라 그가 그것을 그에게 가까이 가져가매 그가 먹고 포도주를 가져가매 그가 마시니라. 그의 아버지 이삭이 그에게 이르되 오라 지금 가까이 와서 나에게 키스해 주세요, 아들아. 그가 가까이 가서 그에게 입맞추니 그가 그의 옷의 향취를 맡고 그에게 축복하여 이르되 내 아들의 향취는 여호와께서 복 주신 밭의 향취로다 그러므로 하나님이 네게 하늘 이슬과 땅의 기름짐과 풍성한 곡식과 포도주를 주시기를 원하노라 민족들이 너를 섬기며 열방이 네게 절하게 하시고 네 형제들의 주인이 되며 네 어미의 아들들이 네게 절하게 하시기를 원하노라 너를 저주하는 자는 저주를 받을 것이요 너를 축복하는 자는 복이 있으리라'),
  ('evt_pat_jacob_bethel', '그리고 야곱은 브엘세바에서 나가 하란을 향하여 갔다. 그리고 그가 한 곳에 머물다가, 해가 져서 거기에서 밤새도록 머물렀다. 그리고 그곳의 돌을 가져다가 베개로 삼고 거기 누워 자려고 했습니다. 꿈에 본즉 ​​사닥다리가 땅 위에 섰는데 그 꼭대기가 하늘에 닿았고 또 본즉 하나님의 사자들이 그 위에서 오르락내리락하더라. 보라, 여호와께서 그 위에 서서 이르시되 나는 여호와 네 아버지 아브라함의 하나님이요 이삭의 하나님이니 네가 누워 있는 땅을 내가 너와 네 자손에게 주리라. 네 자손이 땅의 티끌처럼 되어 네가 동서남북 사방으로 퍼지리라. 그리고 땅의 모든 족속이 너와 네 자손으로 말미암아 복을 받으리라. 보라, 내가 너와 함께 있어 네가 어디로 가든지 너를 지키며 너를 다시 이 땅으로 돌아오게 하리라. 내가 이 일을 다하기까지 너를 떠나지 아니하리라 당신에게 말한 것입니다. 야곱이 잠이 깨어 이르되 여호와께서 과연 여기 계시거늘 나는 그것을 몰랐습니다. 그가 두려워하여 이르되, 이 곳이 얼마나 두렵도다! 이것은 다름 아닌 하나님의 집이요, 이것이 천국의 문이니라. 야곱이 아침에 일찍이 일어나 베개로 삼았던 돌을 가져다가 기둥을 세우고 그 위에 기름을 붓고 그리고 그 곳 이름을 벧엘이라 불렀는데, 그 성의 원래 이름은 루스였다. 야곱이 서원하여 이르되 하나님이 나와 ​​함께 계셔서 내가 가는 이 길에서 나를 지키시고 먹을 떡과 입을 옷을 주사 나로 평안히 아버지 집으로 돌아가게 하시면 그리하면 여호와께서 나의 하나님이 되시리라 내가 기둥으로 세운 이 돌이 하나님의 전이 될 것이요 하나님께서 내게 주신 모든 것에서 내가 반드시 십분의 일을 하나님께 드리겠나이다'),
  ('evt_pat_jacob_haran', '라반이 야곱에게 이르되, 네가 내 동생인데 어찌하여 아무 것도 없이 나를 섬기겠느냐? 나에게 말해보시오. 당신의 품삯은 얼마입니까? 라반에게는 두 딸이 있었는데, 큰 딸의 이름은 레아이고, 작은 딸의 이름은 라헬이었습니다. 레아는 눈이 부드러웠습니다. 그러나 라헬은 아름답고 아름다웠습니다. 그리고 야곱은 라헬을 사랑했습니다. 이르되 내가 네 작은 딸 라헬을 위하여 칠년 동안 너를 섬기리라 하였더니 라반이 이르되 그를 네게 주는 것이 그를 다른 사람에게 주는 것보다 나으니 나와 함께 있으라. 야곱은 라헬을 위해 칠 년 동안 봉사했습니다. 그에게 그 기간은 며칠밖에 안 되는 것처럼 보였습니다. 그가 그녀를 사랑했기 때문입니다. 야곱이 라반에게 이르되 내 기한이 찼으니 내 아내를 내게 주소서 내가 그에게로 들어가겠나이다 라반이 그 곳 사람을 다 모아 잔치를 베풀니라 저녁때에 그는 그의 딸 레아를 그에게로 데려갔다. 그리고 그는 그녀에게 들어갔다. 라반이 그의 여종 실바를 그의 딸 레아에게 여종으로 주었더라. 그리고 그것은왔다 아침에 보니 레아라 그가 라반에게 이르되 네가 어찌하여 나에게 이렇게 하였느냐? 내가 라헬을 위하여 너와 함께 섬기지 아니하였느냐? 그러면 네가 어찌하여 나를 속였느냐? 라반이 이르되, 아우를 장자보다 먼저 주는 것은 우리 나라에서는 이같이 할 수 없느니라. 그 주간을 채우라. 그러면 네가 앞으로 칠 년 동안 나와 함께 섬길 봉사의 대가로 이것도 네게 주리라. 야곱이 그대로 행하여 그 칠일을 채우고 그의 딸 라헬도 그에게 아내로 주었더라. 그리고 라반은 그의 딸 빌하를 그의 여종 라헬에게 시녀로 삼았습니다. 그리고 그가 라헬에게도 들어갔고, 그가 레아보다 라헬도 더 사랑하여, 칠 년을 더 그와 함께 섬겼습니다. 여호와께서 레아에게 총이 없음을 보시고 그의 태를 여셨으나 라헬은 무자하였더라 레아가 잉태하여 아들을 낳고 그 이름을 르우벤이라 하여 가로되 여호와께서 나의 고난을 감찰하셨으니 이제 내 남편은 나를 사랑할 것입니다. 그리고 그녀가 다시 임신하여 아들을 낳았습니다. 그리고 말했다, 왜냐하면 여호와께서 내가 총이 없음을 들으셨으므로 내게 이 아들도 주셨느니라 하고 그의 이름을 시므온이라 하였더라 그리고 그녀가 다시 임신하여 아들을 낳았습니다. 이르되 내가 그에게 세 아들을 낳았으니 이제 내 남편이 나와 연합하리로다 하고 그의 이름을 레위라 하였더라 그가 다시 임신하여 아들을 낳고 이르되 내가 이제 여호와를 찬송하리로다 하고 그의 이름을 유다라 하니라 그리고 왼쪽 베어링. 라헬은 자기가 야곱에게 자식을 낳지 못하는 것을 보고 자기 동생을 시기하였다. 그리고 야곱에게 말했습니다. “나에게 자식을 낳아 주십시오. 그렇지 않으면 내가 죽습니다.” 야곱이 라헬에게 노를 발하여 이르되, 너를 임신하지 못하게 하시는 하나님을 내가 대신하겠느냐? 그 여자가 이르되 내 여종 빌하를 보소서 그에게로 들어가소서 그리고 그녀는 내 무릎을 꿇고 나도 그녀를 통해 자녀를 갖게 될 것입니다. 그 시녀 빌하를 그에게 아내로 주매 야곱이 그에게로 들어갔더니 그리고 빌하가 임신하여 야곱에게 아들을 낳았습니다. 라헬이 이르되 하나님이 나를 심판하사 내 소리를 들으시고 나에게 아들을 주었으므로 그의 이름을 단이라 불렀습니다. 그리고 라헬의 시녀 빌하가 다시 임신하여 야곱에게 둘째 아들을 낳았습니다. 라헬이 이르되 내가 내 형과 크게 싸워 이기었다 하고 그의 이름을 납달리라 하였으며 레아는 자기의 출산이 멈춤을 보고 그 시녀 실바를 데려다가 야곱에게 아내로 주었더라. 그리고 레아의 시녀 실바가 야곱에게 아들을 낳았습니다. 레아가 이르되 군대가 온다 하고 그의 이름을 갓이라 하였으며 그리고 레아의 여종 실바가 야곱에게 둘째 아들을 낳았습니다. 레아가 이르되 나는 행복하도다 딸들이 나를 복되다 하리로다 하고 그의 이름을 아셀이라 하였더라 그리고 르우벤은 밀 추수 때에 갔다가 들에서 합환채를 발견하고 그것을 그의 어머니 레아에게 가져왔습니다. 그러자 라헬이 레아에게 말했습니다. “당신 아들의 합환채를 나에게 주십시오.” 여인이 그에게 이르되 네가 내 남편을 데려간 것이 작은 일이냐 그리고 네가 내 아들의 합환채도 빼앗고 싶느냐? 라헬이 이르되 그러면 그가 네 아들의 합환채를 위하여 오늘 밤 너와 함께 동침하리라 그리고 저물 때에 야곱이 들에서 나오매 레아가 나가서 그를 맞으며 이르되 네가 내게로 들어오라 내가 내 아들의 합환채로 너를 고용하였음이니라. 그리고 그날 밤 그는 그녀와 함께 누웠습니다. 하나님이 레아의 말을 들으셨으므로 그가 잉태하여 다섯 번째 아들을 야곱에게 낳으니라. 레아가 이르되 내가 내 시녀를 내 남편에게 주었으므로 하나님이 나에게 그 값을 주셨다 하고 그의 이름을 잇사갈이라 하였으며 그리고 레아가 다시 임신하여 여섯째 아들 야곱을 낳았습니다. 레아가 말했습니다. “하나님께서 나에게 후한 지참금을 주셨습니다. 이제 내 남편이 나와 함께 거하리라. 내가 그에게 여섯 아들을 낳았으니 그가 그의 이름을 스불론이라 하였느니라. 그 후에 그가 딸을 낳고 그 이름을 디나라 하였더라. 하나님이 라헬을 생각하신지라 하나님이 그의 말을 들으시고 그의 태를 여셨더라 그리고 그녀가 임신하여 아들을 낳았습니다. 가로되 하나님이 나의 부끄러움을 씻으셨느니라 하고 그 이름을 요셉이라 하였으며 이르되 여호와께서 또 다른 아들을 내게 더하시리라 하였느니라'),
  ('evt_pat_jacob_jabbok', '그 밤에 그가 일어나 두 아내와 두 여종과 열한 아들을 데리고 얍복 나루를 건널새 그리고 그는 그들을 데려다가 시내를 건너게 하고 자기가 가진 것도 넘겨 주었느니라. 그리고 야곱은 홀로 남겨졌습니다. 어떤 사람이 날이 새도록 그와 씨름하다가 그가 자기가 자기를 이기지 못함을 보고 그의 환도뼈를 친지라. 야곱이 그와 씨름할 때에 그의 환도뼈 우골이 어그러졌더라. 그가 이르되 날이 새려니 나로 가게 하라 그가 이르되, 당신이 내게 축복하지 아니하면 나는 당신을 보내지 아니하겠나이다. 그가 그에게 이르되, 네 이름이 무엇이냐? 그리고 그가 말했다, 야곱. 그가 이르되 네 이름을 다시는 야곱이라 부를 것이 아니요 이스라엘이라 부를 것이니 이는 네가 하나님과 사람으로 더불어 권세를 가지고 이기었음이니라. 야곱이 그에게 물어 이르되 청하건대 당신의 이름을 내게 가르쳐 주소서. 그가 이르되, 어찌하여 내 이름을 묻느냐? 그리고 거기서 그를 축복했습니다. 야곱이 그 곳 이름을 브니엘이라 불렀으니 이는 내가 하나님과 대면하여 보았음이라 그리고 내 생명은 보존됩니다. 그가 브누엘을 지날 때에 해가 그 위에 돋았고 그의 넓적다리로 인해 절었더라.'),
  ('evt_pat_jacob_egypt_migration', '이스라엘이 모든 소유를 거느리고 발행하여 브엘세바에 이르러 그 아비 이삭의 하나님께 제사를 드리니라. 밤에 하나님이 이상 중에 이스라엘에게 나타나 가라사대 야곱아 야곱아 하신지라 그가 이르시되 내가 여기 있나이다 또 이르시되 나는 하나님이니 네 아버지의 하나님이니 애굽으로 내려가기를 두려워하지 말라 내가 그곳에서 너로 큰 민족을 이루게 하고, 너와 함께 이집트로 내려가겠다. 내가 반드시 너를 다시 일으키리니 요셉이 그의 손으로 네 눈을 감기리라. 야곱이 브엘세바에서 일어났고 이스라엘 자손은 바로가 그를 태우려고 보낸 수레에 그 아버지 야곱과 그들의 어린 아이들과 그들의 아내들을 태웠더라. 그들의 가축과 가나안 땅에서 얻은 재물을 이끌고 애굽으로 갔으니 야곱과 그의 모든 자손과 그와 함께한 그의 아들들과 그의 손자들과 그의 딸들과 그의 손녀들과 그의 모든 자손이 그와 함께 애굽으로 갔더라.'),
  ('evt_pat_joseph_sold', '요셉이 그의 형들에게 이르매 그들이 요셉의 옷 곧 그가 입고 있던 채색옷을 벗기고 그를 잡아 구덩이에 던지니 그 구덩이는 빈 것이라 그 안에 물이 없었더라 그들이 앉아서 떡을 먹다가 눈을 들어 본즉 이스마엘 족속이 길르앗에서 오는데 그 낙타들에 향품과 유향과 몰약을 싣고 애굽으로 내려가는지라 유다가 자기 형제들에게 이르되 우리가 우리 동생을 죽이고 그의 피를 은폐하면 무엇이 유익하리요 자, 그를 이스마엘 사람들에게 팔고 우리 손을 그에게 대지 말자. 그는 우리의 형제요 육체이기 때문입니다. 그리고 그의 형제들은 만족했습니다. 그 때에 미디안 상인들이 지나가더라. 그들이 요셉을 구덩이에서 끌어올리고 은 이십에 요셉을 이스마엘 사람들에게 팔매 그들이 요셉을 데리고 애굽으로 갔더라.'),
  ('evt_pat_joseph_rise', '바로의 눈과 그의 모든 신하의 눈에 이 일이 선하게 여겨졌더라 바로가 그의 신하들에게 이르되 이와 같이 하나님의 영에 감동된 사람을 우리가 어찌 찾을 수 있으리요 바로가 요셉에게 이르되 하나님이 이 모든 것을 네게 보이셨으니 너와 같이 명철하고 지혜 있는 자가 없도다 너는 내 집을 다스리라 내 백성이 다 네 말에 복종하리니 내가 너보다 큰 것은 왕좌뿐이니라 바로가 요셉에게 이르되 보라 내가 너를 애굽 온 땅의 총리로 세웠노라 바로가 자기 손에서 반지를 빼어 요셉의 손에 끼우고 그에게 세마포 옷을 입히고 금목걸이를 목에 걸어주매 그리고 그는 자기가 가지고 있는 두 번째 병거에 그를 타게 했습니다. 그들이 그 앞에서 부르짖기를, 무릎을 꿇으라 하매, 그가 그를 애굽 온 땅의 통치자로 삼았느니라. 바로가 요셉에게 이르되 나는 바로라 애굽 온 땅에서 너 없이는 수족을 놀릴 자가 없느니라 바로가 요셉의 이름을 부르매 삽낫바네아; 그리고 온 제사장 보디베라의 딸 아스낫을 그에게 아내로 주었다. 그리고 요셉은 이집트 온 땅을 순찰하러 나갔습니다. 요셉이 애굽 왕 바로 앞에 설 때에 나이 삼십 세라 요셉은 바로 앞에서 나와 이집트 온 땅을 두루 다녔습니다.'),
  ('evt_pat_joseph_reconcile', '그러자 요셉은 자기 곁에 서 있는 모든 사람들 앞에서 참을 수 없었습니다. 그리고 그는 외쳤다. “모든 사람을 나에게서 나가게 하여라.” 요셉이 자기 형제들에게 자기를 알리는 동안 그와 함께 서 있는 사람이 없었더라 그가 큰 소리로 우니 애굽 사람과 바로의 궁중에 들리더라 요셉이 형들에게 이르되 나는 요셉이라. 내 아버지는 아직 살아 계십니까? 그의 형제들이 그에게 대답할 수 없더라. 이는 그들이 그의 앞에서 불안해하였기 때문이다. 요셉이 형들에게 이르되 청컨대 내게로 가까이 오라 그리고 그들은 가까이 다가왔습니다. 그가 이르되 나는 너희가 애굽에 판 너희 아우 요셉이라 그런즉 너희가 나를 이 곳에 팔았으므로 근심하지 말며 한탄하지 마옵소서 하나님이 생명을 구원하시려고 나를 너희보다 앞서 보내셨음이라 이 땅에 이년 동안 흉년이 들었으나 아직 오년은 밭갈이도 못하고 추수도 못할지라 하나님이 큰 구원으로 너희 생명을 구원하고 이 땅에서 너희 후손을 보존하시려고 나를 너희보다 앞서 보내셨느니라 그러니 이제 나를 보낸 사람은 당신이 아니었습니다 여기에서는 오직 하나님이 나로 바로의 아비를 삼으시며 그 온 집의 주로 삼으시며 애굽 온 땅의 치리자를 삼으셨느니라 너희는 속히 내 아버지에게로 올라가서 그에게 이르기를 네 아들 요셉의 말에 하나님이 나를 애굽 온 땅의 주로 삼으셨으니 지체하지 말고 내게로 내려오라 그리하면 네가 고센 땅에 거하여 너와 네 자녀와 네 손자, 네 양 떼와 소 떼와 네게 속한 모든 것이 나와 가까이 있으리라 내가 거기서 너를 기르리라. 아직 다섯 해 동안 흉년이 들 것입니다. 두렵건대 너와 네 집과 네게 속한 모든 것이 가난하게 될지라 보라, 네 눈과 내 형제 베냐민의 눈이 보는 바가 내 입이 네게 말하는 줄을 알느니라. 그리고 당신들은 내가 이집트에서 누리고 있는 영광과 당신들이 본 모든 것을 내 아버지께 아뢰십시오. 그러면 너희는 서둘러 내 아버지를 이리로 모셔 내려오너라. 그리고 그는 자기 동생 베냐민의 목을 안고 울었습니다. 베냐민은 목을 안고 울었습니다. 더욱이 그는 그의 모든 형제들에게도 입맞추고 그들 위에서 울었습니다. 그 후에 그의 형제들이 그에게 말하였다.'),
  ('evt_ex_moses_burning_bush', '모세가 그 장인 미디안 제사장 이드로의 양 떼를 치더니 그 떼를 광야 서쪽으로 인도하여 하나님의 산 호렙에 이르매 여호와의 사자가 떨기나무 가운데로부터 나오는 불꽃 속에서 그에게 나타나시니라 그가 보니 떨기나무에 불이 붙었으나 그 떨기나무가 사라지지 아니하는지라. 모세가 이르되 내가 이제 돌이켜 이 큰 광경을 보리니 어찌 그 떨기나무가 타지 아니하는지라 여호와께서 그가 보려고 돌이켜 오는 것을 보신지라 하나님이 떨기나무 가운데서 그를 불러 이르시되 모세야 모세야 그가 이르시되 내가 여기 있나이다 이르시되 이리로 가까이 오지 말라 네가 선 곳은 거룩한 땅이니 네 발에서 신을 벗으라 하시고 또 이르시되 나는 네 조상의 하나님이니 아브라함의 하나님, 이삭의 하나님, 야곱의 하나님이니라. 그리고 모세는 얼굴을 가리었습니다. 왜냐하면 그는 하나님을 바라보는 것을 두려워했기 때문입니다. 여호와께서 이르시되 내가 애굽에 있는 내 백성의 고난을 분명히 보고 그들의 부르짖음을 들었나니 감독관의 이유; 나는 그들의 슬픔을 알고 있습니다. 내가 내려와서 그들을 애굽인의 손에서 건져내고 그들을 그 땅에서 인도하여 아름답고 광대한 땅, 젖과 꿀이 흐르는 땅에 이르고 가나안 족속과 헷 족속과 아모리 족속과 브리스 족속과 히위 족속과 여부스 족속의 땅으로 가니라 이제 보라 이스라엘 자손의 부르짖음이 내게 이르렀고 애굽 사람이 그들을 학대하는 학대도 내가 보았느니라 이제 내가 너를 바로에게 보내어 너로 내 백성 이스라엘 자손을 애굽에서 인도하여 내게 하리라 모세가 하나님께 아뢰되 내가 누구이기에 바로에게 가며 이스라엘 자손을 애굽에서 인도하여 내리이까 그리고 그는 말했다, 내가 반드시 너와 함께 있을 것이다; 네가 백성을 애굽에서 인도하여 낸 후에 너희가 이 산에서 하나님을 섬기리라 이것이 내가 너를 보낸 증거니라'),
  ('evt_ex_plagues_passover', '여호와께서 애굽 땅에서 모세와 아론에게 말씀하여 이르시되 이 달로 너희에게 달의 시작 곧 해의 첫 달이 되게 하고 너희는 이스라엘 온 회중에게 말하여 이르라 이 달 열흘에 각 사람이 어린 양을 자기 종족을 따라 한 식대로 취할 것이요 만일 식구가 어린 양에 비해 부족하면 그와 그 집의 이웃이 그 사람의 수를 따라 취할 것이요 각 사람이 먹는 대로 어린 양을 계산할지니라 너희 어린 양은 흠 없는 일 년 된 수컷으로 하되 양이나 염소 중에서 취하여 이달 십사일까지 간직했다가 저녁에 이스라엘 회중 온 회중이 그것을 잡을지니라 그리고 그 피를 취하여 그것을 먹을 집의 좌우 설주와 윗문설주에 뿌리라. 그리고 그들은 먹을 것이다 그 밤에 고기를 불에 구워 무교병을 드리고 쓴 나물과 함께 먹되 생으로 먹지 말고 물에 불리지도 말고 불에 구워서 먹으라. 그의 머리와 그의 다리와 그 소유물과 함께. 그리고 아침까지 아무것도 남겨 두어서는 안 된다. 그리고 아침까지 남은 것은 불에 태워라. 너희는 그것을 이렇게 먹을지니라. 허리에 띠를 띠고 발에 신을 신고 손에 지팡이를 잡고 너희는 그것을 급히 먹으라 이것이 여호와의 유월절이니라 내가 오늘 밤에 이집트 땅을 두루 다니며 사람이나 짐승을 막론하고 이집트 땅에 있는 처음 난 것을 다 쳐죽일 것이기 때문이다. 내가 애굽의 모든 신을 벌하리라 나는 여호와이니라 그 피는 너희가 있는 집에 너희의 표징이 될 것이라 내가 피를 볼 때에 너희를 넘어가리니 내가 애굽 땅을 칠 때에 재앙이 너희에게 내려 멸하지 아니하리라 그리고 이 날이 너희에게 기념이 될 것이다. 그러면 너희는 그것을 지키라 너희 대대로 여호와를 위한 절기니라. 너희는 규례로 영원히 절기를 지킬지니라'),
  ('evt_ex_red_sea_crossing', '그리고 모세가 바다 위로 손을 뻗었습니다. 여호와께서 큰 동풍으로 밤새도록 바다를 물러가게 하시고 바다를 마른 땅이 되게 하시니 물이 갈라지니라 이스라엘 자손이 바다 가운데 육지로 행하였고 물이 그들의 좌우에 벽이 되었더라. 애굽 사람들 곧 바로의 말들과 병거들과 마병들이 다 뒤쫓아 바다 가운데로 들어가니라 새벽에 여호와께서 불과 구름 기둥 가운데서 애굽 군대를 보시고 애굽 군대를 어지럽게 하시며 그들의 병거 바퀴를 벗겨서 달리게 하시매 애굽 사람들이 이르되 이스라엘 앞에서 우리가 도망하자 여호와께서 그들을 위하여 싸워 애굽 사람들을 치는도다 여호와께서 모세에게 이르시되 바다 위로 손을 내밀라 물이 애굽 사람들과 그들의 병거와 마병 위에 다시 덮이리라 모세가 바다 위로 손을 내밀매 아침이 밝아오자 바다가 그 힘을 회복하고 그러자 이집트인들이 그 곳을 향해 도망쳤습니다. 여호와께서 애굽 사람들을 바다 가운데 엎드러뜨리셨느니라 물이 다시 흘러 병거들과 기병들을 덮고 그들의 뒤를 따라 바다에 들어간 바로의 군대를 다 덮으니 그 중 한 마리도 남지 않았습니다. 그러나 이스라엘 자손은 바다 가운데서 마른 땅 위로 걸었습니다. 물은 그들의 오른쪽과 왼쪽에 벽이 되었습니다. 그 날에 여호와께서 이와 같이 이스라엘을 애굽 사람의 손에서 구원하셨으니 이스라엘은 해변에서 이집트인들이 죽어 있는 것을 보았습니다. 이스라엘이 여호와께서 애굽 사람들에게 행하신 그 큰 일을 보았으므로 백성이 여호와를 경외하며 여호와와 그 종 모세를 믿었더라.'),
  ('evt_ex_sinai_covenant', '이스라엘 자손이 애굽 땅에서 나온 셋째 달 바로 그 날에 그들이 시내 광야에 이르니라. 이는 그들이 르비딤을 떠나 시내 광야에 이르러 광야에 진을 쳤음이니라. 이스라엘은 거기 산 앞에 진을 쳤다. 모세가 하나님께 올라갔더니 여호와께서 산에서 그를 불러 이르시되 너는 야곱 족속에게 이같이 이르고 이스라엘 자손에게 이르라 내가 애굽 사람에게 행한 일과 독수리 날개로 너희를 업고 내게로 인도한 것을 너희가 보았느니라 그러므로 너희가 내 말을 잘 듣고 내 언약을 지키면 너희는 모든 민족 중에서 내 소유가 되리라. 천하가 다 내 것임이니라 너희가 내게 대하여 제사장 나라가 되며 거룩한 백성이 되리라 이는 네가 이스라엘 자손에게 전할 말씀이니라. 모세가 와서 백성의 장로들을 불러 여호와께서 자기에게 명하신 모든 말씀을 그들의 앞에 진술하니라 그리고 모든 백성이 일제히 응답하여 이르되 여호와께서 말씀하신 대로 우리가 다 준행하리이다 모세가 백성의 말을 여호와께 회답하니라.'),
  ('evt_ex_wilderness_serpent', '호르 산에서 출발하여 홍해 길로 에돔 땅을 두루 행하매 그 길로 말미암아 백성의 마음이 심히 낙담하였더라. 백성이 하나님과 모세를 향하여 원망하되 너희가 어찌하여 우리를 애굽에서 인도하여 올려 광야에서 죽게 하느냐? 빵도 없고 물도 없습니다. 우리 영혼은 이 가벼운 빵을 싫어합니다. 여호와께서 불뱀들을 백성 중에 보내어 백성을 물게 하시므로 그리고 이스라엘 백성이 많이 죽었습니다. 그러므로 백성이 모세에게 나아와서 이르되 우리가 여호와와 당신을 향하여 원망함으로 범죄하였나이다 여호와께 기도하여 뱀을 우리에게서 떠나게 하소서 그리고 모세는 백성을 위해 기도했습니다. 여호와께서 모세에게 이르시되 불뱀을 만들어 장대 위에 달라 물린 자마다 그것을 보면 살리라 모세가 놋뱀을 만들어 장대 위에 다니 뱀에게 물린 자마다 보면, 놋뱀, 그는 살았다.'),
  ('evt_ex_moses_death_nebo', '모세가 모압 평지에서 느보 산으로 올라가 여리고 맞은편 비스가 산 꼭대기에 이르니라. 여호와께서 길르앗 온 땅을 단까지 보이시고 또 온 납달리와 에브라임과 므낫세의 땅과 서해까지의 유다 온 땅과 남방과 종려나무 성읍 여리고 골짜기 평지를 소알까지 보이시고 여호와께서 그에게 이르시되 이는 내가 아브라함과 이삭과 야곱을 향하여 맹세하여 네 자손에게 주리라 한 땅이라 내가 네 눈으로 보게 하였거니와 너는 그리로 건너가지 못하리라 그리하여 여호와의 종 모세는 여호와의 말씀대로 그곳 모압 땅에서 죽었습니다. 벳브올 맞은편 모압 땅에 있는 골짜기에 장사되었으나 오늘날까지 그의 묘실을 아는 자가 없느니라 모세가 죽을 때 나이 일백이십 세였으나 그의 눈이 흐리지 아니하였고 기력이 쇠하지 아니하였더라. 그리고 이스라엘 자손은 모압 평지에서 모세를 위하여 울었습니다. 삼십 일 동안 모세의 울며 애도하는 날이 끝났느니라.'),
  ('evt_ex_aaron_golden_calf', '백성은 모세가 산에서 내려옴이 더디는 것을 보고 모여 아론에게 이르러 이르되 일어나라 우리를 인도할 신을 우리를 위하여 만들라 우리를 이집트 땅에서 인도해 낸 이 모세라는 사람은 어떻게 되었는지 우리는 모릅니다. 아론이 그들에게 이르되 너희 아내와 자녀의 귀에 있는 금귀고리를 빼어 내게로 가져오라 그리고 모든 백성은 자기 귀에 있는 금귀고리를 빼어 아론에게 가져왔습니다. 그가 그것을 그들의 손에서 받아 송아지를 부어 만든 후에 조각하는 도구로 그것을 만들었더니 그들이 이르되 이스라엘아 이는 너를 애굽 땅에서 인도하여 낸 너의 신들이니라 아론은 그것을 보고 그 앞에 제단을 쌓았습니다. 아론이 선포하여 이르되 내일은 여호와의 절기니라 그리고 그들은 이튿날 일찍 일어나 번제와 화목제를 드렸습니다. 그리고 사람들이 앉았어 내려가서 먹고 마시며 일어나서 놀았느니라. 여호와께서 모세에게 이르시되 가서 내려가라. 네가 애굽 땅에서 인도하여 낸 네 백성이 스스로 부패하여 내가 그들에게 명한 도를 속히 떠나 자기를 위하여 송아지를 부어 만들고 그것을 경배하며 그것에게 제사를 드리며 이르기를 이스라엘아 이는 너를 애굽 땅에서 인도하여 낸 네 신이로다 하였느니라 여호와께서 모세에게 이르시되 내가 이 백성을 보니 목이 곧은 백성이로다 그런즉 나대로 하게 하라 내가 그들에게 진노하여 그들을 진멸하고 너로 큰 나라가 되게 하리라 모세가 그의 하나님 여호와께 구하여 이르되 여호와여 어찌하여 그 큰 권능과 강한 손으로 애굽 땅에서 인도하여 내신 주의 백성에게 진노하시나이까? 어찌하여 애굽인들이 말하여 이르기를 하나님이 그들을 산에서 죽이고 멸하려 하여 재앙을 내리려고 그들을 인도하여 내셨나이까 지상에서 온 사람들이냐? 주의 맹렬한 진노를 그치시고 주의 백성에 대한 이 재앙을 회개하소서. 주의 종 아브라함과 이삭과 이스라엘을 기억하소서 주께서 그들을 위하여 주를 가리켜 맹세하여 이르시기를 내가 너희 자손을 하늘의 별과 같이 많게 하고 내가 허락한 이 온 땅을 너희 자손에게 주어 영원히 기업이 되게 하리라 하셨느니라 그리고 여호와께서는 자기 백성에게 내리려고 생각하신 재앙을 후회하셨다.'),
  ('evt_ex_aaron_rod', '여호와께서 모세에게 일러 가라사대 이스라엘 자손에게 말하여 그들 각각의 종족대로 지팡이 하나씩 취하되 그들의 종족을 따라 모든 방백들에게서 지팡이 열두 개를 취하되 각 사람의 이름을 그 지팡이에 쓰라 너는 레위의 지팡이에 아론의 이름을 쓰라. 그 지팡이 하나는 그들의 조상의 집의 우두머리가 될 것임이니라. 그리고 그것을 회막 안 증거궤 앞에 두라. 그곳에서 내가 너와 만날 것이다. 내가 택한 사람의 지팡이에는 싹이 나리니 이스라엘 자손이 너희를 향하여 원망하는 그 원망이 내게서 그치게 하리라. 모세가 이스라엘 자손에게 말하매 그들의 족장들이 각각 그 종족을 따라 지팡이 하나씩 그에게 주었으니 열두 지팡이라 그 지팡이들 중에 아론의 지팡이가 있었더라 모세가 회막 안 여호와 앞에 그 지팡이들을 놓아 두니라. 그리고 그것은왔다 다음 날 모세는 회막에 들어갔습니다. 보라, 레위 집을 위하여 낸 아론의 지팡이에 움이 돋고 순이 나고 꽃이 피어서 살구 열매가 열렸느니라. 모세가 여호와 앞에서 이스라엘 모든 자손에게 지팡이를 모두 가져오매 그들이 보고 각기 지팡이를 취하니라. 여호와께서 모세에게 이르시되 아론의 지팡이를 증거궤 앞에 도로 가져오라 이는 반역자들을 대적하는 표로 삼으라 그리고 당신께서는 저들의 불평을 제게서 거두어 주십시오. 그러면 저들이 죽지 않을 것입니다.'),
  ('evt_ex_aaron_death_hor', '이스라엘 자손 곧 온 회중이 가데스에서 출발하여 호르 산에 이르니라. 여호와께서 에돔 땅 해변 호르 산에서 모세와 아론에게 일러 가라사대 아론은 그 열조에게로 돌아가고 내가 이스라엘 자손에게 준 땅에는 들어가지 못하리니 이는 너희가 므리바 물에서 내 말을 거역하였음이라. 아론과 그의 아들 엘르아살을 데리고 호르산에 올라가서 아론의 옷을 벗겨 그의 아들 엘르아살에게 입히라 아론은 그 열조에게로 돌아가 거기서 죽으리라 모세가 여호와께서 명령하신 대로 행하여 온 회중이 보는 앞에서 호르 산에 올라가니라. 모세는 아론의 옷을 벗겨 그의 아들 엘르아살에게 입혔습니다. 아론은 그곳 산 꼭대기에서 죽고, 모세와 엘르아살은 산에서 내려왔다. 온 회중이 아론이 죽은 것을 보고 이스라엘 온 족속이 아론을 위하여 삼십 일 동안 애곡하였더라.'),
  ('evt_jdg_joshua_jordan_crossing', '백성이 요단을 건너려고 그 장막에서 떠날 때에 제사장들이 언약궤를 메고 백성 앞에서 궤를 멘 자들이 요단에 이르매 궤를 멘 제사장들의 발이 물가에 잠겼으니 이는 요단이 추수 때마다 온 둑에 넘치므로 위에서 흘러내리던 물이 멈춰서 사르단 옆에 있는 아담 성에서 멀리 떨어진 더미 위에 쌓이고 평야의 바다 곧 염해로 흘러가던 물은 끊어져 끊어지매 백성은 여리고를 향하여 곧 건널새 여호와의 언약궤를 멘 제사장들은 요단 가운데 마른 땅에 굳게 섰고 이스라엘 자손은 다 마른 땅으로 건너가서 모든 백성이 요단을 건널 때까지 하였더라.'),
  ('evt_jdg_joshua_jericho', '이제 여리고는 이스라엘 자손으로 말미암아 굳게 닫혔고 나가는 사람과 들어오는 사람이 없더라 여호와께서 여호수아에게 이르시되 보라 내가 여리고와 그 왕과 용사들을 네 손에 붙였느니라 너희 모든 군사들은 그 성을 돌며 그 성을 한 바퀴 돌라. 너는 엿새 동안 이렇게 하라. 제사장 일곱은 일곱 양각 나팔을 들고 궤 앞에서 행할 것이요 일곱째 날에는 성을 일곱 번 돌며 제사장들은 나팔을 불 것이며 그들이 숫양 나팔을 길게 불고 나팔 소리가 들리면 모든 백성은 큰 소리로 외칠 것입니다. 그러면 그 성벽은 무너져 내릴 것이고, 백성은 각기 자기 앞으로 곧장 올라갈 것이다. 눈의 아들 여호수아가 제사장들을 불러 그들에게 이르되 너는 언약궤를 메고 제사장 일곱은 일곱 양각 나팔을 잡고 여호와의 궤 앞에서 행하라 그리고 그는 말했다 백성은 나아가서 성을 에워싸고 무장한 자는 여호와의 궤 앞으로 행진하라. 여호수아가 백성에게 명령한 후에 일곱 양각 나팔을 가진 일곱 제사장이 여호와 앞으로 나아가며 나팔을 불고 여호와의 언약궤는 그 뒤를 따르니라 무장한 자들은 나팔을 부는 제사장들 앞에서 행진하고 후위대는 궤 뒤에 오니 제사장들은 나팔을 불며 행진하더라. 여호수아가 백성에게 명령하여 이르되 내가 너희에게 외치라 명하는 날까지 너희는 외치지 말며 큰 소리로 떠들지도 말며 아무 말도 너희 입에서 내지 말찌니라 그러면 너희는 소리칠 것이다. 여호와의 궤가 그 성을 한 번 두루 돌매 그들이 진영에 들어와 진영에서 자니라 여호수아가 아침에 일찍 일어나매 제사장들이 여호와의 궤를 메니라 일곱 제사장은 일곱 양각 나팔을 들고 여호와의 궤 앞에서 행진하니라 계속해서 나팔을 불고, 무장한 사람들이 그들 앞에서 행진했습니다. 그러나 후송자는 여호와의 궤 뒤에 왔고 제사장들은 나팔을 불며 행진하였다. 둘째 날에도 그들은 그 성을 한 번 돌고 진영으로 돌아왔다. 그들은 엿새 동안 그렇게 했다. 일곱째 날 새벽에 그들이 일찍이 일어나 같은 방식으로 그 성을 일곱 번 돌았으니 그 날에만 그들이 그 성을 일곱 번 돌았느니라. 일곱 번째에 제사장들이 나팔을 불 때에 여호수아가 백성에게 이르되 외치라. 여호와께서 이 성을 너희에게 주셨느니라. 그 성과 그 안에 있는 모든 것은 여호와께 저주를 받으리니 기생 라합과 그 집에 동거하는 자는 다 살리라 이는 그가 우리가 보낸 사자를 숨겼음이니라 너희는 반드시 바친 물건을 삼가라 너희가 바친 물건을 취하여 이스라엘 진을 만들 때에는 스스로 저주를 받을까 하노라 저주하고 문제를 일으키십시오. 오직 은과 금과 놋과 철로 만든 모든 기명은 여호와께 구별하여 여호와의 곳간에 들어가게 할 것이니라 이에 제사장들이 나팔을 불 때에 백성이 외쳤더니 백성이 나팔 소리를 듣고 큰 소리로 외치매 성벽이 무너져 내린지라 백성이 각기 앞으로 나아가 성읍으로 올라가서 그 성을 점령하였느니라.'),
  ('evt_jdg_joshua_shechem_covenant', '그런즉 이제 여호와를 경외하며 온전함과 진실함으로 그를 섬기라 너희 조상들이 강 저편과 애굽에서 섬기던 신들을 버려라. 그리고 여호와를 섬기십시오. 만일 여호와를 섬기는 것이 너희에게 좋지 않게 보이거든 너희 섬길 자를 오늘 택하라. 너희 조상들이 강 저편에서 섬기던 신이든지 혹 너희가 거주하는 땅 아모리 족속의 신이든지 오직 나와 내 집은 여호와를 섬기겠노라 백성이 대답하여 이르되 우리가 결단코 여호와를 버리고 다른 신들을 섬기는 것은 결단코 아니니라 우리 하나님 여호와께서는 우리와 우리 조상들을 애굽 땅, 종 되었던 집에서 인도하여 내시고 우리 목전에서 큰 이적을 행하시고 우리가 가는 모든 길에서와 우리가 지나간 모든 백성 가운데에서 우리를 보호하셨느니라 여호와께서 모든 백성 곧 그 땅에 거주하는 아모리 족속을 우리 앞에서 쫓아내시니 그러므로 우리도 여호와를 섬기리라 그분은 우리 하나님이시기 때문입니다. 그리고 조슈아가 말했습니다. 백성에게 대하여 너희가 여호와를 능히 섬기지 못하리니 그는 거룩하신 하나님이심이니라 그는 질투하시는 하나님이십니다. 그는 너희 허물과 죄를 용서하지 아니하실 것이다. 너희가 여호와를 버리고 이방 신들을 섬기면 너희에게 복을 내리신 후에라도 돌이켜 너희에게 재앙을 내리시고 너희를 멸하실 것이라 백성이 여호수아에게 말했습니다. 그러나 우리는 여호와를 섬기겠습니다. 여호수아가 백성에게 이르되 너희가 여호와를 택하여 그를 섬기게 하였음에 대하여 너희가 스스로 증인이 되었느니라 그러자 그들이 말했습니다. “우리는 증인입니다.” 이제 너희 중에 있는 이방 신들을 제하여버리고 너희 마음을 이스라엘의 하나님 여호와께로 향하라 하였느니라. 백성이 여호수아에게 이르되 우리가 우리 하나님 여호와를 섬기고 그 말씀을 우리가 청종하리이다 그리하여 여호수아는 그 날 백성과 언약을 맺고 세겜에서 그들에게 율례와 율례를 정하였다. 여호수아가 이 모든 말씀을 하나님의 율법책에 기록하고 큰 돌을 가져다가 거기 여호와의 성소 곁에 있는 상수리나무 아래 세우고 여호수아가 모든 백성에게 이르되 사람들아, 보라 이 돌이 우리에게 증거가 되리라. 이 짐승은 여호와께서 우리에게 이르신 모든 말씀을 들었으므로 너희에게 증인이 되어 너희가 너희 하나님을 부인하지 않게 하려 함이니라 그리하여 여호수아는 백성을 각각 자기의 기업으로 돌려 보냈습니다.'),
  ('evt_jdg_cycle_begins', '그러나 여호와께서 사사들을 세우사 그들을 노략하는 자들의 손에서 구원하셨느니라 그러나 그들이 자기 사사들의 말을 듣지 아니하고 음란하게 다른 신들을 섬기며 그들에게 절하고 그들의 조상들이 여호와의 명령을 순종하여 행하던 길에서 속히 떠나 그러나 그들은 그렇지 않았습니다. 여호와께서 그들을 사사들을 세우실 때에 여호와께서 그 사사와 함께 계셔서 사사가 사는 날 동안 그들을 그들의 대적의 손에서 구원하셨으니 이는 그들이 그들을 학대하고 학대함으로 인하여 탄식함으로 말미암아 여호와께서 후회하셨음이라 사사가 죽은 후에 그들이 돌아와서 그들의 조상들보다 더 부패하여 다른 신들을 따라 그들을 섬기며 그들에게 절하고 그들은 자기 행위와 고집을 그치지 아니하였느니라.'),
  ('evt_jdg_deborah_victory', '그 때에 랍비돗의 아내 여선지자 드보라가 이스라엘의 사사가 되었더라 그가 에브라임 산지 라마와 벧엘 사이 드보라의 종려나무 아래 거하였더니 이스라엘 자손이 그에게 나아가 재판을 받더라. 그가 사람을 보내어 납달리 게데스에서 아비노암의 아들 바락을 불러서 그에게 이르되 이스라엘의 하나님 여호와께서 명하여 이르시기를 가서 다볼 산으로 향하여 납달리 자손과 스불론 자손 만 명을 데리고 가라 하시지 아니하였느냐 내가 야빈의 군대 대장 시스라와 그의 병거들과 그의 무리를 기손 강으로 네게로 인도하리라. 그러면 내가 그를 네 손에 넘겨주겠다. 바락이 그에게 이르되 당신이 나와 함께 가면 나도 가고 당신이 나와 함께 가지 아니하면 나도 가지 아니하리니 그 여자가 이르되 내가 반드시 너와 함께 가리라. 그러나 네가 가는 길은 네 영광이 되지 못할 것임이니라. 여호와께서 시스라를 여인의 손에 파실 것임이니라 드보라가 일어나 바락과 함께 게데스로 가니라. 그리고 바락은 스불론과 납달리를 게데스로 불렀습니다. 그가 만 명을 거느리고 그의 발 아래로 올라갔고 드보라도 그와 함께 올라갔더라. 모세의 장인 호밥의 자손 중 겐 사람 헤벨이 자기 족속을 떠나 게데스에 가까운 사아나임 상수리나무에 장막을 쳤더니 그리고 그들은 아비노암의 아들 바락이 다볼 산으로 올라갔다는 것을 시스라에게 알렸습니다. 시스라가 그의 모든 병거 곧 철 병거 구백 대와 자기와 함께한 모든 백성을 이방인의 하로셋에서 기손 강까지 모으니라. 드보라가 바락에게 말했습니다. 이는 여호와께서 시스라를 네 손에 붙이신 날이니라 여호와께서 네 앞서 행하신 것이 아니냐? 바락이 다볼산에서 내려갔고 그의 뒤를 따르는 자가 만 명이더라. 여호와께서 바락 앞에서 시스라와 그의 모든 병거와 그의 모든 군대를 칼날로 쳐서 패하게 하시니 그러자 시스라가 병거에서 내려 걸어서 도망쳤습니다. 그러나 바락 병거들과 군대를 추격하여 이방인 하로셋까지 추격하니 시스라의 온 군대가 칼날에 엎드러지니라. 그리고 한 사람도 남지 않았습니다.'),
  ('evt_jdg_gideon_victory', '기드온과 그와 함께한 백 명이 월경 초에 진영 밖에 이르렀더니 그들은 파수꾼을 새로 놓았을 뿐이고, 나팔을 불고 손에 들고 있던 항아리를 부수었습니다. 세 대가 나팔을 불며 항아리를 부수고 왼손에 등불을 들고 오른손에 나팔을 잡고 불며 이르되 여호와와 기드온의 칼이로다 하더라. 그들이 각각 자기 자리에 서서 진영을 둘러싸매 모든 군대가 달리고 부르짖으며 도망하니라. 삼백 명이 나팔을 불매 여호와께서 온 군대에서 서로 칼로 치게 하시므로 적군이 도망하여 스레라의 벧싯다에 이르고 또 답밧에 이르는 아벨므홀라의 경계에 이르렀으며'),
  ('evt_jdg_samson_finale', '삼손이 여호와께 부르짖어 이르되 주 여호와여 나를 기억하옵소서 하나님이여 구하옵나니 이번만 나를 강하게 하사 블레셋 사람들이 내 두 눈을 뺀 원수를 단번에 갚게 하옵소서 삼손은 집을 지탱하는 가운데 기둥 두 개를 잡았습니다. 하나는 오른손으로, 하나는 왼손으로 잡았습니다. 삼손이 이르되 내가 블레셋 사람들과 함께 죽게 하소서. 그리고 그는 온 힘을 다해 몸을 굽혔습니다. 그 집은 귀인들과 거기에 있는 모든 백성에게 무너졌느니라. 그러므로 그가 죽을 때 죽인 사람이 그가 살아 있을 때 죽인 사람보다 더 많았습니다.'),
  ('evt_jdg_samuel_call', '그리고 어린 사무엘은 엘리 앞에서 여호와를 섬겼습니다. 그 당시에는 여호와의 말씀이 귀중하여 열린 비전이 없었습니다. 그 때에 엘리가 자기 처소에 누웠더니 그의 눈이 어두워져서 보지 못하더라. 하나님의 궤 있는 여호와의 전 안의 하나님의 등불이 꺼지기 전에 사무엘이 잠들었더니 여호와께서 사무엘을 부르시니 그가 대답하되 내가 여기 있나이다 하고 엘리에게 달려가 이르되 내가 여기 있나이다 당신이 나를 부르셨기 때문입니다. 그가 이르되, 나는 부르지 아니하였노라. 다시 누워. 그리고 그는 가서 누웠다. 여호와께서 다시 사무엘을 부르시니라. 사무엘이 일어나 엘리에게 가서 이르되 내가 여기 있나이다 당신이 나를 부르셨기 때문입니다. 그가 대답하되 내 아들아 내가 부르지 아니하였노라 다시 누워. 사무엘은 아직 여호와를 알지 못하였고 여호와의 말씀도 아직 그에게 나타나지 아니하였더니 그리고 여호와께서 세 번째로 다시 사무엘을 부르셨습니다. 그가 일어나 엘리에게 가서 이르되 내가 여기 있나이다 당신이 나를 부르셨기 때문입니다. 엘리는 여호와께서 그 아이를 불렀다. 그러므로 엘리가 사무엘에게 이르되 가서 누우라 그가 너를 부르면 너는 여호와여 말씀하소서 하라. 주의 종이 듣겠나이다. 그래서 사무엘은 가서 그 자리에 누웠습니다. 여호와께서 임하여 서서 전과 같이 사무엘아 사무엘아 부르시는지라 그러자 사무엘이 대답했습니다. “말씀하십시오. 주의 종이 듣겠나이다.'),
  ('evt_jdg_samuel_mizpah', '사무엘이 이르되 온 이스라엘은 미스바로 모이라 내가 너희를 위하여 여호와께 기도하리라 그들이 미스바에 모여 물을 길어 여호와 앞에 붓고 그 날에 금식하고 거기서 이르되 우리가 여호와께 죄를 범하였나이다 하니라 사무엘은 미스바에서 이스라엘 자손을 다스렸습니다. 이스라엘 자손이 미스베에 모였다는 소식을 블레셋 사람들이 듣고, 블레셋 방백들이 이스라엘을 치러 올라왔다. 이스라엘 자손은 이 말을 듣고 블레셋 사람들을 두려워했습니다. 이스라엘 자손이 사무엘에게 이르되 당신은 우리를 위하여 우리 하나님 여호와께 쉬지 말고 부르짖어 우리를 블레셋 사람들의 손에서 구원하시게 하소서 사무엘이 젖 먹는 어린 양 한 마리를 가져다가 온전히 여호와께 번제물로 드리고 이스라엘을 위하여 여호와께 부르짖으니라. 여호와께서 그의 말을 들으셨다. 사무엘이 번제를 드릴 때에 블레셋 사람들이 이스라엘과 싸우려고 가까이 오매 그 날에 여호와께서 큰 우뢰로 그 위에 우렛소리를 발하시니라 블레셋 사람들을 괴롭게 하였으니 그들은 이스라엘 앞에서 패하였다. 이스라엘 사람들은 미스바에서 나가서 블레셋 사람들을 추격하여 벧갈 아래에 이르기까지 쳤더라. 사무엘이 돌을 취하여 미스바와 센 사이에 세워 이르되 여호와께서 여기까지 우리를 도우셨다 하고 그 이름을 에벤에셀이라 하니라'),
  ('evt_jdg_samuel_anoints_saul', '사무엘이 기름병을 가져다가 그의 머리에 붓고 그에게 입맞추며 이르되 여호와께서 너를 그의 기업의 총리로 기름부으셨음이 아니냐 네가 오늘 나를 떠나가거든 베냐민 경계 셀사에 있는 라헬의 무덤 곁에서 두 사람을 만나리라. 사람이 네게 이르기를 네가 찾으러 갔던 암나귀들을 찾았으나 보라 네 아버지가 당나귀 돌보는 일을 그치고 너를 위하여 근심하여 이르되 내 아들을 위하여 어떻게 할까 하리라 하리라. 네가 거기서 앞으로 나아가서 다볼 평지에 이르라 거기서 벧엘로 하나님께로 올라가는 세 사람을 만나리니 한 사람은 어린아이 셋을 안고 한 사람은 떡 세 덩이를 가지고 또 한 사람은 포도주 한 가죽 부대를 가지고 네게 문안하고 떡 두 덩이를 주리라 너는 그것을 그들의 손에서 받을 것이다. 그 후에 네가 하나님의 산에 이르리니 거기 블레셋 사람의 수비대가 있는 곳이니라 네가 그 곳에 이르면 그 일이 되리라 성읍에서 네가 양금과 소고와 피리와 수금을 가지고 산당에서 내려오는 한 무리의 선지자들을 만나리니 그들은 예언할 것이요, 네게는 여호와의 신이 임하리니 너도 그들과 함께 예언을 하고 변하여 새 사람이 되리라. 이런 표적이 네게 임하거든 너는 기회에 따라 행하라. 하나님이 너와 함께 계시기 때문이다. 너는 나보다 먼저 길갈로 내려가라. 보라, 내가 네게로 내려가서 번제와 화목제를 드리리니 내가 네게 가서 네가 무엇을 할지 가르칠 때까지 너는 칠 일 동안 기다리라. 이에 그가 사무엘에게서 떠나려고 몸을 돌이켰을 때에 하나님이 그에게 새 마음을 주셨고 그 날 그 표징도 다 응하였느니라.'),
  ('evt_mon_saul_jabesh_victory', '이에 암몬 사람 나하스가 올라와서 길르앗 야베스를 대하여 진 쳤더니 야베스 모든 사람들이 나하스에게 이르되 우리와 언약하라 그리하면 우리가 너를 섬기리라. 암몬 사람 나하스가 그들에게 대답하되 내가 너희 오른 눈을 다 빼어 너희와 언약을 세우리니 이것이 온 이스라엘을 욕되게 하리라 야베스 장로들이 그에게 이르되 우리에게 칠일 동안 유예를 주소서 우리가 이스라엘 온 지역에 사자를 보내게 하소서 그 후에 우리를 구원할 사람이 없으면 당신에게로 나아가리이다 이에 사자들이 사울의 기브아에 이르러 백성의 귀에 이 소식을 전하매 모든 백성이 소리를 높여 울더라. 그런데 보라, 사울이 들에서 떼를 몰고 오는지라. 사울이 이르되, 백성들이 어찌하여 우느냐? 그리고 그들은 야베스 사람들의 소식을 그에게 전했습니다. 사울이 이 소식을 듣자 하나님의 영이 사울에게 임하였고 그의 분노가 심히 불타올랐다. 그리고 그는 한 겨리의 소를 가져다가 그것을 쪼개어 쪼개고 사자들의 손으로 그들을 이스라엘 온 지경에 두루 보내며 이르되 누구든지 사울과 사무엘을 따르지 아니하면 그 소들도 이와 같이 하리라 하였느니라 그러자 백성들이 여호와를 두려워하고 한마음으로 나왔습니다. 그가 베섹에서 그들을 계수하니 이스라엘 자손이 삼십만이요 유다 사람이 삼만이었더라 온 사자들에게 이르되 너희는 길르앗 야베스 사람들에게 이같이 이르기를 내일 해가 더울 때에는 너희가 구원을 받으리라 하라 사자들이 와서 그것을 야베스 사람들에게 고하니라. 그리고 그들은 기뻤습니다. 그러므로 야베스 사람들이 이르되 우리가 내일 너희에게로 나오리니 너희가 좋게 여기는 대로 다 우리에게 행하라 하였느니라 이튿날 사울은 백성을 세 떼로 나누었습니다. 그들이 새벽에 진 가운데로 들어가서 날이 더울 때까지 암몬 자손을 쳐죽이고 남은 자들이 흩어지니라 그 중 두 개는 함께 남아 있지 않았습니다.'),
  ('evt_mon_saul_rejected', '사무엘이 가로되 여호와께서 번제와 다른 제사를 그 말씀 순종하는 것을 좋아하심 같이 좋아하시나이까 보라 순종이 제사보다 낫고 듣는 것이 수양의 기름보다 나으니라 거역하는 것은 마술과 같고 완고함은 불법과 우상 숭배와 같으니라. 네가 여호와의 말씀을 버렸으므로 여호와께서도 너를 버려 왕이 되지 못하게 하셨느니라 사울이 사무엘에게 이르되 내가 여호와의 명령과 당신의 말씀을 어기므로 죄를 범하였나니 이는 내가 백성을 두려워하고 그들의 말을 청종하였음이니라 그러므로 이제 청컨대 나의 죄를 사하시고 나와 함께 돌아와서 나로 여호와께 경배하게 하옵소서. 사무엘이 사울에게 이르되 나는 당신과 함께 돌아가지 아니하리니 이는 당신이 여호와의 말씀을 버렸고 여호와께서도 당신을 버려 이스라엘 왕이 되지 못하게 하셨음이니이다. 사무엘이 돌아서 가려고 하다가 자기 겉옷 자락을 붙잡으니 옷이 찢어지더라. 사무엘이 그에게 이르되 여호와께서 오늘 이스라엘 나라를 왕에게서 떼어 주시고 네 이웃에게 주는 것이 너보다 나으니라'),
  ('evt_mon_saul_gilboa_death', '블레셋 사람들이 이스라엘을 쳤더니 이스라엘 사람들이 블레셋 사람들 앞에서 도망하여 길보아 ​​산에서 엎드러져 죽으니라. 블레셋 사람들은 사울과 그의 아들들을 맹렬하게 추격했습니다. 블레셋 사람들은 사울의 아들 요나단과 아비나답과 멜기수아를 죽였습니다. 사울과의 전투가 치열해져서 궁수들이 그를 쳤습니다. 그는 궁수들에게 심한 부상을 입었습니다. 그러자 사울이 그의 무기병에게 말했습니다. “칼을 뽑아 나를 찌르십시오. 그렇지 않으면 이 할례받지 않은 자들이 와서 나를 밀어붙이고 나를 학대할까 두렵습니다. 그러나 그의 무기를 든 자는 그렇게 하지 않았습니다. 왜냐하면 그는 몹시 두려워했기 때문입니다. 그러므로 사울은 칼을 들고 그 위에 엎드러졌다. 무기를 든 자가 사울의 죽음을 보고 자기도 자기 칼 위에 엎드러져 그와 함께 죽으니라. 그리하여 사울과 그의 세 아들과 그의 무기병과 그의 모든 사람들이 그 날에 함께 죽었느니라.'),
  ('evt_mon_david_anointed', '사무엘이 이새에게 이르되 네 자녀가 다 여기 있느냐? 그가 이르되 아직 막내가 남았는데 보라 그가 양을 지키느니라 사무엘이 이새에게 이르되 사람을 보내어 그를 데려오라 그가 여기 오기 전에는 우리가 앉지 아니하리라 하니라 그가 사람을 보내어 그를 데려왔더니 그 사람이 붉고 용모가 아름답고 보기에 좋았더라. 여호와께서 이르시되 일어나 그에게 기름을 부으라 이는 그가니라 사무엘이 기름 뿔을 가져다가 그의 형제 중에서 그에게 부었더니 이 날 이후로 다윗이 여호와의 신에게 크게 감동되니라 그래서 사무엘은 일어나 라마로 갔습니다.'),
  ('evt_mon_david_jerusalem', '왕과 그의 사람들이 예루살렘으로 가서 그 땅 주민 여부스 사람에게 이르매 그들이 다윗에게 말하여 이르되 네가 맹인과 저는 사람을 제하여 내지 아니하면 이리로 들어오지 못하리라 생각하니 다윗은 이리로 들어오지 못하리라 생각하였더라. 그럼에도 불구하고 다윗은 시온의 견고한 성을 빼앗았으니 다윗 성도 그러하니라. 그 날에 다윗이 이르되 누구든지 시궁창에 올라가서 다윗의 마음에 미워하는 여부스 사람과 절뚝발이와 맹인을 치는 자가 우두머리와 대장이 되리라 하고 그러므로 그들은 말하기를 맹인과 저는 사람은 집에 들어오지 못하리라 하였느니라. 그래서 다윗은 그 요새에 살면서 그 곳을 다윗 성이라고 불렀습니다. 그리고 다윗은 밀로에서부터 안쪽까지 성벽을 쌓았습니다. 다윗이 계속하여 점점 강성해 가는데 만군의 하나님 여호와께서 그와 함께 계시니라.'),
  ('evt_mon_david_covenant', '그러므로 너는 내 종 다윗에게 이같이 이르기를 만군의 여호와의 말씀에 내가 너를 양우리에서, 양을 따르는 중에서 데려다가 내 백성 이스라엘의 통치자로 삼았느니라 네가 어디로 가든지 내가 너와 함께 있어 네 모든 대적을 네 목전에서 제하여 네 이름을 세상에 있는 큰 자들의 이름과 같이 크게 하였느니라 또 내가 내 백성 이스라엘을 위하여 한 곳을 정하여 그들을 심고 그들이 자기 곳에 거하여 다시는 움직이지 못하게 하리라. 악한 자식들이 다시는 그들을 괴롭게 하지 아니하리니 전과 같이 내가 사사들을 명하여 내 백성 이스라엘을 다스리게 하고 너를 모든 대적에게서 평안하게 하던 때와 같으니라 또한 여호와께서 너를 위하여 집을 지으실 것이라고 네게 말씀하시느니라. 네 수한이 차서 네 조상들과 함께 잘 때에 내가 네 몸에서 날 네 씨를 네 뒤에 세워 그의 나라를 견고하게 하리라. 그가 내 이름을 위하여 집을 건축할 것이요 그리고 나는 그의 왕국의 왕위를 영원히 견고하게 할 것이다. 나는 그의 아버지가 되고 그는 내 아들이 될 것이다. 만일 그가 죄를 범하면 내가 사람 채찍과 인생 채찍으로 그를 징계하리라 그러나 내가 네 앞에서 폐한 사울에게서 내 은총을 빼앗은 것 같이 그에게서는 빼앗지 아니하리라 네 집과 네 나라가 네 앞에서 영원히 견고하게 되며 네 왕위가 영원히 견고하리라.'),
  ('evt_mon_solomon_enthroned', '다윗 왕이 이르되 제사장 사독과 선지자 나단과 여호야다의 아들 브나야를 나를 부르라 그리고 그들은 왕 앞으로 나아갔습니다. 왕이 그들에게 이르되 너희는 너희 주의 신하들을 데리고 내 아들 솔로몬을 내 노새에 태워 기혼으로 인도하고 거기서 제사장 사독과 선지자 나단은 그에게 기름을 부어 이스라엘 왕으로 삼고 너희는 나팔을 불며 솔로몬 왕 만세를 외치라 그 후에 너희는 그를 따라 올라와서 내 왕좌에 앉게 될 것이다. 그가 나를 대신하여 왕이 될 것임이라 내가 그를 이스라엘과 유다의 통치자로 임명하였느니라. 여호야다의 아들 브나야가 왕께 대답하여 이르되 아멘. 내 주 왕의 하나님 여호와께서도 그렇게 말씀하시옵소서. 여호와께서 내 주 왕과 함께 계셨던 것 같이 솔로몬도 그와 같이 하시고 그의 왕위를 내 주 다윗 왕의 왕위보다 크게 하시기를 원하나이다 이에 제사장 사독과 선지자 나단과 여호야다의 아들 브나야와 그렛 사람과 블렛 사람이 내려가서 솔로몬은 다윗 왕의 노새를 타고 기혼으로 데려갔습니다. 그리고 제사장 사독은 성막에서 기름 뿔을 가져다가 솔로몬에게 기름을 부었습니다. 그리고 그들은 나팔을 불었습니다. 그러자 모든 백성이 “솔로몬 왕 만세!”라고 말했습니다. 모든 백성이 그를 따라 올라와서 피리를 불며 크게 기뻐하니 땅이 그들의 소리로 인하여 갈라지더라.'),
  ('evt_mon_solomon_temple', '솔로몬이 여호와의 제단 앞에 서서 이스라엘의 온 회중 앞에서 하늘을 향하여 손을 펴고 이르되 이스라엘의 하나님 여호와여 위로 하늘과 아래로 땅에 주와 같은 신이 없나이다 주는 온 마음으로 주의 앞에서 행하는 주의 종들에게 언약을 지키사 은혜를 베푸시며 주의 종 내 아버지 다윗에게 말씀하신 것을 지키시며 주의 입으로 말씀하신 것을 손으로 이루셨나니 이같이 되었나이다 일. 그런즉 이스라엘 하나님 여호와여 원하건대 주의 종 내 아버지 다윗에게 말씀하시기를 이스라엘 왕위에 앉을 사람이 내 목전에서 네게서 끊어지지 아니하리라 하신 말씀을 지키시옵소서 네 자녀들이 그들의 길을 조심하여 네가 내 앞에서 행한 것 같이 그들도 내 앞에서 행하게 하라. 이제 이스라엘의 하나님이여 원하건대 주의 종 내 아버지 다윗에게 하신 말씀이 확실하게 되기를 원하나이다 그러나 하나님이 참으로 땅에 거하실 것인가? 보라 하늘과 하늘들의 하늘이 다 담을 수 없느니라 너를; 하물며 내가 지은 이 집은 얼마나 적느냐? 그러나 나의 하나님 여호와여 주의 종의 기도와 간구를 돌아보시며 종이 오늘 주 앞에서 부르짖는 것과 비는 기도를 들으시옵소서 주께서 말씀하시기를 내 이름이 거기 있으리라 하신 곳을 향하여 주야로 눈이 보이시옵소서 주의 종이 이 곳을 향하여 드리는 기도를 들으시옵소서 주의 종과 주의 백성 이스라엘이 이곳을 향하여 기도할 때에 주는 그 간구함을 들으시되 주는 계신 곳 하늘에서 들으시고 들으시사 사하여 주옵소서.'),
  ('evt_mon_kingdom_divided', '온 이스라엘은 왕이 자기들의 말을 듣지 아니함을 보고 왕에게 대답하여 이르되 우리가 다윗과 무슨 관계가 있느냐? 우리는 이새의 아들에게서 유업을 얻지 못하리니 이스라엘아 네 장막으로 돌아가라 다윗아 이제 네 집이나 돌보라 그리하여 이스라엘은 자기들의 장막으로 돌아갔습니다. 그러나 유다 성읍들에 거주하는 이스라엘 자손에게는 르호보암이 그들의 왕이 되니라 그러자 르호보암 왕은 조공을 맡은 아도람을 보냈습니다. 그러자 온 이스라엘이 그를 돌로 쳐서 죽였습니다. 그러므로 르호보암 왕이 급히 그를 수레에 태워 예루살렘으로 도망하려 하였더라. 그리하여 이스라엘이 다윗의 집을 배반하여 오늘까지 이르렀습니다. 온 이스라엘이 여로보암이 돌아왔다 함을 듣고 사람을 보내어 그를 회중으로 불러 온 이스라엘의 왕을 삼으니라 유다 지파 외에는 다윗의 집을 따르는 자가 없었더라'),
  ('evt_exr_zerubbabel_return', '이는 바벨론 왕 느부갓네살에게 바벨론으로 사로잡혀 갔더라 사로잡혀 갔다가 예루살렘과 유다에 이르러 각각 자기 성읍으로 돌아간 그 지방 자손은 이러하니라 스룹바벨과 함께 온 자들은 예수아, 느헤미야, 스라야, 르엘라야, 모르드개, 빌산, 미스발, 비그왜, 르훔, 바아나입니다. 이스라엘 백성의 남자 수는 이러합니다.'),
  ('evt_exr_temple_foundation', '성전 기초를 놓을 때 제사장들은 예복을 입고 나팔을 들었고, 레위 사람들은 제금으로 여호와를 찬양했다. 백성은 여호와께 감사하며 큰 소리로 외쳤다. 첫 성전을 보았던 노인들은 통곡했고, 많은 사람은 기쁨으로 환호했다. 기쁨의 소리와 울음의 소리가 섞여 멀리까지 들렸다.'),
  ('evt_exr_temple_completion', '유다의 장로들은 학개와 스가랴의 예언을 따라 성전을 건축했고, 이스라엘의 하나님의 명령과 바사 왕들의 조서에 따라 공사를 마쳤다. 다리오 왕 제육년 아달월 초사흘에 성전이 완공되었다. 이스라엘 자손과 제사장들과 레위 사람들과 포로에서 돌아온 남은 백성은 기쁨으로 하나님의 전 봉헌식을 지켰다.'),
  ('evt_exr_ezra_return', '에스라는 바벨론에서 올라온 율법학사였고, 그의 위에 임한 여호와의 손을 따라 왕에게서 요청한 것을 허락받았다. 이스라엘 사람들과 제사장들과 레위 사람들과 노래하는 자들과 문지기들과 느디님 사람들이 아닥사스다 왕 제칠년에 예루살렘으로 올라왔다. 그는 첫째 달 초하루에 바벨론을 떠나 다섯째 달 초하루에 예루살렘에 이르렀다. 에스라는 여호와의 율법을 연구하고 지키며 이스라엘에 율례와 법도를 가르치기로 마음을 정했다.'),
  ('evt_exr_ezra_reform', '제사장 에스라가 일어나 그들에게 이르되 너희가 범죄하여 이방 아내를 취하여 이스라엘의 죄를 더하였느니라 그런즉 이제 너희 조상의 하나님 여호와께 자복하고 그 뜻을 행하여 이 땅 백성과 이방 여인을 끊어라. 그러자 온 회중이 큰 소리로 대답하여 말했습니다. “당신의 말씀대로 우리가 그렇게 해야 합니다.” 그러나 백성이 많고 비가 많이 내리는 때라 우리가 밖에 서 있을 수 없나니 이는 하루 이틀에 할 일이 아니니 이는 이 일로 범죄한 우리가 많음이라. 이제 우리 온 회중의 관원들은 일어나게 하고 우리 성읍들에서 이방 아내를 취한 모든 자와 각 성의 장로들과 재판관들도 정한 때에 와서 우리 하나님의 이 일로 인한 진노가 우리에게서 떠나기까지 하게 하소서 오직 아사헬의 아들 요나단과 디과의 아들 야하시야만이 이 일에 참여하였고 므술람과 레위 사람 삽브대 그들을 도왔습니다. 포로된 자의 자녀들도 그대로 행하였다. 제사장 에스라와 각 종족의 족장 몇 사람과 각 사람의 이름을 따라 구별하고 열째 달 초하루에 앉아서 그 일을 조사하니라 그리고 첫째 달 초하루에 이방 아내를 취한 모든 남자를 그쳤더라.'),
  ('evt_exr_law_reading', '그러자 모든 백성이 한마음으로 수문 앞 거리로 모였습니다. 그리고 그들은 서기관 에스라에게 여호와께서 이스라엘에게 명령하신 모세의 율법책을 가져오라고 말했습니다. 일곱째 달 초하루에 제사장 에스라가 율법책을 남녀와 알아 들을 수 있는 모든 회중 앞에 가져오매 그리고 그는 수문 앞 거리 앞에서 아침부터 정오까지 남자나 여자나 알아들을 수 있는 모든 사람 앞에서 그것을 읽으니라. 모든 백성이 율법책에 귀를 기울였습니다. 학사 에스라는 그들이 목적을 위해 만든 나무 강단 위에 섰습니다. 그 곁에는 맛디디야와 스마와 아나야와 우리야와 힐기야와 마아세야가 그의 우편에 섰고 그 왼편에는 브다야와 미사엘과 말기야와 하숨과 하스바다나와 스가랴와 므술람이요 에스라가 모든 백성이 보는 앞에서 책을 펴니라. (을 위한 그는 모든 백성 위에 계시니라) 문을 열자 모든 백성이 일어서니 에스라가 위대하신 하나님 여호와를 송축하니라 그러자 모든 백성이 손을 들고 아멘, 아멘 하고 응답하고 머리를 숙여 얼굴을 땅에 대고 여호와께 경배했습니다. 예수아와 바니와 세레뱌와 야민과 악굽과 사브대와 호디야와 마아세야와 그리다와 아사랴와 요사밧과 하난과 블라야와 레위 사람들이 백성에게 율법을 깨닫게 하니 백성은 그 자리에 섰느니라. 그리하여 그들이 하나님의 율법 책을 낭독하고 그 뜻을 해석하여 그 읽는 것을 깨닫게 하였느니라.'),
  ('evt_exr_nehemiah_commission', '아닥사스다 왕 제이십년 니산월에 왕 앞에 포도주가 있기로 내가 그 포도주를 왕에게 드렸더니 이제 나는 이전에 그의 앞에서 슬퍼한 적이 없었습니다. 그러므로 왕이 내게 이르시되 네가 아프지도 아니하였거늘 어찌하여 얼굴에 근심이 있느냐? 이것은 다름 아닌 마음의 슬픔입니다. 내가 심히 두려워하여 왕께 아뢰되 왕은 만세수를 하옵소서 내 조상들의 묘실 있는 성읍이 황폐하고 성문이 불탔사오니 어찌 내 얼굴에 수심이 없겠습니까? 왕이 내게 이르시되 네가 무엇을 구하느냐? 그래서 나는 하늘의 하나님께 기도했습니다. 내가 왕께 아뢰되 왕께서 만일 좋게 여기시고 종이 왕의 목전에서 은혜를 얻었사오면 나를 유다 땅 내 조상들의 묘실이 있는 성읍에 보내사 그 성을 건축하게 하옵소서 하였나이다 왕이 내게 이르시되 (왕후도 그 곁에 앉았으니) 네 여행이 얼마나 걸리겠느냐 ? 그러면 너는 언제 돌아오겠느냐? 그래서 왕께서 나를 보내신 것을 기쁘게 생각합니다. 나는 그에게 시간을 정했습니다. 내가 또 왕께 아뢰되 왕께서 좋게 여기시거든 강 건너편 방백들에게 조서를 주어 내가 유다에 들어갈 때까지 나를 인도하게 하소서 또 왕의 삼림 감독 아삽에게 조서를 내리사 그가 전에 있는 뜰의 문과 성벽과 내가 들어갈 집을 위하여 들보로 쓸 재목을 내게 주게 하소서. 그리고 내 하나님의 선한 손이 나를 도우시므로 왕께서 나에게 허락하셨습니다.'),
  ('evt_exr_nehemiah_wall', '그리하여 성벽 공사는 오십이일 만인 엘룰월 이십오일에 끝났습니다. 우리의 모든 대적과 우리 주위에 있는 모든 이방인이 이 일을 보고 스스로 크게 낙망하였으니 이는 이 일이 우리 하나님으로 말미암아 된 줄 알았음이니라'),
  ('evt_exr_nehemiah_covenant', '이 모든 것 때문에 우리는 확실한 언약을 세워 기록합니다. 인친 자는 느헤미야와 하가랴의 아들 디르사다와 시드기야와 스라야와 아사랴와 예레미야와 바스훌과 아마랴와 말기야와 핫두스와 스바냐와 말룩과 하림과 므레못과 오바댜와 다니엘과 긴느돈과 바룩과 므술람과 아비야와 미야민과 마아시야, 빌개, 스마야니 이들은 제사장들이요 레위 사람은 아사냐의 아들 예수아와 헤나닷 자손 중 빈누이와 갓미엘과 그리고 그들의 형제들은 스바냐, 호디야, 글리타, 블라야, 하난, 미가, 르홉, 하사뱌, 삭굴, 세레뱌, 스바냐, 호디야, 바니, 베니누이다. 국민의 우두머리; 바로스, 바핫모압, 엘람, 삿두, 바니, 분니, 아스갓, 베배, 아도니야, 비그왜, 아딘, 아델, 히스기야, 앗술, 호디야, 하숨, 브새, 하립, 아나돗, 느배, 막비아스, 므술람, 헤실, 므세사벨, 사독, 얏두아, 블라댜, 하난, 아나야, 호세아, 하나냐, 핫숩, 할로헤스, 빌레하, 소벡, 르훔, 하삽나, 마아세야, 그리고 아히야, 하난, 아난, 말룩, 하림, 바아나입니다. 남은 백성과 제사장들과 레위 사람들과 문지기들과 노래하는 자들과 느디님 사람들과 이방 사람과 절교하여 하나님의 율법을 준행하는 모든 자와 그들의 아내와 그들의 아들과 딸들이 다 지식과 총명이 있는 자라 그들은 자기 형제 귀족들과 연합하여 저주로 맹세하기를, 하나님의 종 모세를 통하여 주신 하나님의 율법을 지켜 우리 주 여호와의 모든 계명과 율례와 율례를 지켜 행하기로 작정하였느니라.')
) as s(code, story)
where e.code = s.code;
-- End generated story block

-- Generated: short_story from story (first ~5 sentences)
with short_src as (
  select
    id,
    array_to_string(
      (
        regexp_split_to_array(
          regexp_replace(replace(coalesce(story, ''), E'\n', ' '), E'\\s+', ' ', 'g'),
          E'\\s*[.!?]+\\s+'
        )
      )[1:5],
      '. '
    ) as summarized
  from events
)
update events e
set short_story = case
  when trim(coalesce(s.summarized, '')) = '' then null
  when right(trim(s.summarized), 1) = '.' then trim(s.summarized)
  else trim(s.summarized) || '.'
end
from short_src s
where e.id = s.id;

-- -----------------------------------------------------------------------------
-- Seed: quiz_questions
-- -----------------------------------------------------------------------------
with seed_quiz (
  event_code,
  question,
  choice_a,
  choice_b,
  choice_c,
  choice_d,
  answer_index,
  explanation,
  display_order
) as (
  values
    ('evt_pri_adam_creation', '하나님이 인간을 어떤 본질로 창조하셨다는 내용인가요?', '하나님의 형상과 모양', '동물들의 왕', '영원한 천사', '흙덩이의 무기력함', 0, '인간은 하나님 형상으로 지음 받은 존재로서 하나님의 형상을 닮은 책임 있는 존재입니다.', 1),
    ('evt_pri_adam_fall', '타락 사건의 핵심은 무엇인가요?', '동산의 축복', '아담의 기도', '하나님을 거역한 불순종', '자손의 탄생', 2, '에덴에서의 불순종은 인간 역사에 죄와 고통을 초래한 분수령입니다.', 1),
    ('evt_pri_adam_cain_abel', '가인과 아벨의 갈등에서 반복되는 핵심 경고는?', '형제의 질투', '축복의 경쟁', '농사 기술', '성전 건축', 0, '가인과 아벨의 장면은 질투와 분노가 폭력으로 번질 수 있음을 보여 줍니다.', 1),
    ('evt_pri_noah_ark', '노아가 방주를 건축하도록 명하신 배경은?', '성전 재건', '심판 전 예고와 구원의 준비', '바벨탑 시도', '왕국 확장', 1, '홍수 심판을 앞두고 노아의 순종이 구원의 통로가 되었습니다.', 1),
    ('evt_pri_noah_flood', '홍수 후 하나님과의 약속을 상기시키는 표지는?', '십계명', '무지개', '성막', '율법서', 1, '무지개는 심판 이후 자비의 약속의 표징입니다.', 1),
    ('evt_pri_noah_covenant', '무지개 언약은 어떤 의미인가요?', '새로운 우상 제시', '심판의 반복', '하나님의 자비 약속', '이스라엘의 세습 규칙', 2, '홍수 심판이 영원히 반복되지 않음을 보증하는 언약입니다.', 1),

    ('evt_pat_abraham_call', '아브라함의 부르심 핵심은?', '본토에서 영원히 머물기', '가나안 정복 전쟁', '낯선 땅으로의 순종적 이동', '요셉을 찾기', 2, '아브라함은 하란을 떠나 약속의 땅을 향한 부르심에 순종했습니다.', 1),
    ('evt_pat_abraham_covenant', '아브라함 언약에서 하나님이 분명히 주신 것은?', '즉각적인 부와 권력', '전쟁 승리', '후손과 땅의 약속', '새벽 기도법', 2, '언약은 장차 받을 약속의 약속입니다.', 1),
    ('evt_pat_isaac_birth', '이삭의 출생으로 보여준 메시지는?', '예정된 약속의 성취', '부모의 실패', '야곱의 실패', '요셉의 추방', 0, '불가능해 보이는 약속이 하나님의 약속으로 성취됨을 드러냅니다.', 1),
    ('evt_pat_abraham_moriah', '모리아 사건에서 아브라함이 보여 준 태도는?', '분노', '회개 거부', '순종의 신뢰', '지도력 탐욕', 2, '이삭 제사는 아브라함의 신뢰와 순종을 극명하게 드러냅니다.', 1),
    ('evt_pat_isaac_wells', '이삭의 우물 사건에서 드러난 핵심은?', '무력한 항복', '물과 자원을 둘러싼 분쟁의 화해', '성전 건축', '왕권 승계', 1, '우물은 생존 자원을 둘러싼 신뢰의 문제이자 평화의 훈련장이었습니다.', 1),
    ('evt_pat_isaac_blessing', '야곱이 축복을 받게 된 장면은 무엇을 바꾸었나요?', '전쟁의 영구화', '축복의 계승자', '왕권 폐지', '유언의 삭제', 1, '축복은 약속의 계보가 이스라엘로 이어지는 전환점입니다.', 1),
    ('evt_pat_jacob_bethel', '야곱의 벧엘 경험의 주요 결론은?', '망각', '언약의 재확인', '신분 상실', '순식간의 부활', 1, '하나님의 약속을 기억하고 다시 일어서는 신앙의 회복을 보여 줍니다.', 1),
    ('evt_pat_jacob_haran', '하란 체류 기간의 성격은?', '단 한 주', '단기 여행', '장기 노동과 가정 형성', '즉각적 귀환', 2, '하란은 인생 재정비와 인내의 시기였습니다.', 1),
    ('evt_pat_jacob_jabbok', '얍복강에서의 씨름은 결국 무엇으로 이어졌나요?', '패배', '새 이름과 사명', '즉시 귀환', '예루살렘 정복', 1, '야곱의 씨름은 정체성 전환과 책임 수용을 상징합니다.', 1),
    ('evt_pat_jacob_egypt_migration', '야곱 가족의 애굽 이주는 무엇을 예고하나요?', '전면 전쟁', '족장 시대 마무리와 새로운 국면', '왕국 건국', '예루살렘 왕위 획득', 1, '가뭄과 기근 속 이동이 이후 이스라엘 역사의 전환을 만듭니다.', 1),
    ('evt_pat_joseph_sold', '요셉이 팔려난 뒤 시작된 주요 흐름은?', '바로의 즉시 즉위', '집안 분열의 완성', '해방과 회복의 연쇄', '이스라엘 분열', 2, '고난이 이후 구원의 통로로 전환됩니다.', 1),
    ('evt_pat_joseph_rise', '요셉의 애굽 총리 등극이 상징하는 것은?', '자기 과시', '제도적 통치와 책임', '순수 영성만', '왕권 부정', 1, '요셉은 꿈 해석과 행정 능력으로 백성의 삶을 안정시켰습니다.', 1),
    ('evt_pat_joseph_reconcile', '형제와 요셉의 화해는 어떤 메시지인가요?', '보복의 정당화', '회개의 필요', '왕권 쟁탈', '유산 분할', 1, '형제간 상처를 넘어 공동체 회복이 가능한 것을 보여 줍니다.', 1),

    ('evt_ex_moses_burning_bush', '모세의 첫 부르심은 어디서 주어졌나요?', '시나이 산 정상', '홍해', '홉기나무', '호렙산의 떨기나무', 3, '모세는 호렙산의 떨기나무에서 하나님의 부르심을 받습니다.', 1),
    ('evt_ex_plagues_passover', '유월절의 제도는 무엇을 기억하기 위한 것인가요?', '예루살렘 왕위', '하나님의 해방 약속', '가나안 정복', '왕의 탄생', 1, '유월절은 억압에서의 구원을 신앙적으로 기억하게 하는 표지입니다.', 1),
    ('evt_ex_red_sea_crossing', '홍해 도하의 본질은?', '전투 회피', '배를 건조', '해방의 길', '교역의 시작', 2, '바다가 길이 열리며 노예 신분에서 해방의 정체성으로 전환됩니다.', 1),
    ('evt_ex_sinai_covenant', '시내산에서 백성이 얻게 된 것은?', '왕위 계승', '언약과 율법', '새로운 제사장직만', '군사 훈련법', 1, '시내산은 공동체 규범의 시작점입니다.', 1),
    ('evt_ex_wilderness_serpent', '놋뱀 사건의 목적은?', '새로운 사역자의 탄생', '불평의 증명', '회개와 회복', '왕정 정당화', 2, '불평이 극에 달한 백성에게 신뢰 회복의 상징이 된 장면입니다.', 1),
    ('evt_ex_moses_death_nebo', '모세의 마지막은 어떤 리더십 메시지인가요?', '완성된 승리', '좌절의 기록', '후계의 전수', '권력 독점', 2, '모세는 목표를 대신 다음 세대에 위임한 채 생애를 마칩니다.', 1),
    ('evt_ex_aaron_golden_calf', '금송아지 사건은 무엇을 경고하나요?', '우상과 쉽게 돌아가는 경향', '평화 협상', '왕실 건축', '율법의 반영', 0, '공포의 순간 공동체는 신앙의 핵심을 쉽게 잃을 수 있음을 보여 줍니다.', 1),
    ('evt_ex_aaron_rod', '아론의 지팡이 표징은 무엇을 보증하나요?', '인간의 세력 경쟁', '제사장직의 정당성', '바다의 지배', '재산 분배', 1, '지팡이는 하나님의 선택으로 리더십이 확인됨을 뜻합니다.', 1),
    ('evt_ex_aaron_death_hor', '아론의 죽음이 남긴 메시지는?', '권력의 종결', '봉직의 전환', '언약의 파기', '새 왕조 즉위', 1, '세대 전환 시 직분과 책임이 계승됨을 보여 줍니다.', 1),

    ('evt_jdg_joshua_jordan_crossing', '요단강 도하는 무엇의 상징인가요?', '귀환의 상실', '정복의 시작', '약속의 땅 입성', '에덴 회귀', 2, '요단강 도하는 가나안 입성의 신학적 전환점입니다.', 1),
    ('evt_jdg_joshua_jericho', '여리고 함락에서 강조되는 핵심은?', '전투 장비', '규칙 없는 공격', '순종한 신앙 행위', '무장 증강', 2, '질서 있는 순종이 승리를 가능하게 했습니다.', 1),
    ('evt_jdg_joshua_shechem_covenant', '세겜 언약 갱신의 목적은?', '왕권 강화', '전사 모집', '공동체 윤리 재확인', '새 왕가 수립', 2, '정복 이후 정체성을 지키기 위한 규범 확인입니다.', 1),
    ('evt_jdg_cycle_begins', '사사 시대의 반복 패턴에 처음 들어간 핵심은?', '번영만 지속', '배반-압제-구원', '지속적 율법', '왕권 안정', 1, '배반과 억압이 반복될 때 회개의 필요가 강해집니다.', 1),
    ('evt_jdg_deborah_victory', '드보라와 바락의 협력은 무엇을 보여 주나요?', '남성 지도자만 유효', '여성 지도력의 가능성', '우연의 승리', '성전 중심 정치', 1, '은혜는 성별과 관계없이 하나님의 구원 도구로 세워줍니다.', 1),
    ('evt_jdg_gideon_victory', '기드온의 승리는 숫자보다 무엇이 중요했나요?', '무기도구 수', '작전비밀', '분별된 신뢰', '왕의 훈령', 2, '소수라도 하나님의 지혜와 분별을 따라 전술이 완성됩니다.', 1),
    ('evt_jdg_samson_finale', '삼손의 마지막 사건이 드러낸 것은?', '완전한 영적 성숙', '약한 인간의 회복 가능성', '왕권 상속', '율법 폐기', 1, '실수 많은 삶도 하나님께 의탁하면 공적 전환점이 생깁니다.', 1),
    ('evt_jdg_samuel_call', '사무엘의 소명에서 배울 점은?', '권력 추구', '기도와 경청의 습관', '전장 중심 지도', '순간적 기적', 1, '그는 반복되는 음성을 분별하며 듣는 훈련을 갖춘 인물이 됩니다.', 1),
    ('evt_jdg_samuel_mizpah', '미스바 개혁은 어떤 형태의 변화였나요?', '전쟁 영웅 양성', '공적 회개와 회복', '왕의 즉위', '성전 붕괴', 1, '회개가 삶의 규범으로 정착될 때 공동체가 회복됩니다.', 1),
    ('evt_jdg_samuel_anoints_saul', '사울의 기름부음은 무엇을 의미하나요?', '자동 승리', '왕정의 시작', '사사 폐지', '예루살렘 건국', 1, '사울 기름부음은 국가 체제의 시작과 책임의 시작입니다.', 1),

    ('evt_mon_saul_jabesh_victory', '사울의 초기 승리는 어떤 교훈을 남기나요?', '권력은 영속적', '구원은 즉각적', '단기 성과 뒤의 책임', '율법의 제거', 2, '성공은 영속적 통치의 증거가 아니라 책임의 시작입니다.', 1),
    ('evt_mon_saul_rejected', '사울이 폐위되는 결정적 이유는?', '군사 무능', '우상숭배 선언', '불순종과 자기의', '백성의 반란', 2, '제사와 전리품보다 순종과 마음의 정직이 왕으로서의 핵심입니다.', 1),
    ('evt_mon_saul_gilboa_death', '길보아 전사는 어떤 전환을 가져오나요?', '왕정의 완성', '지도력 교체의 필요성', '왕권 강화', '신정시대 도입', 1, '한 지도자의 몰락은 공동체 통합의 필요를 드러냅니다.', 1),
    ('evt_mon_david_anointed', '다윗이 기름 부음을 받는 것은?', '왕권 약속의 시작', '패배의 선언', '사무엘의 폐위', '무관한 의식', 0, '다윗의 즉위는 전환기 지도력과 언약의 출발점입니다.', 1),
    ('evt_mon_david_jerusalem', '예루살렘 정복의 결과는?', '전술 훈련 종료', '우상숭배 강화', '국가 중심의 재구성', '왕권 포기', 2, '예루살렘 정복은 중심지 획득이자 통치 질서의 확립입니다.', 1),
    ('evt_mon_david_covenant', '다윗 언약의 핵심은?', '완전한 인간성', '예언과 왕권 단절', '지속적 언약의 보증', '군사력 고갈', 2, '다윗의 한계 속에서도 약속은 지속됨을 보여 줍니다.', 1),
    ('evt_mon_solomon_enthroned', '솔로몬 즉위는 무엇을 알리나요?', '분열의 시작', '국정 리더십 정착', '사사 복귀', '출애굽 재현', 1, '국정을 안정적으로 운영하기 위한 운영 체계를 세운 순간입니다.', 1),
    ('evt_mon_solomon_temple', '성전 봉헌의 의미는?', '정치 행사의 축소', '예배 중심 완성', '농업의 단절', '제사장 해산', 1, '성전 봉헌은 예배적 중심을 세우는 중대한 사건입니다.', 1),
    ('evt_mon_kingdom_divided', '왕국 분열은 어떤 경고인가요?', '번영의 결과', '불의의 누적', '사사 시대 폐쇄', '바벨론 정복', 1, '번영 뒤의 불공정과 경직이 분열을 가져왔습니다.', 1),

    ('evt_exr_zerubbabel_return', '1차 귀환의 핵심은 무엇인가요?', '사라진 문화의 회복', '새 왕국 건설', '정복 확장', '권력의 이양', 0, '포로 후 공동체가 예루살렘으로 돌아가는 시작입니다.', 1),
    ('evt_exr_temple_foundation', '성전 기초 재건은 무엇의 상징인가요?', '전쟁 준비', '정체성 재건', '왕의 확장', '사법 제도', 1, '기초를 놓는 행위는 예배 중심 회복의 상징적 시작입니다.', 1),
    ('evt_exr_temple_completion', '성전 완공으로 가장 잘 드러난 것은?', '영적 지연의 끝', '지속적 예배의 중심', '왕권 강화', '바다 이동', 1, '완공은 예배와 공동체 회복의 성숙한 단계입니다.', 1),
    ('evt_exr_ezra_return', '에스라 귀환의 목적은?', '군사 지휘 확립', '말씀 중심 개혁', '성전 봉헌', '왕위 박탈', 1, '에스라는 말씀으로 공동체의 규범을 재정비했습니다.', 1),
    ('evt_exr_ezra_reform', '에스라의 개혁에서 핵심은?', '의식만 강조', '공동체의 삶 정비', '부족의 이동', '방언 통제', 1, '개혁은 규범이 삶으로 내려올 때 완성됩니다.', 1),
    ('evt_exr_law_reading', '율법 낭독은 단지 읽기보다 무엇에 가깝나요?', '기록 보존', '교육과 적용', '예식의 과장', '군사 동원', 1, '말씀을 함께 읽고 판단하는 과정이 공동체 성숙의 시작입니다.', 1),
    ('evt_exr_nehemiah_commission', '느헤미야 파송의 상징은?', '즉시 반란', '교회 분열', '행정적 리더십의 출발', '언약 문서 파기', 2, '느헤미야는 행정적 결단으로 성벽 재건 프로젝트를 시작했습니다.', 1),
    ('evt_exr_nehemiah_wall', '성벽 재건 완성은 무엇을 보여줍니까?', '지식 교육 완성', '지역 수비와 연합', '왕권 수립', '전쟁 종식', 1, '성벽은 연합과 규율의 결실입니다.', 1),
    ('evt_exr_nehemiah_covenant', '언약 갱신의 목적은?', '경제 성장', '문서 수집', '신앙과 행정의 재확인', '성전 봉헌', 2, '갱신은 기억된 약속을 일상의 행동으로 되돌리는 과정입니다.', 1)
)
insert into quiz_questions (
  event_id,
  question,
  choice_a,
  choice_b,
  choice_c,
  choice_d,
  answer_index,
  explanation,
  display_order
)
select
  e.id,
  s.question,
  s.choice_a,
  s.choice_b,
  s.choice_c,
  s.choice_d,
  s.answer_index,
  s.explanation,
  s.display_order
from seed_quiz s
join events e on e.code = s.event_code
;

-- -----------------------------------------------------------------------------
-- Seed: New Testament (구약/신약 분리 + 예수/바울)
-- -----------------------------------------------------------------------------
alter table eras
  add column if not exists testament text not null default 'old';

update eras
set testament = 'old'
where coalesce(testament, '') <> 'new';

insert into eras (
  code,
  testament,
  name,
  display_order,
  start_year,
  end_year,
  theme_color,
  map_center_lat,
  map_center_lng,
  map_zoom
)
values
  ('era_nt_public_ministry', 'new', '예수님의 공생애', 1, 27, 33, '#9F642A', 31.78, 35.22, 6.10),
  ('era_nt_apostolic', 'new', '사도의 시대', 2, 33, 70, '#7D5A3A', 37.40, 26.90, 4.90),
  ('era_nt_post_apostolic', 'new', '후기 사도의 시대', 3, 70, 100, '#6C5646', 37.45, 27.20, 5.20),
  ('era_nt_consummation', 'new', '역사의 종결', 4, null, null, '#8B6B4A', 31.78, 35.22, 4.40)
on conflict (code) do update
set
  testament = excluded.testament,
  name = excluded.name,
  display_order = excluded.display_order,
  start_year = excluded.start_year,
  end_year = excluded.end_year,
  theme_color = excluded.theme_color,
  map_center_lat = excluded.map_center_lat,
  map_center_lng = excluded.map_center_lng,
  map_zoom = excluded.map_zoom
;

insert into persons (
  code,
  name,
  tagline,
  avatar_url,
  description,
  is_active
)
values
  ('jesus', '예수님', '하나님 나라의 복음', 'assets/avatars/jesus.png', '복음을 전하고 십자가와 부활로 구원을 이루신 메시아', true),
  ('paul', '바울', '이방 선교의 사도', 'assets/avatars/paul.png', '회심 이후 여러 선교 여행으로 복음을 전한 사도', true),
  ('eve', '하와', '모든 산 자의 어머니', 'assets/avatars/eve.png', '창조와 타락 서사에서 아담과 함께 인류의 시작점에 선 인물', true),
  ('cain', '가인', '첫 농부', 'assets/avatars/cain.png', '가인과 아벨 사건으로 죄의 확산을 보여주는 인물', true),
  ('sarah', '사라', '약속의 어머니', 'assets/avatars/sarah.png', '늦은 나이에 약속의 아들 이삭을 낳은 족장 시대의 핵심 인물', true),
  ('rebekah', '리브가', '언약 가문의 계승자', 'assets/avatars/rebekah.png', '이삭의 아내로서 언약 가문 계승의 전환점에 선 인물', true),
  ('leah', '레아', '가문의 기초 어머니', 'assets/avatars/leah.png', '야곱 가문 안에서 지파 계보 형성에 중요한 위치를 차지한 인물', true),
  ('rachel', '라헬', '요셉의 어머니', 'assets/avatars/rachel.png', '야곱 가문 이야기에서 요셉과 베냐민의 어머니로 기억되는 인물', true),
  ('miriam', '미리암', '출애굽의 찬양 리더', 'assets/avatars/miriam.png', '출애굽 공동체에서 찬양과 예언 사역으로 함께한 인물', true),
  ('caleb', '갈렙', '끝까지 믿은 정탐꾼', 'assets/avatars/caleb.png', '정탐 사건에서 신뢰의 보고를 지킨 광야 세대의 대표 인물', true),
  ('deborah', '드보라', '사사이자 예언자', 'assets/avatars/deborah.png', '사사 시대에 말씀과 리더십으로 공동체를 이끈 여성 지도자', true),
  ('gideon', '기드온', '300용사의 사사', 'assets/avatars/gideon.png', '적은 수로 미디안을 물리친 사사 시대의 대표 인물', true),
  ('samson', '삼손', '힘의 사사', 'assets/avatars/samson.png', '블레셋과의 갈등 속에서 사사 시대의 긴장을 보여주는 인물', true),
  ('ruth', '룻', '충성의 여인', 'assets/avatars/ruth.png', '모압에서 와서 언약 공동체에 헌신한 다윗 계보의 핵심 인물', true),
  ('naomi', '나오미', '회복의 증인', 'assets/avatars/naomi.png', '상실 이후 룻과 함께 회복 서사를 열어가는 인물', true),
  ('boaz', '보아스', '기업 무를 자', 'assets/avatars/boaz.png', '룻을 보호하고 가문을 세운 구속자 역할의 인물', true),
  ('esther', '에스더', '민족을 구한 왕후', 'assets/avatars/esther.png', '페르시아 시대 위기에서 민족을 위해 중보한 왕후', true),
  ('elijah', '엘리야', '갈멜산의 선지자', 'assets/avatars/elijah.png', '우상 숭배와 대결하며 여호와 신앙을 선포한 선지자', true),
  ('elisha', '엘리사', '회복의 선지자', 'assets/avatars/elisha.png', '엘리야 뒤를 이어 표적과 치유 사역을 감당한 선지자', true),
  ('isaiah', '이사야', '거룩을 본 선지자', 'assets/avatars/isaiah.png', '유다 왕정기에 거룩과 메시아 소망을 선포한 대선지자', true),
  ('jeremiah', '예레미야', '눈물의 선지자', 'assets/avatars/jeremiah.png', '멸망 직전 유다에 회개와 새 언약을 선포한 선지자', true),
  ('daniel', '다니엘', '포로지의 신실한 증인', 'assets/avatars/daniel.png', '바벨론과 페르시아 궁정에서 신앙의 정체성을 지킨 인물', true),
  ('mary', '마리아', '순종의 어머니', 'assets/avatars/mary.png', '예수 탄생 서사에서 하나님의 뜻에 순종으로 응답한 인물', true),
  ('peter', '베드로', '사도단의 기둥', 'assets/avatars/peter.png', '예수의 수제자에서 초대교회 리더로 세워진 사도', true),
  ('andrew', '안드레', '인도하는 제자', 'assets/avatars/andrew.png', '사람을 예수께 인도하는 사역으로 알려진 제자', true),
  ('james_zebedee', '야고보(세베대의 아들)', '열정의 제자', 'assets/avatars/james_zebedee.png', '세베대의 아들로서 초기 제자 공동체 핵심에 선 인물', true),
  ('john', '요한', '사랑의 제자', 'assets/avatars/john.png', '예수의 가까운 제자로서 복음 증언을 이어간 사도', true),
  ('philip', '빌립', '안내하는 제자', 'assets/avatars/philip.png', '사람들을 예수께 연결하는 역할이 두드러진 제자', true),
  ('bartholomew', '바돌로매', '진실한 제자', 'assets/avatars/bartholomew.png', '나다나엘로도 알려진 정직한 제자', true),
  ('matthew', '마태', '세리에서 제자로', 'assets/avatars/matthew.png', '세리의 자리에서 부르심을 받아 복음 증언자가 된 제자', true),
  ('thomas', '도마', '의심에서 고백으로', 'assets/avatars/thomas.png', '의심을 지나 주님 고백으로 나아간 제자', true),
  ('james_alphaeus', '야고보(알패오의 아들)', '조용한 충성의 제자', 'assets/avatars/james_alphaeus.png', '열두 제자 명단 안에서 꾸준한 충성으로 기억되는 제자', true),
  ('thaddaeus', '다대오(유다)', '질문하는 제자', 'assets/avatars/thaddaeus.png', '주님께 묻고 배우며 따랐던 열두 제자', true),
  ('simon_zealot', '시몬(셀롯)', '열심에서 복음으로', 'assets/avatars/simon_zealot.png', '열심당 배경에서 복음의 제자로 변화된 인물', true),
  ('judas_iscariot', '가룟 유다', '배신의 경고', 'assets/avatars/judas_iscariot.png', '예수를 팔아넘긴 사건으로 경고를 남긴 제자', true)
on conflict (code) do update
set
  name = excluded.name,
  tagline = excluded.tagline,
  avatar_url = excluded.avatar_url,
  description = excluded.description,
  is_active = excluded.is_active
;

with nt_person_eras (person_code, era_code, display_order) as (
  values
    ('adam', 'era_primeval', 1),
    ('eve', 'era_primeval', 2),
    ('cain', 'era_primeval', 3),
    ('noah', 'era_primeval', 4),

    ('abraham', 'era_patriarch', 1),
    ('sarah', 'era_patriarch', 2),
    ('isaac', 'era_patriarch', 3),
    ('rebekah', 'era_patriarch', 4),
    ('jacob', 'era_patriarch', 5),
    ('leah', 'era_patriarch', 6),
    ('rachel', 'era_patriarch', 7),
    ('joseph', 'era_patriarch', 8),

    ('moses', 'era_exodus', 1),
    ('aaron', 'era_exodus', 2),
    ('miriam', 'era_exodus', 3),
    ('caleb', 'era_exodus', 4),

    ('joshua', 'era_judges', 1),
    ('judges', 'era_judges', 2),
    ('deborah', 'era_judges', 3),
    ('gideon', 'era_judges', 4),
    ('samson', 'era_judges', 5),
    ('ruth', 'era_judges', 6),
    ('naomi', 'era_judges', 7),
    ('boaz', 'era_judges', 8),
    ('samuel', 'era_judges', 9),

    ('saul', 'era_monarchy', 1),
    ('david', 'era_monarchy', 2),
    ('solomon', 'era_monarchy', 3),
    ('elijah', 'era_monarchy', 4),
    ('elisha', 'era_monarchy', 5),
    ('isaiah', 'era_monarchy', 6),
    ('jeremiah', 'era_monarchy', 7),

    ('daniel', 'era_exile_return', 1),
    ('zerubbabel', 'era_exile_return', 2),
    ('esther', 'era_exile_return', 3),
    ('ezra', 'era_exile_return', 4),
    ('nehemiah', 'era_exile_return', 5),

    ('jesus', 'era_nt_public_ministry', 1),
    ('mary', 'era_nt_public_ministry', 2),
    ('peter', 'era_nt_public_ministry', 3),
    ('andrew', 'era_nt_public_ministry', 4),
    ('james_zebedee', 'era_nt_public_ministry', 5),
    ('john', 'era_nt_public_ministry', 6),
    ('philip', 'era_nt_public_ministry', 7),
    ('bartholomew', 'era_nt_public_ministry', 8),
    ('matthew', 'era_nt_public_ministry', 9),
    ('thomas', 'era_nt_public_ministry', 10),
    ('james_alphaeus', 'era_nt_public_ministry', 11),
    ('thaddaeus', 'era_nt_public_ministry', 12),
    ('simon_zealot', 'era_nt_public_ministry', 13),
    ('judas_iscariot', 'era_nt_public_ministry', 14),

    ('paul', 'era_nt_apostolic', 1)
)
insert into person_eras (person_id, era_id, display_order)
select
  p.id,
  e.id,
  s.display_order
from nt_person_eras s
join persons p on p.code = s.person_code
join eras e on e.code = s.era_code
on conflict (person_id, era_id) do update
set display_order = excluded.display_order
;

with nt_events (
  code,
  era_code,
  title,
  summary,
  short_text,
  story,
  short_story,
  start_year,
  end_year,
  time_precision,
  time_sort_key,
  place_name,
  lat,
  lng,
  is_major,
  search_text
) as (
  values
    ('evt_nt_jesus_baptism', 'era_nt_public_ministry', '세례 받으심', '예수께서 요단강에서 세례를 받으심', '공생애 시작에서 하늘의 증언이 선포된다.', '예수께서 갈릴리에서 요단강으로 오셔서 요한에게 세례를 받으셨다. 요한이 만류했지만 예수께서는 모든 의를 이루기 위해 허락하라고 말씀하셨다. 예수께서 물에서 올라오실 때 하늘이 열리고 성령이 비둘기 같이 임하셨다. 하늘의 음성이 이는 내 사랑하는 아들이요 내 기뻐하는 자라고 선포했다. 이 장면으로 공생애의 시작이 분명하게 드러났다.', '예수께서 요단강에서 세례를 받으셨다. 하늘이 열리고 성령이 임했다. 하늘의 음성이 예수를 사랑하는 아들이라고 선포했다. 공생애의 출발이 공식적으로 드러난 사건이다.', 27, 27, 'exact', 2701, '요단강', 31.84, 35.55, true, '예수 세례 요단강 마태복음 3장'),
    ('evt_nt_jesus_sermon_mount', 'era_nt_public_ministry', '산상수훈', '예수께서 하나님 나라의 삶을 가르치심', '복과 의와 기도의 길을 체계적으로 선포하신다.', '예수께서 산에 올라 제자들과 무리 앞에서 가르치기 시작하셨다. 심령이 가난한 자와 온유한 자가 복이 있다고 말씀하셨다. 또한 율법을 폐하려 온 것이 아니라 완성하려 왔다고 선포하셨다. 사랑과 용서와 기도와 금식의 태도를 구체적으로 가르치셨다. 이 말씀은 하나님 나라 백성의 삶을 정리한 기준이 되었다.', '예수께서 산 위에서 하나님 나라 백성의 삶을 가르치셨다. 복 있는 사람의 모습과 의의 길을 선포하셨다. 율법의 참뜻과 사랑의 실천을 분명히 하셨다. 제자 공동체의 기준이 되는 핵심 가르침이다.', 28, 28, 'exact', 2801, '갈릴리 언덕', 32.82, 35.57, true, '예수 산상수훈 마태복음 5장 6장 7장'),
    ('evt_nt_jesus_miracles_galilee', 'era_nt_public_ministry', '갈릴리 사역과 기적', '예수께서 갈릴리에서 병을 고치고 권세를 보이심', '말씀과 기적으로 하나님 나라의 도래를 보여주신다.', '예수께서 갈릴리 여러 마을을 다니며 복음을 전하셨다. 병든 자를 고치고 귀신 들린 사람을 자유롭게 하셨다. 폭풍 가운데서 바다를 잠잠하게 하셔서 제자들을 놀라게 하셨다. 중풍병자에게 죄 사함을 선포하시고 일어나 걷게 하셨다. 무리는 예수의 권위 있는 말씀과 행하심을 직접 보게 되었다.', '예수께서 갈릴리에서 복음을 전하며 많은 병자를 고치셨다. 폭풍을 잠잠하게 하시고 사람들을 두려움에서 건지셨다. 중풍병자를 일으켜 세우며 죄 사함의 권세를 보여주셨다. 갈릴리 사역은 말씀과 기적이 함께 나타난 시간이었다.', 29, 29, 'exact', 2901, '갈릴리', 32.84, 35.55, true, '예수 갈릴리 기적 마가복음 2장 4장'),
    ('evt_nt_jesus_transfiguration', 'era_nt_public_ministry', '변화산 사건', '예수의 영광이 제자들 앞에 드러남', '제자들이 예수의 정체성을 깊이 확인하게 된다.', '예수께서 베드로와 야고보와 요한을 데리고 높은 산에 오르셨다. 그곳에서 예수의 모습이 변화되고 옷이 빛처럼 희어졌다. 모세와 엘리야가 나타나 예수와 함께 말씀하는 장면이 보였다. 하늘의 음성이 이는 내 사랑하는 아들이니 그의 말을 들으라고 말했다. 제자들은 두려워했지만 예수께서 일으켜 세우시며 길을 계속 가게 하셨다.', '예수께서 제자들과 산에 오르셔서 영광의 모습을 보이셨다. 모세와 엘리야가 함께 나타나 예수의 사역을 증언했다. 하늘의 음성이 예수의 아들 되심을 다시 선포했다. 제자들은 두려움 속에서 예수의 정체성을 더 분명히 보게 되었다.', 30, 30, 'exact', 3001, '헤르몬산 인근', 33.41, 35.86, true, '예수 변화산 마태복음 17장'),
    ('evt_nt_jesus_last_supper_cross', 'era_nt_public_ministry', '최후의 만찬과 십자가', '예수께서 제자들과 유월절 식사 후 십자가에 달리심', '고난과 죽음을 통해 구원의 길이 열리는 장면이다.', '예수께서 제자들과 마지막 식사를 하시며 떡과 잔으로 새 언약을 말씀하셨다. 겟세마네에서 기도하신 후 체포되어 재판을 받으셨다. 예수는 조롱과 채찍질을 당하고 골고다에서 십자가에 못 박히셨다. 십자가 위에서 여러 말씀을 남기신 뒤 숨을 거두셨다. 제자들은 큰 혼란 속에서 이 사건을 지나게 되었다.', '예수께서 마지막 식사에서 새 언약을 제자들에게 전하셨다. 이어 체포와 재판을 거쳐 골고다 십자가에 달리셨다. 예수의 죽음으로 구속 사건의 중심이 세워졌다. 제자들은 이 고난의 시간을 통과하며 기다리게 되었다.', 33, 33, 'exact', 3301, '예루살렘', 31.78, 35.22, true, '예수 십자가 최후의 만찬 누가복음 22장 요한복음 19장'),
    ('evt_nt_jesus_resurrection_ascension', 'era_nt_public_ministry', '부활과 승천', '예수께서 부활하시고 제자들에게 나타난 뒤 승천하심', '부활 증언과 파송으로 사도 시대의 문이 열린다.', '안식 후 첫날 새벽에 무덤을 찾은 이들은 돌이 옮겨진 것을 보았다. 예수께서는 제자들에게 여러 번 나타나셔서 평강을 선포하시고 말씀을 풀어 주셨다. 제자들은 예수의 부활을 확인하고 증인의 사명을 받았다. 예수께서 감람원 근처에서 그들을 축복하시며 하늘로 올려지셨다. 제자들은 큰 기쁨으로 예루살렘에 돌아와 기도하며 기다렸다.', '빈 무덤과 부활하신 예수의 나타나심이 제자들에게 확인되었다. 예수는 제자들에게 증인의 사명을 맡기셨다. 감람원에서 승천하신 뒤 제자들은 예루살렘으로 돌아왔다. 이 사건이 사도 시대의 시작을 준비했다.', 33, 33, 'exact', 3302, '예루살렘', 31.78, 35.22, true, '예수 부활 승천 누가복음 24장 사도행전 1장'),

    ('evt_nt_paul_j1_commission_antioch', 'era_nt_apostolic', '1차: 안디옥 파송', '교회가 바울과 바나바를 선교로 파송함', '금식과 기도 가운데 첫 선교 여정이 시작된다.', '안디옥 교회가 금식하며 주를 섬길 때 성령께서 바울과 바나바를 따로 세우라고 말씀하셨다. 교회는 기도하고 두 사람에게 안수해 파송했다. 바울은 동역자들과 함께 선교 여정을 시작했다. 지역 교회가 선교의 출발점이 된 장면이다. 이후 전도 여행의 기본 패턴이 이곳에서 시작되었다.', '안디옥 교회가 금식과 기도 가운데 바울과 바나바를 파송했다. 성령의 인도 속에 1차 전도여행이 시작되었다. 교회는 안수로 선교 사역을 공적으로 맡겼다. 이 장면은 바울 선교의 출발점이다.', 46, 46, 'exact', 4601, '안디옥', 36.20, 36.16, true, '바울 1차 전도여행 안디옥 사도행전 13장'),
    ('evt_nt_paul_j1_pisidian_antioch', 'era_nt_apostolic', '1차: 비시디아 안디옥 설교', '바울이 회당에서 복음을 선포함', '복음이 유대인과 이방인에게 동시에 확장된다.', '바울은 비시디아 안디옥 회당에서 이스라엘 역사와 예수의 부활을 연결해 설교했다. 많은 이들이 말씀을 듣고 다음 안식일에도 모여들었다. 반대하는 사람들도 있었지만 바울은 담대하게 복음을 전했다. 이방인들이 기뻐하며 말씀을 받아들이는 일이 이어졌다. 복음 전파가 새로운 지역으로 본격적으로 넓어졌다.', '바울이 비시디아 안디옥 회당에서 예수의 복음을 선포했다. 반대와 환영이 동시에 일어났고 복음은 이방인에게도 전해졌다. 공동체는 큰 반응 속에서 새 국면을 맞았다. 1차 여행의 핵심 전환점이 되는 사건이다.', 46, 46, 'exact', 4602, '비시디아 안디옥', 38.31, 31.18, true, '바울 비시디아 안디옥 설교 사도행전 13장'),
    ('evt_nt_paul_j1_lystra_return', 'era_nt_apostolic', '1차: 루스드라와 귀환', '바울이 고난 속에서도 교회를 세우고 안디옥으로 돌아옴', '여러 도시를 지나며 제자를 세우고 보고한다.', '루스드라에서 바울은 앉은뱅이를 고치며 복음을 전했다. 그러나 곧 격렬한 반대가 일어나 돌에 맞는 고난도 겪었다. 바울은 다시 일어나 더베로 가서 많은 제자를 세웠다. 이어 방문했던 성읍들을 다시 돌며 교회를 격려하고 장로를 세웠다. 마지막으로 안디옥에 돌아와 하나님이 행하신 일을 보고했다.', '루스드라와 더베 사역에서 바울은 고난과 열매를 함께 경험했다. 그는 여러 도시를 다시 방문해 제자들을 굳게 세웠다. 장로를 세우고 교회 질서를 마련한 뒤 안디옥으로 돌아왔다. 1차 여행이 보고와 감사로 마무리되었다.', 47, 47, 'exact', 4603, '루스드라', 37.58, 32.49, true, '바울 루스드라 더베 귀환 사도행전 14장'),

    ('evt_nt_paul_j2_macedonian_call', 'era_nt_apostolic', '2차: 마게도냐 환상', '바울이 드로아에서 마게도냐로 가라는 인도를 받음', '사역의 방향이 아시아에서 유럽으로 확장된다.', '바울 일행은 여러 지역을 지나며 다음 사역지를 분별했다. 밤에 마게도냐 사람이 서서 건너와 도우라고 청하는 환상을 바울이 보게 되었다. 일행은 이를 하나님이 복음을 전하라고 부르신 것으로 확신했다. 그래서 즉시 배를 준비해 마게도냐로 향했다. 2차 여행의 큰 방향이 이 환상으로 결정되었다.', '드로아에서 바울은 마게도냐로 오라는 환상을 보았다. 일행은 하나님의 부르심으로 이해하고 즉시 이동했다. 복음 전파의 중심이 유럽 지역으로 확장되기 시작했다. 2차 여행의 출발점이 되는 장면이다.', 49, 49, 'exact', 5001, '드로아', 39.79, 26.24, true, '바울 2차 마게도냐 환상 사도행전 16장'),
    ('evt_nt_paul_j2_philippi', 'era_nt_apostolic', '2차: 빌립보 사역', '루디아의 회심과 옥중 찬송, 간수의 회심이 일어남', '복음이 가정과 도시로 퍼져 나가는 장면이다.', '빌립보에서 바울은 강가 기도처에서 루디아를 만나 복음을 전했다. 루디아와 그 집이 세례를 받고 일행을 맞아들였다. 이후 바울과 실라는 옥에 갇혔지만 한밤중에 찬송하며 기도했다. 큰 지진이 나고 옥문이 열렸고 간수는 두려워하다가 복음을 듣고 세례를 받았다. 빌립보 교회가 고난 속에서 시작되었다.', '빌립보에서 루디아 가정이 먼저 복음을 받아들였다. 바울과 실라는 투옥되었지만 찬송과 기도 속에서 간수 가정까지 복음이 전해졌다. 고난의 자리에서 공동체가 세워지는 모습이 나타났다. 2차 여행의 대표적인 사건이다.', 50, 50, 'exact', 5002, '빌립보', 41.01, 24.29, true, '바울 2차 빌립보 루디아 간수 사도행전 16장'),
    ('evt_nt_paul_j2_athens_corinth', 'era_nt_apostolic', '2차: 아테네와 고린도', '바울이 아레오바고에서 설교하고 고린도에서 오래 머뭄', '도시 문화 속에서 복음을 해석해 전한다.', '아테네에서 바울은 우상으로 가득한 도시를 보고 복음을 전하기 시작했다. 아레오바고에서 창조주 하나님과 부활의 소식을 선포했다. 이후 고린도로 이동해 아굴라와 브리스길라와 함께 지내며 일하고 전도했다. 안식일마다 회당에서 복음을 전했고 많은 이들이 믿었다. 바울은 고린도에 오래 머물며 공동체를 세웠다.', '바울은 아테네에서 철학자들에게 하나님과 부활을 선포했다. 이어 고린도에서 동역자들과 함께 장기간 사역했다. 말씀 전파와 공동체 형성이 동시에 진행되었다. 2차 여행의 후반을 대표하는 장면이다.', 51, 52, 'exact', 5003, '아테네·고린도', 37.98, 23.72, true, '바울 2차 아테네 고린도 아레오바고 사도행전 17장 18장'),

    ('evt_nt_paul_j3_ephesus', 'era_nt_apostolic', '3차: 에베소 사역', '바울이 에베소에서 장기간 머물며 복음을 전함', '두란노 서원 사역으로 말씀이 넓게 퍼진다.', '바울은 에베소에서 제자들을 만나 성령과 세례를 다시 가르쳤다. 회당에서 담대히 전하다가 두란노 서원에서 날마다 말씀을 전했다. 에베소와 주변 지역에 복음이 널리 퍼져 많은 사람이 말씀을 듣게 되었다. 우상 숭배와 마술을 버리고 돌아오는 변화가 일어났다. 3차 여행의 중심 사역지가 에베소로 자리잡았다.', '바울은 에베소에서 오랜 기간 말씀을 가르치고 제자들을 세웠다. 두란노 서원 사역을 통해 넓은 지역에 복음이 확산되었다. 우상 숭배를 끊고 삶이 바뀌는 회심이 이어졌다. 3차 여행의 핵심 거점이었다.', 54, 56, 'exact', 5401, '에베소', 37.94, 27.34, true, '바울 3차 에베소 두란노 서원 사도행전 19장'),
    ('evt_nt_paul_j3_miletus_farewell', 'era_nt_apostolic', '3차: 밀레도 고별', '바울이 에베소 장로들에게 마지막 권면을 전함', '눈물의 작별 속에서 목회적 당부를 남긴다.', '바울은 예루살렘으로 가는 길에 밀레도에서 에베소 장로들을 불렀다. 그는 자신이 어떻게 겸손과 눈물로 섬겼는지를 다시 전했다. 앞으로 닥칠 환난을 알지만 달려갈 길을 마치겠다고 고백했다. 장로들에게 교회를 맡기며 깨어 있으라고 간절히 권면했다. 모두가 함께 울며 기도하고 작별했다.', '밀레도에서 바울은 에베소 장로들에게 마지막 권면을 전했다. 그는 사명의 길을 끝까지 가겠다는 결심을 밝혔다. 장로들에게 교회를 지키라고 부탁하며 함께 기도했다. 3차 여행의 깊은 전환점이 되는 고별 장면이다.', 57, 57, 'exact', 5501, '밀레도', 37.53, 27.28, true, '바울 3차 밀레도 고별 사도행전 20장'),
    ('evt_nt_paul_j3_jerusalem_arrest', 'era_nt_apostolic', '3차: 예루살렘 체포', '바울이 성전에서 체포되어 군인들에게 호송됨', '선교 보고 이후 재판 국면으로 넘어간다.', '바울이 예루살렘에 도착했을 때 여러 소문과 긴장이 이미 퍼져 있었다. 성전에서 큰 소동이 일어나 바울은 군중에게 붙잡혔다. 천부장이 급히 개입해 바울을 군사적으로 보호하며 연행했다. 바울은 계단 위에서 백성에게 변론할 기회를 요청했다. 이 사건으로 바울 사역은 긴 재판과 호송의 단계로 들어갔다.', '예루살렘 성전에서 소동이 일어나 바울이 체포되었다. 군대의 개입으로 바울은 목숨을 건졌고 변론을 시작했다. 선교 여행 단계가 끝나고 긴 재판 과정으로 넘어가는 분기점이다. 3차 여행의 마지막 장면으로 기록된다.', 57, 57, 'exact', 5701, '예루살렘', 31.78, 35.22, true, '바울 3차 예루살렘 체포 사도행전 21장'),

    ('evt_nt_paul_rome_caesarea_trial', 'era_nt_apostolic', '로마 여정: 가이사랴 재판', '바울이 총독과 왕 앞에서 변론하고 가이사에게 상소함', '로마행이 법적 절차를 통해 확정된다.', '가이사랴에서 바울은 여러 차례 총독과 왕 앞에 서서 자신을 변론했다. 그는 예수의 부활 소망 때문에 심문받는다고 분명히 말했다. 재판은 길어졌고 유대 지도자들의 고발은 계속되었다. 바울은 결국 가이사에게 상소하여 로마로 가게 되었다. 복음 증언의 무대가 제국의 중심으로 이동하기 시작했다.', '가이사랴 재판에서 바울은 여러 통치자 앞에서 신앙을 변론했다. 그는 부활의 소망을 분명히 증언했고 결국 가이사에게 상소했다. 이 결정으로 로마 여정이 공식화되었다. 바울 사역은 새 단계로 들어갔다.', 59, 59, 'exact', 5901, '가이사랴', 32.50, 34.89, true, '바울 로마 여정 가이사랴 재판 사도행전 24장 25장'),
    ('evt_nt_paul_rome_storm_shipwreck', 'era_nt_apostolic', '로마 여정: 폭풍과 난파', '로마로 가는 배가 큰 폭풍을 만나 멜리데에 난파함', '긴 항해의 위기 속에서 모두가 생명을 보존한다.', '바울을 태운 배는 지중해에서 큰 폭풍을 만나 오랫동안 방향을 잃었다. 선원과 승객들은 식량을 줄이며 버티는 어려운 시간을 보냈다. 바울은 하나님이 모두의 생명을 지켜 주실 것이라고 격려했다. 결국 배는 멜리데 섬 근처에서 부서졌지만 사람들은 헤엄치거나 널빤지를 붙잡고 모두 살아 나왔다. 고난의 항해 속에서도 바울의 로마행은 멈추지 않았다.', '로마로 가던 배가 폭풍을 만나 난파 위기에 놓였다. 바울은 모두가 살아남을 것이라고 격려했고 결국 전원이 구조되었다. 멜리데 섬에 도착한 뒤 여정이 계속 이어졌다. 로마 여정의 가장 큰 위기 장면이다.', 60, 60, 'exact', 6001, '멜리데(몰타)', 35.89, 14.50, true, '바울 로마 여정 난파 멜리데 사도행전 27장'),
    ('evt_nt_paul_rome_arrival', 'era_nt_apostolic', '로마 여정: 로마 도착', '바울이 로마에 도착해 복음을 전함', '가택 연금 중에도 복음이 담대히 선포된다.', '바울은 마침내 로마에 도착해 군사의 보호 아래 머물게 되었다. 그는 유대 지도자들을 불러 자신의 입장을 설명하고 복음을 전했다. 어떤 사람은 믿고 어떤 사람은 믿지 않았지만 바울의 선포는 계속되었다. 그는 두 해 동안 자기 집에서 찾아오는 사람들을 맞아 하나님 나라를 전했다. 사도행전은 담대하고 거침없이 전했다는 말로 이 장면을 마무리한다.', '바울이 로마에 도착해 가택 연금 상태에서도 복음을 계속 전했다. 방문하는 사람들에게 하나님 나라와 예수를 가르쳤다. 반응은 갈렸지만 선포는 멈추지 않았다. 로마 여정의 도착점이자 사도행전의 마지막 장면이다.', 61, 61, 'exact', 6101, '로마', 41.90, 12.50, true, '바울 로마 도착 가택연금 사도행전 28장')
)
insert into events (
  code,
  era_id,
  title,
  summary,
  short_text,
  story,
  short_story,
  start_year,
  end_year,
  time_precision,
  time_sort_key,
  place_name,
  lat,
  lng,
  is_major,
  search_text
)
select
  n.code,
  e.id,
  n.title,
  n.summary,
  n.short_text,
  n.story,
  n.short_story,
  n.start_year,
  n.end_year,
  n.time_precision,
  n.time_sort_key,
  n.place_name,
  n.lat,
  n.lng,
  n.is_major,
  n.search_text
from nt_events n
join eras e on e.code = n.era_code
on conflict (code) do update
set
  era_id = excluded.era_id,
  title = excluded.title,
  summary = excluded.summary,
  short_text = excluded.short_text,
  story = excluded.story,
  short_story = excluded.short_story,
  start_year = excluded.start_year,
  end_year = excluded.end_year,
  time_precision = excluded.time_precision,
  time_sort_key = excluded.time_sort_key,
  place_name = excluded.place_name,
  lat = excluded.lat,
  lng = excluded.lng,
  is_major = excluded.is_major,
  search_text = excluded.search_text
;

with extra_events (
  code,
  era_code,
  title,
  summary,
  short_text,
  story,
  short_story,
  start_year,
  end_year,
  time_precision,
  time_sort_key,
  place_name,
  lat,
  lng,
  is_major,
  search_text
) as (
  values
    ('evt_pri_eve_creation', 'era_primeval', '하와의 창조', '하와가 아담의 돕는 배필로 세워짐', '하나님이 남자와 여자를 함께 세워 인간 공동체를 시작하신다.', '하나님은 사람이 홀로 있는 것이 좋지 않다고 하시고 아담에게서 여자를 지으셨다. 아담은 그녀를 보고 내 뼈 중의 뼈요 살 중의 살이라고 고백했다. 하와의 창조는 인간이 관계 속에서 부르심을 받았음을 보여준다.', '하와가 아담의 배필로 창조되며 인간 공동체가 시작되었다.', -4000, -4000, 'approx', -4000, '에덴(추정)', 33.30, 44.40, true, '하와 창조 아담 창세기 2장'),
    ('evt_ex_caleb_faithful_report', 'era_exodus', '갈렙의 신앙 보고', '갈렙이 가나안 정탐 후 믿음의 보고를 전함', '두려움보다 약속을 붙든 믿음이 다음 세대를 준비한다.', '정탐꾼들이 가나안 소식을 전할 때 다수는 두려움을 말했지만 갈렙과 여호수아는 하나님이 주신 땅을 취할 수 있다고 선포했다. 갈렙의 보고는 광야 공동체에 믿음의 기준을 세웠다.', '갈렙은 정탐 보고에서 약속을 신뢰하며 담대히 전했다.', -1446, -1446, 'approx', -1446, '가데스 바네아', 30.74, 34.39, true, '갈렙 정탐 보고 민수기 13장 14장'),
    ('evt_jdg_ruth_boaz_redeemer', 'era_judges', '룻과 보아스의 기업 무름', '룻과 보아스의 결단으로 나오미 가문이 회복됨', '충성과 책임의 선택이 다윗 계보의 문을 연다.', '룻은 시어머니 나오미를 떠나지 않고 베들레헴으로 돌아왔다. 보아스는 율법의 책임을 따라 룻을 보호하고 기업 무를 자의 역할을 감당했다. 이 사건을 통해 한 가정의 회복이 공동체의 미래로 연결되었다.', '룻과 보아스의 결단으로 나오미 가문이 회복되고 계보가 이어졌다.', -1120, -1120, 'approx', -1120, '베들레헴', 31.70, 35.20, true, '룻 보아스 나오미 기업무름 룻기 4장'),
    ('evt_exr_esther_intercession', 'era_exile_return', '에스더의 중보', '에스더가 왕 앞에 나아가 민족 보존을 위해 중보함', '죽으면 죽으리라의 결단이 공동체를 살린다.', '유다 민족을 향한 위기가 닥쳤을 때 에스더는 금식 후 왕 앞에 나아갔다. 에스더는 왕에게 간청해 하만의 계략을 드러냈고 민족은 큰 위기에서 보존되었다.', '에스더는 왕 앞에 담대히 나아가 민족을 위한 중보를 감당했다.', -479, -479, 'approx', -479, '수산 궁', 32.19, 48.24, true, '에스더 중보 수산 에스더 4장'),
    ('evt_mon_elijah_carmel_fire', 'era_monarchy', '갈멜산 대결', '엘리야가 갈멜산에서 여호와만이 하나님이심을 선포함', '무너진 제단이 회복되고 백성의 시선이 다시 하나님께 돌아온다.', '엘리야는 갈멜산에서 바알 선지자들과 맞서 여호와의 제단을 다시 쌓았다. 기도하자 하늘에서 불이 내려 제물을 사르며 하나님의 응답이 드러났다. 백성은 여호와 그는 하나님이시라고 고백했다.', '갈멜산에서 엘리야의 기도에 불이 내려 여호와의 주권이 선포되었다.', -860, -860, 'approx', -860, '갈멜산', 32.67, 35.03, true, '엘리야 갈멜산 불 열왕기상 18장'),
    ('evt_mon_elisha_naaman_healed', 'era_monarchy', '나아만 치유', '엘리사가 나아만 장군에게 순종의 길을 제시함', '하나님의 은혜는 겸손히 순종하는 자에게 임한다.', '나아만은 문둥병 치유를 구하며 엘리사를 찾았다. 엘리사는 요단강에 일곱 번 몸을 씻으라고 전했고 나아만이 순종하자 그의 살이 회복되었다. 이 사건은 이방인에게도 임하는 하나님의 은혜를 보여준다.', '나아만이 엘리사의 말씀에 순종해 요단강에서 치유를 받았다.', -850, -850, 'approx', -850, '사마리아', 32.08, 34.78, true, '엘리사 나아만 요단강 열왕기하 5장'),
    ('evt_mon_isaiah_temple_call', 'era_monarchy', '이사야의 소명', '이사야가 성전 환상 가운데 거룩하신 하나님께 부름받음', '거룩의 체험이 선지자 사명의 출발점이 된다.', '이사야는 성전 환상에서 높이 들린 보좌의 하나님과 거룩하다 외치는 스랍들을 보았다. 그는 자신의 부정함을 고백했으나 죄 사함을 받고 내가 여기 있나이다 나를 보내소서라고 응답했다.', '이사야는 성전 환상 가운데 죄 사함을 받고 선지자 소명을 받았다.', -740, -740, 'approx', -740, '예루살렘 성전', 31.78, 35.23, true, '이사야 소명 성전 이사야 6장'),
    ('evt_mon_jeremiah_temple_warning', 'era_monarchy', '예레미야의 성전 경고', '예레미야가 회개 없는 신앙을 경고함', '형식이 아닌 순종과 정의가 언약 백성의 길임을 선포한다.', '예레미야는 성전 문에 서서 거짓된 안전 의식을 버리고 삶을 돌이키라고 외쳤다. 그는 정의와 공의를 실천하지 않으면 심판이 임할 것을 경고했다. 이 메시지는 멸망 전 마지막 회개의 부르심이 되었다.', '예레미야는 성전에서 회개와 정의를 촉구하는 경고를 선포했다.', -609, -609, 'approx', -609, '예루살렘 성전', 31.78, 35.23, true, '예레미야 성전 설교 경고 예레미야 7장'),
    ('evt_exr_daniel_lions_den', 'era_exile_return', '다니엘의 사자굴 구원', '다니엘이 금지령 속에서도 기도를 지키다 사자굴에서 구원받음', '포로지에서도 흔들리지 않는 신앙이 하나님의 구원을 드러낸다.', '다니엘은 왕의 금지령에도 하나님께 기도하기를 멈추지 않았다. 그는 사자굴에 던져졌지만 하나님이 사자들의 입을 막으셔서 해를 입지 않았다. 왕은 다니엘의 하나님을 높이며 조서를 내렸다.', '다니엘은 사자굴에서도 보호받아 하나님의 살아 계심을 증언했다.', -539, -539, 'approx', -539, '바벨론', 32.54, 44.42, true, '다니엘 사자굴 기도 다니엘 6장'),
    ('evt_nt_mary_annunciation', 'era_nt_public_ministry', '마리아의 수태고지 순종', '마리아가 천사의 소식을 믿음으로 받아들임', '순종의 대답이 구속사의 시작을 여는 통로가 된다.', '천사는 마리아에게 성령으로 아들을 잉태하리라는 소식을 전했다. 마리아는 두려움 가운데서도 주의 여종이오니 말씀대로 이루어지이다라고 응답했다. 이 순종은 예수 탄생 서사의 출발점이 되었다.', '마리아는 수태고지 앞에서 믿음으로 순종하여 하나님의 뜻을 받아들였다.', 26, 26, 'exact', 2601, '나사렛', 32.70, 35.30, true, '마리아 수태고지 누가복음 1장'),
    ('evt_nt_call_first_disciples', 'era_nt_public_ministry', '첫 제자들의 부르심', '베드로 안드레 야고보 요한이 예수를 따르도록 부름받음', '일상에서의 부르심이 제자 공동체의 시작이 된다.', '예수께서 갈릴리 바닷가에서 어부들을 부르시며 나를 따라오라 내가 너희를 사람을 낚는 어부가 되게 하리라 하셨다. 그들은 배와 그물을 내려두고 예수를 따랐다.', '갈릴리 바닷가에서 첫 제자들이 예수의 부르심에 즉시 응답했다.', 27, 27, 'exact', 2702, '갈릴리 바다', 32.84, 35.58, true, '베드로 안드레 야고보 요한 부르심 마태복음 4장'),
    ('evt_nt_twelve_appointment', 'era_nt_public_ministry', '열두 제자 임명', '예수께서 열두 제자를 세워 함께 있게 하시고 파송 준비를 하심', '공동체의 증언 사명이 사람들을 세우는 방식으로 시작된다.', '예수께서는 기도 후 제자들 가운데 열둘을 따로 세우셨다. 그들을 가까이 두어 배우게 하시고 복음 전파와 치유 사역을 맡기셨다. 열두 제자 임명은 초대교회 증언 구조의 기반이 되었다.', '예수께서 열두 제자를 임명해 함께 있게 하시고 사명을 준비시키셨다.', 28, 28, 'exact', 2802, '갈릴리', 32.82, 35.57, true, '열두 제자 임명 마가복음 3장'),
    ('evt_nt_peter_confession', 'era_nt_public_ministry', '베드로의 신앙 고백', '베드로가 예수를 그리스도라 고백함', '제자 공동체가 예수의 정체성을 분명히 붙드는 전환점이다.', '가이사랴 빌립보에서 예수께서 제자들에게 누구라 하느냐 물으셨다. 베드로는 주는 그리스도시요 살아 계신 하나님의 아들이시니이다라고 고백했다. 예수께서는 이 고백 위에 공동체를 세우겠다고 말씀하셨다.', '베드로는 예수를 그리스도로 고백하며 제자 공동체의 전환점을 만들었다.', 29, 29, 'exact', 2902, '가이사랴 빌립보', 33.25, 35.69, true, '베드로 신앙고백 가이사랴 빌립보 마태복음 16장'),
    ('evt_nt_thomas_confession', 'era_nt_public_ministry', '도마의 부활 고백', '도마가 부활하신 예수를 만나 신앙 고백에 이름', '의심을 지나 만남으로 확신에 이르는 제자의 길을 보여준다.', '도마는 부활 소식을 쉽게 받아들이지 못했지만 예수께서 직접 나타나 상처를 보이셨다. 도마는 나의 주님이시요 나의 하나님이시니이다라고 고백했다. 이 장면은 부활 증언의 진정성을 강조한다.', '도마는 부활하신 예수를 만나 깊은 신앙 고백으로 나아갔다.', 33, 33, 'exact', 3303, '예루살렘', 31.78, 35.22, true, '도마 부활 고백 요한복음 20장'),
    ('evt_nt_judas_betrayal', 'era_nt_public_ministry', '가룟 유다의 배반', '가룟 유다가 예수를 넘겨주어 체포가 시작됨', '제자 공동체 안의 배신이 고난 서사를 본격화한다.', '가룟 유다는 은전의 대가로 예수를 넘겨주기로 합의했다. 겟세마네에서 그는 입맞춤으로 예수를 지목했고 예수는 체포되셨다. 이 사건은 십자가 고난으로 이어지는 직접적 계기가 되었다.', '가룟 유다의 배반으로 예수의 체포와 고난이 시작되었다.', 33, 33, 'exact', 3304, '예루살렘 겟세마네', 31.78, 35.24, true, '가룟 유다 배반 은전 마태복음 26장')
)
insert into events (
  code,
  era_id,
  title,
  summary,
  short_text,
  story,
  short_story,
  start_year,
  end_year,
  time_precision,
  time_sort_key,
  place_name,
  lat,
  lng,
  is_major,
  search_text
)
select
  n.code,
  e.id,
  n.title,
  n.summary,
  n.short_text,
  n.story,
  n.short_story,
  n.start_year,
  n.end_year,
  n.time_precision,
  n.time_sort_key,
  n.place_name,
  n.lat,
  n.lng,
  n.is_major,
  n.search_text
from extra_events n
join eras e on e.code = n.era_code
on conflict (code) do update
set
  era_id = excluded.era_id,
  title = excluded.title,
  summary = excluded.summary,
  short_text = excluded.short_text,
  story = excluded.story,
  short_story = excluded.short_story,
  start_year = excluded.start_year,
  end_year = excluded.end_year,
  time_precision = excluded.time_precision,
  time_sort_key = excluded.time_sort_key,
  place_name = excluded.place_name,
  lat = excluded.lat,
  lng = excluded.lng,
  is_major = excluded.is_major,
  search_text = excluded.search_text
;

with nt_event_persons (event_code, person_code) as (
  values
    ('evt_nt_jesus_baptism', 'jesus'),
    ('evt_nt_jesus_sermon_mount', 'jesus'),
    ('evt_nt_jesus_miracles_galilee', 'jesus'),
    ('evt_nt_jesus_transfiguration', 'jesus'),
    ('evt_nt_jesus_last_supper_cross', 'jesus'),
    ('evt_nt_jesus_resurrection_ascension', 'jesus'),
    ('evt_nt_paul_j1_commission_antioch', 'paul'),
    ('evt_nt_paul_j1_pisidian_antioch', 'paul'),
    ('evt_nt_paul_j1_lystra_return', 'paul'),
    ('evt_nt_paul_j2_macedonian_call', 'paul'),
    ('evt_nt_paul_j2_philippi', 'paul'),
    ('evt_nt_paul_j2_athens_corinth', 'paul'),
    ('evt_nt_paul_j3_ephesus', 'paul'),
    ('evt_nt_paul_j3_miletus_farewell', 'paul'),
    ('evt_nt_paul_j3_jerusalem_arrest', 'paul'),
    ('evt_nt_paul_rome_caesarea_trial', 'paul'),
    ('evt_nt_paul_rome_storm_shipwreck', 'paul'),
    ('evt_nt_paul_rome_arrival', 'paul')
)
insert into event_persons (event_id, person_id, person_sequence, role)
select
  e.id,
  p.id,
  1,
  'main'
from nt_event_persons s
join events e on e.code = s.event_code
join persons p on p.code = s.person_code
on conflict (event_id, person_id) do update
set
  person_sequence = excluded.person_sequence,
  role = excluded.role
;

with extra_event_persons (event_code, person_code, person_sequence, role) as (
  values
    ('evt_pri_eve_creation', 'eve', 1, '주인공'),
    ('evt_pri_adam_fall', 'eve', 2, '주요 인물'),
    ('evt_pri_adam_cain_abel', 'cain', 1, '주인공'),
    ('evt_pat_isaac_birth', 'sarah', 2, '주요 인물'),
    ('evt_pat_isaac_blessing', 'rebekah', 2, '주요 인물'),
    ('evt_pat_jacob_haran', 'leah', 3, '주요 인물'),
    ('evt_pat_jacob_haran', 'rachel', 4, '주요 인물'),
    ('evt_ex_red_sea_crossing', 'miriam', 4, '찬양 인도자'),
    ('evt_ex_caleb_faithful_report', 'caleb', 1, '주인공'),
    ('evt_jdg_deborah_victory', 'deborah', 1, '주인공'),
    ('evt_jdg_gideon_victory', 'gideon', 1, '주인공'),
    ('evt_jdg_samson_finale', 'samson', 1, '주인공'),
    ('evt_jdg_ruth_boaz_redeemer', 'ruth', 1, '주인공'),
    ('evt_jdg_ruth_boaz_redeemer', 'naomi', 2, '동행'),
    ('evt_jdg_ruth_boaz_redeemer', 'boaz', 3, '기업 무를 자'),
    ('evt_exr_esther_intercession', 'esther', 1, '주인공'),
    ('evt_mon_elijah_carmel_fire', 'elijah', 1, '주인공'),
    ('evt_mon_elisha_naaman_healed', 'elisha', 1, '주인공'),
    ('evt_mon_isaiah_temple_call', 'isaiah', 1, '주인공'),
    ('evt_mon_jeremiah_temple_warning', 'jeremiah', 1, '주인공'),
    ('evt_exr_daniel_lions_den', 'daniel', 1, '주인공'),
    ('evt_nt_mary_annunciation', 'mary', 1, '주인공'),
    ('evt_nt_call_first_disciples', 'peter', 1, '주요 제자'),
    ('evt_nt_call_first_disciples', 'andrew', 2, '주요 제자'),
    ('evt_nt_call_first_disciples', 'james_zebedee', 3, '주요 제자'),
    ('evt_nt_call_first_disciples', 'john', 4, '주요 제자'),
    ('evt_nt_twelve_appointment', 'peter', 1, '열두 제자'),
    ('evt_nt_twelve_appointment', 'andrew', 2, '열두 제자'),
    ('evt_nt_twelve_appointment', 'james_zebedee', 3, '열두 제자'),
    ('evt_nt_twelve_appointment', 'john', 4, '열두 제자'),
    ('evt_nt_twelve_appointment', 'philip', 5, '열두 제자'),
    ('evt_nt_twelve_appointment', 'bartholomew', 6, '열두 제자'),
    ('evt_nt_twelve_appointment', 'matthew', 7, '열두 제자'),
    ('evt_nt_twelve_appointment', 'thomas', 8, '열두 제자'),
    ('evt_nt_twelve_appointment', 'james_alphaeus', 9, '열두 제자'),
    ('evt_nt_twelve_appointment', 'thaddaeus', 10, '열두 제자'),
    ('evt_nt_twelve_appointment', 'simon_zealot', 11, '열두 제자'),
    ('evt_nt_twelve_appointment', 'judas_iscariot', 12, '열두 제자'),
    ('evt_nt_jesus_transfiguration', 'peter', 2, '동행 제자'),
    ('evt_nt_jesus_transfiguration', 'james_zebedee', 3, '동행 제자'),
    ('evt_nt_jesus_transfiguration', 'john', 4, '동행 제자'),
    ('evt_nt_peter_confession', 'peter', 1, '주인공'),
    ('evt_nt_thomas_confession', 'thomas', 1, '주인공'),
    ('evt_nt_judas_betrayal', 'judas_iscariot', 1, '주인공')
)
insert into event_persons (event_id, person_id, person_sequence, role)
select
  e.id,
  p.id,
  s.person_sequence,
  s.role
from extra_event_persons s
join events e on e.code = s.event_code
join persons p on p.code = s.person_code
on conflict (event_id, person_id) do update
set
  person_sequence = excluded.person_sequence,
  role = excluded.role
;

with nt_refs (
  event_code,
  book,
  chapter_start,
  verse_start,
  chapter_end,
  verse_end,
  display_text
) as (
  values
    ('evt_nt_jesus_baptism', '마태복음', 3, 13, 3, 17, '마태복음 3:13-17'),
    ('evt_nt_jesus_sermon_mount', '마태복음', 5, 1, 7, 29, '마태복음 5-7장'),
    ('evt_nt_jesus_miracles_galilee', '마가복음', 2, 1, 4, 41, '마가복음 2:1-12, 4:35-41'),
    ('evt_nt_jesus_transfiguration', '마태복음', 17, 1, 17, 8, '마태복음 17:1-8'),
    ('evt_nt_jesus_last_supper_cross', '요한복음', 19, 16, 19, 30, '요한복음 19:16-30'),
    ('evt_nt_jesus_resurrection_ascension', '누가복음', 24, 1, 24, 53, '누가복음 24장'),
    ('evt_nt_paul_j1_commission_antioch', '사도행전', 13, 1, 13, 3, '사도행전 13:1-3'),
    ('evt_nt_paul_j1_pisidian_antioch', '사도행전', 13, 14, 13, 52, '사도행전 13:14-52'),
    ('evt_nt_paul_j1_lystra_return', '사도행전', 14, 8, 14, 28, '사도행전 14:8-28'),
    ('evt_nt_paul_j2_macedonian_call', '사도행전', 16, 6, 16, 10, '사도행전 16:6-10'),
    ('evt_nt_paul_j2_philippi', '사도행전', 16, 11, 16, 40, '사도행전 16:11-40'),
    ('evt_nt_paul_j2_athens_corinth', '사도행전', 17, 16, 18, 11, '사도행전 17:16-18:11'),
    ('evt_nt_paul_j3_ephesus', '사도행전', 19, 1, 19, 20, '사도행전 19:1-20'),
    ('evt_nt_paul_j3_miletus_farewell', '사도행전', 20, 17, 20, 38, '사도행전 20:17-38'),
    ('evt_nt_paul_j3_jerusalem_arrest', '사도행전', 21, 27, 21, 36, '사도행전 21:27-36'),
    ('evt_nt_paul_rome_caesarea_trial', '사도행전', 24, 10, 25, 12, '사도행전 24:10-25:12'),
    ('evt_nt_paul_rome_storm_shipwreck', '사도행전', 27, 13, 27, 44, '사도행전 27:13-44'),
    ('evt_nt_paul_rome_arrival', '사도행전', 28, 16, 28, 31, '사도행전 28:16-31')
)
insert into event_bible_refs (
  event_id,
  book,
  chapter_start,
  verse_start,
  chapter_end,
  verse_end,
  display_text
)
select
  e.id,
  r.book,
  r.chapter_start,
  r.verse_start,
  r.chapter_end,
  r.verse_end,
  r.display_text
from nt_refs r
join events e on e.code = r.event_code
on conflict (event_id, display_text) do update
set
  book = excluded.book,
  chapter_start = excluded.chapter_start,
  verse_start = excluded.verse_start,
  chapter_end = excluded.chapter_end,
  verse_end = excluded.verse_end
;

with extra_refs (
  event_code,
  book,
  chapter_start,
  verse_start,
  chapter_end,
  verse_end,
  display_text
) as (
  values
    ('evt_pri_eve_creation', '창세기', 2, 18, 2, 23, '창 2:18-23'),
    ('evt_ex_caleb_faithful_report', '민수기', 14, 6, 14, 9, '민 14:6-9'),
    ('evt_jdg_ruth_boaz_redeemer', '룻기', 4, 9, 4, 10, '룻 4:9-10'),
    ('evt_exr_esther_intercession', '에스더', 4, 13, 4, 16, '에 4:13-16'),
    ('evt_mon_elijah_carmel_fire', '열왕기상', 18, 36, 18, 39, '왕상 18:36-39'),
    ('evt_mon_elisha_naaman_healed', '열왕기하', 5, 10, 5, 14, '왕하 5:10-14'),
    ('evt_mon_isaiah_temple_call', '이사야', 6, 1, 6, 8, '사 6:1-8'),
    ('evt_mon_jeremiah_temple_warning', '예레미야', 7, 3, 7, 7, '렘 7:3-7'),
    ('evt_exr_daniel_lions_den', '다니엘', 6, 19, 6, 23, '단 6:19-23'),
    ('evt_nt_mary_annunciation', '누가복음', 1, 26, 1, 38, '눅 1:26-38'),
    ('evt_nt_call_first_disciples', '마태복음', 4, 18, 4, 22, '마 4:18-22'),
    ('evt_nt_twelve_appointment', '마가복음', 3, 13, 3, 19, '막 3:13-19'),
    ('evt_nt_peter_confession', '마태복음', 16, 15, 16, 17, '마 16:15-17'),
    ('evt_nt_thomas_confession', '요한복음', 20, 27, 20, 29, '요 20:27-29'),
    ('evt_nt_judas_betrayal', '마태복음', 26, 47, 26, 50, '마 26:47-50')
)
insert into event_bible_refs (
  event_id,
  book,
  chapter_start,
  verse_start,
  chapter_end,
  verse_end,
  display_text
)
select
  e.id,
  r.book,
  r.chapter_start,
  r.verse_start,
  r.chapter_end,
  r.verse_end,
  r.display_text
from extra_refs r
join events e on e.code = r.event_code
on conflict (event_id, display_text) do update
set
  book = excluded.book,
  chapter_start = excluded.chapter_start,
  verse_start = excluded.verse_start,
  chapter_end = excluded.chapter_end,
  verse_end = excluded.verse_end
;
