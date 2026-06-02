// Supabase Edge Function: generate-proposal-scene
//
// Web client (proposal submit form) calls this to generate ONE scene image
// for a draft proposal. Input: scene text + character codes + draft id +
// scene index. Output: the Supabase Storage path where the generated image
// was uploaded (inside `proposal-scenes` bucket).
//
// Why an Edge Function:
//   - The Vertex AI call requires a GCP service account key. We cannot expose
//     that to the browser, so we run generation here and only hand back a
//     Storage path.
//   - One image at a time (user blocked in UI). No batching on this path.
//
// Deployment (see docs/BACKEND.md §Edge Functions):
//   supabase secrets set GOOGLE_CLOUD_PROJECT=your-gcp-project
//   supabase secrets set --env-file .env.supabase.secrets  # GCP_SERVICE_ACCOUNT_JSON
//   supabase functions deploy generate-proposal-scene
//
// Invocation from Flutter (see lib/data/proposal_repository.dart):
//   final result = await supabase.functions.invoke(
//     'generate-proposal-scene',
//     body: { sceneText, characterCodes, draftId, sceneIndex, ... },
//   );
//
// Response shape:
//   {
//     "storage_path": "proposal-scenes/<uid>/<draft>/scene_<idx>.png",
//     "prompt": "<exact text used>"
//   }
//
// Errors: 400 on bad input, 401 on missing JWT, 500 on Vertex/Storage failure.

import { createClient } from "npm:@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
import { getGcpAccessToken } from "../_shared/gcp_auth.ts";
import { translateForImagePrompt } from "../_shared/translate.ts";

// Same visual preamble used by tools/images/generate_event_story_images_vertex.py
// so user-generated proposal scenes blend with production scene art.
const COMMON_SCENE_STYLE =
  "Create one non-photoreal 2D Bible story illustration in the same visual " +
  "world as the avatar cast. Use stylized geometric biblical illustration, " +
  "blocky low-poly faceted planes, angular but friendly forms, flat matte " +
  "vector shading with subtle cut-paper facets, warm parchment-friendly " +
  "colors, clean composition, and consistent character design across every " +
  "scene. No speech bubbles, no captions, no written letters, no symbols, " +
  "no watermark, no modern objects.";

// Model fallback order: prefer the Gemini 3 Pro Image model, fall back to flash.
const MODEL_CANDIDATES = ["gemini-3-pro-image", "gemini-2.5-flash-image"];

const AVATAR_BUCKET = "characters";
const SCENE_BUCKET = "proposal-scenes";

interface RequestBody {
  sceneText: string;
  characterCodes: string[];
  draftId: string;
  sceneIndex: number;
  eventTitle?: string;
  placeName?: string;
}

