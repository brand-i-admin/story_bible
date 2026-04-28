// Supabase Edge Function: send-push
//
// DB 트리거 (pg_net 으로) 혹은 서버 사이드 코드가 호출해서 FCM HTTP v1 API 로
// 푸시 알림을 전송하는 함수.
//
// 호출 경로:
//   1) DB 에서 pg_net.http_post(
//        url := '<project>.functions.supabase.co/send-push',
//        headers := '{"Authorization":"Bearer <service_role_key>"}'::jsonb,
//        body := '{"user_id": "...", "title": "...", "body": "..."}'::jsonb)
//   2) 혹은 Flutter/관리 도구에서 supabase.functions.invoke('send-push', { ... })
//
// 입력 스키마 (두 변형):
//   개인 알림: { user_id: uuid, title, body?, deep_link?, type? }
//   브로드캐스트: { broadcast: true, title, body?, deep_link?, type?, target? }
//     target ('all' | 'pastor_or_admin') — 지정 시 유저 필터링.
//
// 전송 방식:
//   - 해당 유저의 user_push_tokens 에 저장된 모든 디바이스 토큰에 대해
//     FCM HTTP v1 API POST /v1/projects/{project}/messages:send.
//   - 404 UNREGISTERED 응답이 오면 해당 토큰 삭제 (정리).
//
// Secrets (supabase secrets set):
//   FIREBASE_SERVICE_ACCOUNT  — Firebase 서비스 계정 JSON 전문
//     (project 설정 → 서비스 계정 → "새 비공개 키 생성" 으로 받은 파일)
//   SUPABASE_URL              — 자동 주입됨
//   SUPABASE_SERVICE_ROLE_KEY — 자동 주입됨

import { createClient } from "npm:@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
import { getGcpAccessToken } from "../_shared/gcp_auth.ts";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

interface PersonalPayload {
  user_id: string;
  title: string;
  body?: string;
  deep_link?: string;
  type?: string;
}

interface BroadcastPayload {
  broadcast: true;
  title: string;
  body?: string;
  deep_link?: string;
  type?: string;
  target?: "all" | "pastor_or_admin";
}

type InputPayload = PersonalPayload | BroadcastPayload;

function isBroadcast(p: InputPayload): p is BroadcastPayload {
  return (p as BroadcastPayload).broadcast === true;
}

function corsJson(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errJson(msg: string, status = 500): Response {
  console.error(`[send-push] ${msg}`);
  return corsJson({ error: msg }, status);
}

/**
 * FCM HTTP v1 로 단일 메시지 전송.
 * 성공 시 name(메시지 ID) 반환, 실패 시 Error throw.
 * 404 UNREGISTERED 는 특별 처리용으로 "UNREGISTERED" 문자열을 throw.
 */
async function sendFcmMessage(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string | undefined,
  data: Record<string, string>,
): Promise<void> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const payload = {
    message: {
      token,
      notification: { title, body: body ?? "" },
      data,
      // Android/iOS 자동 탭 시 action 전달 (앱 내 라우팅용).
      android: {
        priority: "HIGH",
        notification: { channel_id: "default_channel" },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
      webpush: {
        fcm_options: data.deep_link ? { link: data.deep_link } : undefined,
      },
    },
  };
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (response.ok) return;
  const text = await response.text();
  // FCM 이 토큰 무효라고 알려주면 UNREGISTERED 로 마킹 — 호출자가 토큰 삭제.
  if (
    response.status === 404 ||
    text.includes("UNREGISTERED") ||
    text.includes("INVALID_ARGUMENT")
  ) {
    throw new Error("UNREGISTERED");
  }
  throw new Error(`FCM ${response.status}: ${text}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return errJson("only POST is supported", 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const rawSaJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!supabaseUrl || !serviceRoleKey) {
    return errJson("missing Supabase env", 500);
  }
  if (!rawSaJson) {
    return errJson("missing FIREBASE_SERVICE_ACCOUNT secret", 500);
  }

  let sa: ServiceAccount;
  try {
    sa = JSON.parse(rawSaJson);
  } catch {
    return errJson("FIREBASE_SERVICE_ACCOUNT is not valid JSON", 500);
  }
  if (!sa.project_id || !sa.client_email || !sa.private_key) {
    return errJson("service account missing required fields", 500);
  }

  let payload: InputPayload;
  try {
    payload = await req.json();
  } catch {
    return errJson("invalid JSON body", 400);
  }
  if (!payload.title) {
    return errJson("title is required", 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // 대상 user_id 목록 결정.
  let userIds: string[];
  if (isBroadcast(payload)) {
    // pastor_or_admin 타겟은 향후 확장용 — 현재 MVP 는 'all' 만 처리.
    // user_push_tokens 의 모든 user_id 를 읽는다 (로그인한 적 있는 유저만).
    const { data, error } = await admin
      .from("user_push_tokens")
      .select("user_id");
    if (error) return errJson(`fetch user ids failed: ${error.message}`, 500);
    userIds = Array.from(new Set(data?.map((r) => r.user_id as string) ?? []));
  } else {
    if (!payload.user_id) return errJson("user_id is required", 400);
    userIds = [payload.user_id];
  }

  if (userIds.length === 0) {
    return corsJson({ sent: 0, failed: 0, note: "no recipients" });
  }

  // 토큰 조회.
  const { data: tokenRows, error: tokenErr } = await admin
    .from("user_push_tokens")
    .select("token,user_id,platform")
    .in("user_id", userIds);
  if (tokenErr) return errJson(`fetch tokens failed: ${tokenErr.message}`, 500);
  if (!tokenRows || tokenRows.length === 0) {
    return corsJson({ sent: 0, failed: 0, note: "no tokens" });
  }

  // GCP 액세스 토큰 발급 (FCM scope).
  let accessToken: string;
  try {
    accessToken = await getGcpAccessToken(sa, FCM_SCOPE);
  } catch (e) {
    return errJson(`token exchange failed: ${e}`, 500);
  }

  const data: Record<string, string> = {
    type: payload.type ?? "",
    deep_link: payload.deep_link ?? "",
  };

  let sent = 0;
  let failed = 0;
  const unregisteredTokens: string[] = [];

  // 순차 전송 — 토큰 수가 많지 않다고 가정. 많아지면 Promise.all 로 교체.
  for (const row of tokenRows) {
    try {
      await sendFcmMessage(
        accessToken,
        sa.project_id,
        row.token as string,
        payload.title,
        payload.body,
        data,
      );
      sent += 1;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg === "UNREGISTERED") {
        unregisteredTokens.push(row.token as string);
      }
      failed += 1;
    }
  }

  // 무효 토큰 정리.
  if (unregisteredTokens.length > 0) {
    await admin
      .from("user_push_tokens")
      .delete()
      .in("token", unregisteredTokens);
  }

  return corsJson({
    sent,
    failed,
    cleaned_tokens: unregisteredTokens.length,
  });
});
