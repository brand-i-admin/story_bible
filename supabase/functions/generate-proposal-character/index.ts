// Supabase Edge Function: generate-proposal-character
//
// Proposal submit form calls this to generate a NEW character avatar that
// doesn't yet exist in the `characters` table. Same Vertex Imagen 4.0 model
// used by `tools/images/generate_avatars_vertex.py` so results blend visually
// with the pre-generated canonical cast.
//
// Request:
//   { prompt: string,          // user-written description (한글 OK)
//     characterCode: string,   // snake_case id, e.g. "caleb_disciple"
//     characterName: string,   // display name (한글), e.g. "갈렙의 제자"
//     draftId: string }        // client-generated uuid; groups all proposal assets
//
// Response: { storage_path: "proposal-characters/<uid>/<draft>/<code>.png",
//             prompt: "<final prompt sent to Imagen>" }
//
// Errors: 400 input, 401 auth, 500 config, 502 Vertex.

import { createClient } from "npm:@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
import { getGcpAccessToken } from "../_shared/gcp_auth.ts";
import {
  CHARACTER_NEGATIVE_PROMPT,
  IMAGEN_MODEL_CANDIDATES,
  composeCharacterPrompt,
} from "../_shared/character_style.ts";
import { translateForImagePrompt } from "../_shared/translate.ts";

const BUCKET = "proposal-characters";

