// Google Cloud service-account OAuth token minter for Edge Functions.
//
// Signs a JWT with the service account private key (RS256) and exchanges it
// at https://oauth2.googleapis.com/token for a short-lived access token with
// the Vertex AI scope. Uses only the Web Crypto API — no extra dependencies.
//
// Usage:
//   const sa = JSON.parse(Deno.env.get("GCP_SERVICE_ACCOUNT_JSON")!);
//   const token = await getGcpAccessToken(sa);
//   fetch(vertexUrl, { headers: { Authorization: `Bearer ${token}` } });

export interface GcpServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

const DEFAULT_SCOPE = "https://www.googleapis.com/auth/cloud-platform";
const DEFAULT_TOKEN_URI = "https://oauth2.googleapis.com/token";

function base64UrlEncode(input: string | Uint8Array): string {
  const bytes =
    typeof input === "string" ? new TextEncoder().encode(input) : input;
  let str = "";
  for (let i = 0; i < bytes.length; i++) {
    str += String.fromCharCode(bytes[i]);
  }
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

async function signJwt(
  header: Record<string, unknown>,
  claims: Record<string, unknown>,
  privateKeyPem: string,
): Promise<string> {
  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const claimsB64 = base64UrlEncode(JSON.stringify(claims));
  const toSign = `${headerB64}.${claimsB64}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(toSign),
  );
  return `${toSign}.${base64UrlEncode(new Uint8Array(signature))}`;
}

export async function getGcpAccessToken(
  sa: GcpServiceAccount,
  scope: string = DEFAULT_SCOPE,
): Promise<string> {
  const tokenUri = sa.token_uri ?? DEFAULT_TOKEN_URI;
  const nowSec = Math.floor(Date.now() / 1000);
  const jwt = await signJwt(
    { alg: "RS256", typ: "JWT" },
    {
      iss: sa.client_email,
      scope,
      aud: tokenUri,
      iat: nowSec,
      exp: nowSec + 3600,
    },
    sa.private_key.replace(/\\n/g, "\n"), // handle escaped newlines
  );

  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion: jwt,
  });
  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`GCP token exchange failed: ${response.status} ${text}`);
  }
  const json = await response.json();
  return json.access_token as string;
}
