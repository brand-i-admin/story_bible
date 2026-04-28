// 사용자가 한국어로 쓴 prompt 를 Imagen 이 잘 이해하는 영어로 번역.
//
// Imagen 4/3 는 영어 prompt 에 가장 강하게 반응한다 — 한국어 명사(지팡이/책/안경 등)
// 는 자주 무시되거나 약하게 반영돼 사용자가 의도한 시각 요소가 누락된 채 generic
// 인물 이미지가 나오는 문제가 있다. 이를 해결하기 위해 Imagen 호출 직전에
// Vertex Gemini 1.5 Flash 로 한국어 → 영어 번역 단계를 추가한다.
//
// - 입력에 한국어 글자가 없으면 (이미 영어) 그대로 반환 — 비용/지연 절약
// - 번역 실패 시 원문 그대로 반환 (graceful degradation — 일부 누락이 있더라도
//   생성 자체는 진행)

const HANGUL_RE = /[가-힯ᄀ-ᇿ㄰-㆏]/;

export function containsKorean(text: string): boolean {
  return HANGUL_RE.test(text);
}

/**
 * Vertex Gemini 1.5 Flash 로 한국어 character description 을 영어 image prompt
 * 로 번역. 모든 구체적 시각 요소(props, 의상, 액세서리, 나이, 머리, 체형)를
 * 보존하도록 명시 instruction.
 *
 * @param text 사용자 입력 (한국어 또는 영어)
 * @param accessToken GCP OAuth access_token
 * @param project    GCP project id
 * @param location   Vertex region (보통 us-central1; "global" 은 자동 fallback)
 * @returns 영어 prompt. 번역 실패 또는 한국어 미포함 시 원문 그대로.
 */
export async function translateForImagePrompt(
  text: string,
  accessToken: string,
  project: string,
  location: string,
): Promise<string> {
  const trimmed = text.trim();
  if (!trimmed) return trimmed;
  if (!containsKorean(trimmed)) return trimmed;

  const loc = location === "global" ? "us-central1" : location;
  const url =
    `https://${loc}-aiplatform.googleapis.com/v1/projects/${project}/` +
    `locations/${loc}/publishers/google/models/gemini-1.5-flash:generateContent`;

  const instruction =
    "You are an expert prompt engineer for image generation models. " +
    "Translate the following Korean character description to a precise, " +
    "vivid English prompt suitable for an image generator. " +
    "PRESERVE every concrete visual element exactly: props the character holds " +
    "(e.g., staff, book, sword), clothing and accessories (e.g., glasses, hat, robe), " +
    "age (e.g., young, old, middle-aged), hair (color, length, style), body type, " +
    "facial features, mood. Do not omit any concrete noun. " +
    "Output ONLY the English prompt as a single concise sentence. " +
    "No explanation, no quotes, no labels.\n\n" +
    `Korean: ${trimmed}\n` +
    "English:";

  const body = {
    contents: [
      {
        role: "user",
        parts: [{ text: instruction }],
      },
    ],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 256,
    },
  };

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      console.warn(
        `[translate] Gemini ${res.status}: ${(await res.text()).slice(0, 200)}`,
      );
      return trimmed;
    }
    const json = (await res.json()) as Record<string, unknown>;
    const candidates = json["candidates"];
    if (!Array.isArray(candidates) || candidates.length === 0) return trimmed;
    const first = candidates[0] as Record<string, unknown>;
    const content = first["content"] as Record<string, unknown> | undefined;
    const parts = content?.["parts"];
    if (!Array.isArray(parts) || parts.length === 0) return trimmed;
    const txt = (parts[0] as Record<string, unknown>)["text"];
    if (typeof txt !== "string") return trimmed;
    const cleaned = txt.trim().replace(/^["']+|["']+$/g, "");
    return cleaned.length > 0 ? cleaned : trimmed;
  } catch (e) {
    console.warn(
      `[translate] failed: ${e instanceof Error ? e.message : String(e)}`,
    );
    return trimmed;
  }
}