interface RequestBody {
  prompt: string;
  characterCode: string;
  characterName: string;
  draftId: string;
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function err(message: string, status = 500): Response {
  console.error(`[generate-proposal-character] ${message}`);
  return json({ error: message }, status);
}

function extractPngBase64(node: unknown): string | null {
  if (node == null) return null;
  if (Array.isArray(node)) {
    for (const v of node) {
      const r = extractPngBase64(v);
      if (r) return r;
    }
    return null;
  }
  if (typeof node === "object") {
    const obj = node as Record<string, unknown>;
    for (const k of ["bytesBase64Encoded", "b64Json"]) {
      const v = obj[k];
      if (typeof v === "string" && v.length > 16) return v;
    }
    const inline = obj["inlineData"];
    if (
      inline &&
      typeof inline === "object" &&
      typeof (inline as Record<string, unknown>)["data"] === "string"
    ) {
      return (inline as Record<string, string>)["data"];
    }
    for (const v of Object.values(obj)) {
      const r = extractPngBase64(v);
      if (r) return r;
    }
  }
  return null;
}

async function callImagen(
  accessToken: string,
  project: string,
  location: string,
  prompt: string,
): Promise<Uint8Array> {
  // Imagen 은 regional endpoint (no `global`); fallback to us-central1.
  const loc = location === "global" ? "us-central1" : location;
  const host = `${loc}-aiplatform.googleapis.com`;

  const body = {
    instances: [{ prompt }],
    parameters: {
      sampleCount: 1,
      aspectRatio: "1:1",
      enhancePrompt: true,
      personGeneration: "allow_adult",
      negativePrompt: CHARACTER_NEGATIVE_PROMPT,
      outputOptions: { mimeType: "image/png" },
    },
  };

  // Try models in order. 403/404 on one model → try the next (대개 4.0 은
  // preview allowlist, 3.0 은 GA). 다른 오류는 즉시 raise.
  const errors: string[] = [];
  for (const model of IMAGEN_MODEL_CANDIDATES) {
    const url =
      `https://${host}/v1/projects/${project}/locations/${loc}/` +
      `publishers/google/models/${model}:predict`;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (res.ok) {
      const payload = await res.json();
      const b64 = extractPngBase64(payload);
      if (!b64) throw new Error(`Imagen ${model} returned no image bytes`);
      const bin = atob(b64);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      return bytes;
    }
    const text = await res.text();
    errors.push(`${model} → ${res.status}: ${text.slice(0, 200)}`);
    // 403/404 는 allowlist/모델 미존재 가능성 → 다음 후보로 fallback.
    // 401/500 류는 더 심각한 config 문제이므로 계속 try 해도 대부분 동일하지만,
    // 그래도 모든 후보를 시도해 보고 마지막에 모아서 raise.
  }
  throw new Error(
    `All Imagen models failed:\n  ${errors.join("\n  ")}`,
  );
}

// Enforce the same naming convention as local avatars (lowercase snake_case).
function sanitizeCode(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 48);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") return err("method not allowed", 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const project = Deno.env.get("GOOGLE_CLOUD_PROJECT");
  const location = Deno.env.get("GOOGLE_CLOUD_LOCATION") ?? "us-central1";
  const saJson = Deno.env.get("GCP_SERVICE_ACCOUNT_JSON");
  if (!project) return err("GOOGLE_CLOUD_PROJECT secret not set", 500);
  if (!saJson) return err("GCP_SERVICE_ACCOUNT_JSON secret not set", 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  const client = createClient(supabaseUrl, serviceKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await client.auth.getUser();
  if (userErr || !user) return err("unauthorized", 401);

  let input: RequestBody;
  try {
    input = (await req.json()) as RequestBody;
  } catch (_) {
    return err("invalid JSON body", 400);
  }
  const { prompt, characterName = "", draftId } = input;
  const code = sanitizeCode(input.characterCode ?? "");
  if (
    typeof prompt !== "string" ||
    prompt.trim() === "" ||
    typeof draftId !== "string" ||
    draftId.trim() === "" ||
    code === ""
  ) {
    return err(
      "missing/invalid prompt | characterCode | draftId (code must be a-z0-9_)",
      400,
    );
  }

  // Reject attempts to overwrite a canonical character code that already
  // exists and is active — the proposal flow is only for NEW characters.
  // (This protects against accidentally replacing `jesus.png` etc.)
  const { data: existing } = await client
    .from("characters")
    .select("code, is_active")
    .eq("code", code)
    .maybeSingle();
  if (existing != null && existing["is_active"] === true) {
    return err(
      `character code "${code}" already exists as an active canonical ` +
        "character. Please pick a different code.",
      409,
    );
  }

  // 1) GCP token 발급 (Imagen + Gemini 둘 다 같은 토큰 사용)
  let accessToken: string;
  try {
    const sa = JSON.parse(saJson);
    accessToken = await getGcpAccessToken(sa);
  } catch (e) {
    return err(
      `gcp token failed: ${e instanceof Error ? e.message : String(e)}`,
      500,
    );
  }

  // 2) 사용자 한국어 prompt → 영어로 번역 (한국어 미포함 시 그대로).
  //    Imagen 4/3 가 한국어 명사(지팡이/책/안경 등)를 자주 무시하는 문제를
  //    해결하기 위해 영어 prompt 로 변환해 정확한 시각 요소 반영.
  const englishDescription = await translateForImagePrompt(
    prompt,
    accessToken,
    project,
    location,
  );

  // 3) common style + description (영어) 합쳐 최종 Imagen prompt 구성.
  const fullPrompt = composeCharacterPrompt(englishDescription);

  // 4) Imagen 호출.
  let imageBytes: Uint8Array;
  try {
    imageBytes = await callImagen(accessToken, project, location, fullPrompt);
  } catch (e) {
    return err(
      `Imagen call failed: ${e instanceof Error ? e.message : String(e)}`,
      502,
    );
  }

  // Upload to proposal-characters/<uid>/<draft>/<code>.png (upsert allows regen).
  const storagePath = `${user.id}/${draftId}/${code}.png`;
  const { error: uploadErr } = await client.storage
    .from(BUCKET)
    .upload(storagePath, imageBytes, {
      contentType: "image/png",
      upsert: true,
      cacheControl: "3600",
    });
  if (uploadErr) return err(`storage upload failed: ${uploadErr.message}`);

  return json({
    storage_path: `${BUCKET}/${storagePath}`,
    prompt: fullPrompt,
    character_code: code,
    character_name: characterName,
  });
});