function corsOrJson(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errJson(message: string, status = 500): Response {
  console.error(`[generate-proposal-scene] ${message}`);
  return corsOrJson({ error: message }, status);
}

async function fetchAvatarAsBase64(
  supabaseUrl: string,
  code: string,
): Promise<string | null> {
  // Avatars are in a public bucket, so a signed fetch is unnecessary.
  const publicUrl =
    `${supabaseUrl.replace(/\/$/, "")}/storage/v1/object/public/` +
    `${AVATAR_BUCKET}/${encodeURIComponent(code)}.png`;
  const res = await fetch(publicUrl);
  if (!res.ok) {
    console.warn(`[avatars] miss ${code} (${res.status})`);
    return null;
  }
  const buf = new Uint8Array(await res.arrayBuffer());
  let binary = "";
  for (let i = 0; i < buf.length; i++) binary += String.fromCharCode(buf[i]);
  return btoa(binary);
}

function buildVertexParts(input: {
  eventTitle: string;
  sceneText: string;
  placeName?: string;
  references: {
    code: string;
    name: string;
    description: string;
    base64: string;
  }[];
}): Array<Record<string, unknown>> {
  const refLabels = input.references.map((r) => `${r.name} (${r.code})`);
  const charText = refLabels.length ? refLabels.join(", ") : "none";
  const namesOnly = input.references.map((r) => r.name);
  const placeClause = input.placeName ? ` Place: ${input.placeName}.` : "";

  // Reference characters are this scene's *exact and only* cast.
  // The attached avatar images define their canonical look — face, hair,
  // costume, age. The scene must depict precisely these characters and no
  // other named persons.
  const exactCastClause = namesOnly.length
    ? ` This scene MUST depict exactly these characters and only these: ${namesOnly.join(
        ", ",
      )}. Do not add other named figures. Each attached avatar image is the canonical look of that character.`
    : "";

  const instruction =
    `${COMMON_SCENE_STYLE} ` +
    `Event title: ${input.eventTitle}. ` +
    `Scene description: ${input.sceneText}.${placeClause} ` +
    "Keep the composition suitable for mobile storytelling. " +
    "Show only visible action, facial expression, body pose, props, weather, light, and environment. " +
    "Do not add spoken words, dialogue balloons, captions, written letters, scripture text, or logos. " +
    "CRITICAL CHARACTER CONSISTENCY: each attached avatar image is the EXACT canonical appearance of that character. " +
    "You MUST faithfully copy the face geometry, hair color and style, skin tone, body proportions, clothing colors, and any held props or accessories from each attached avatar. " +
    "The same person must look like the SAME person across every scene — do NOT redesign, age them, swap their clothing, or invent a new face. " +
    "If the scene description explicitly requests a different physical state (e.g., older, wounded, kneeling), keep the same identity (face/hair) but apply only the requested change. " +
    "Do not introduce extra characters that are not on the attached cast list. " +
    `Scene reference characters: ${charText}.${exactCastClause}`;

  const parts: Array<Record<string, unknown>> = [{ text: instruction }];
  for (const ref of input.references) {
    const descClause = ref.description.trim().length > 0
      ? ` Visual identity reference (must match): ${ref.description.trim()}.`
      : "";
    parts.push({
      text:
        `Attached canonical character reference: ${ref.name} (${ref.code}). ` +
        "Use the attached avatar image as the SINGLE SOURCE OF TRUTH for face, " +
        "hair, costume, age, body type, and skin tone of this character. " +
        "Every appearance of this character in the scene must look like the avatar." +
        descClause,
    });
    parts.push({
      inlineData: { mimeType: "image/png", data: ref.base64 },
    });
  }
  return parts;
}

async function callVertex(
  accessToken: string,
  project: string,
  location: string,
  parts: Array<Record<string, unknown>>,
): Promise<Uint8Array> {
  const body = {
    contents: [{ role: "user", parts }],
    generationConfig: {
      responseModalities: ["IMAGE"],
      candidateCount: 1,
    },
  };

  let lastErr: unknown = null;
  for (const model of MODEL_CANDIDATES) {
    // Some Gemini 3 image models require `global` region.
    const loc = model.startsWith("gemini-3-") ? "global" : location;
    const host =
      loc === "global"
        ? "aiplatform.googleapis.com"
        : `${loc}-aiplatform.googleapis.com`;
    const url =
      `https://${host}/v1/projects/${project}/locations/${loc}/` +
      `publishers/google/models/${model}:generateContent`;

    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const text = await res.text();
      lastErr = new Error(`Vertex ${model} → ${res.status}: ${text}`);
      continue;
    }
    const json = await res.json();
    const b64 = extractImageBase64(json);
    if (b64) {
      const bin = atob(b64);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      return bytes;
    }
    lastErr = new Error(`Vertex ${model} returned no image bytes`);
  }
  throw lastErr ?? new Error("No Vertex model produced an image");
}

function extractImageBase64(node: unknown): string | null {
  // Depth-first search for bytesBase64Encoded / inlineData.data in the
  // Gemini `generateContent` response. Safe against schema drift.
  if (node == null) return null;
  if (typeof node === "string") return null;
  if (Array.isArray(node)) {
    for (const v of node) {
      const r = extractImageBase64(v);
      if (r) return r;
    }
    return null;
  }
  if (typeof node === "object") {
    const obj = node as Record<string, unknown>;
    // Preferred keys first.
    for (const k of ["bytesBase64Encoded", "b64Json"]) {
      const v = obj[k];
      if (typeof v === "string" && v.length > 0) return v;
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
      const r = extractImageBase64(v);
      if (r) return r;
    }
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return errJson("method not allowed", 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const gcpProject = Deno.env.get("GOOGLE_CLOUD_PROJECT");
  const gcpLocation = Deno.env.get("GOOGLE_CLOUD_LOCATION") ?? "global";
  const saJsonStr = Deno.env.get("GCP_SERVICE_ACCOUNT_JSON");

  if (!gcpProject) return errJson("GOOGLE_CLOUD_PROJECT secret not set", 500);
  if (!saJsonStr) return errJson("GCP_SERVICE_ACCOUNT_JSON secret not set", 500);

  // verify_jwt=true in config.toml ensures a valid user token, but we still
  // need the user id for the storage folder path.
  const authHeader = req.headers.get("Authorization") ?? "";
  const client = createClient(supabaseUrl, serviceKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await client.auth.getUser();
  if (userErr || !user) return errJson("unauthorized", 401);

  let input: RequestBody;
  try {
    input = (await req.json()) as RequestBody;
  } catch (_) {
    return errJson("invalid JSON body", 400);
  }
  const {
    sceneText,
    characterCodes = [],
    draftId,
    sceneIndex,
    eventTitle = "",
    placeName,
  } = input;
  if (
    typeof sceneText !== "string" ||
    sceneText.trim() === "" ||
    typeof draftId !== "string" ||
    draftId.trim() === "" ||
    typeof sceneIndex !== "number" ||
    sceneIndex < 0 ||
    sceneIndex > 9
  ) {
    return errJson("missing/invalid sceneText | draftId | sceneIndex", 400);
  }

  // Look up character display names + descriptions — name 은 prompt 텍스트에,
  // description 은 reference 옆에 붙여 모델이 외형 단서까지 알게 한다.
  const codeToName: Record<string, string> = {};
  const codeToDesc: Record<string, string> = {};
  if (characterCodes.length > 0) {
    const { data: rows, error: nameErr } = await client
      .from("characters")
      .select("code, name, description")
      .in("code", characterCodes);
    if (nameErr) console.warn("[characters] lookup failed", nameErr.message);
    for (const row of rows ?? []) {
      const code = row.code as string;
      codeToName[code] = row.name as string;
      codeToDesc[code] = (row.description as string | null) ?? "";
    }
  }

  // GCP 토큰 1회 발급 (번역 + Vertex 둘 다 사용).
  let accessToken: string;
  try {
    const sa = JSON.parse(saJsonStr);
    accessToken = await getGcpAccessToken(sa);
  } catch (e) {
    return errJson(
      `gcp token failed: ${e instanceof Error ? e.message : String(e)}`,
      500,
    );
  }

  // 한국어 sceneText → 영어 번역 (한국어 미포함 시 그대로). Imagen/Gemini Image
  // 가 한국어 명사(지팡이/책/안경/특정 행동 등)를 자주 무시하는 문제 해결.
  const englishSceneText = await translateForImagePrompt(
    sceneText,
    accessToken,
    gcpProject,
    gcpLocation,
  );
  // 캐릭터 description 도 한국어면 번역 — 모델이 영문 visual identity 단서를 받음.
  const codeToDescEn: Record<string, string> = {};
  await Promise.all(
    Object.entries(codeToDesc).map(async ([code, desc]) => {
      if (!desc.trim()) {
        codeToDescEn[code] = "";
        return;
      }
      codeToDescEn[code] = await translateForImagePrompt(
        desc,
        accessToken,
        gcpProject,
        gcpLocation,
      );
    }),
  );

  // Pull avatar PNGs (public bucket, fetch parallel).
  const references = await Promise.all(
    characterCodes.map(async (code) => {
      const base64 = await fetchAvatarAsBase64(supabaseUrl, code);
      if (!base64) return null;
      return {
        code,
        name: codeToName[code] ?? code,
        description: codeToDescEn[code] ?? "",
        base64,
      };
    }),
  ).then((list) => list.filter((x): x is NonNullable<typeof x> => x !== null));

  const parts = buildVertexParts({
    eventTitle: eventTitle || "Untitled Bible scene",
    sceneText: englishSceneText,
    placeName,
    references,
  });

  // Vertex 호출 (위에서 이미 토큰 발급 완료).
  let imageBytes: Uint8Array;
  try {
    imageBytes = await callVertex(accessToken, gcpProject, gcpLocation, parts);
  } catch (e) {
    return errJson(
      `vertex call failed: ${e instanceof Error ? e.message : String(e)}`,
      502,
    );
  }

  // Upload to proposal-scenes/<user>/<draft>/scene_<idx>.png (upsert → allows regen).
  const storagePath = `${user.id}/${draftId}/scene_${sceneIndex}.png`;
  const { error: uploadErr } = await client.storage
    .from(SCENE_BUCKET)
    .upload(storagePath, imageBytes, {
      contentType: "image/png",
      upsert: true,
      cacheControl: "3600",
    });
  if (uploadErr) return errJson(`storage upload failed: ${uploadErr.message}`);

  // The prompt text (first part) is returned so the client can store it
  // alongside the image for traceability.
  const promptText = (parts[0] as { text?: string }).text ?? "";

  return corsOrJson({
    storage_path: `${SCENE_BUCKET}/${storagePath}`,
    prompt: promptText,
  });
});
