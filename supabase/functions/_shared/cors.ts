// CORS helper for Supabase Edge Functions invoked from the Flutter web client.
// We intentionally allow any origin because the Flutter web app may be hosted
// on multiple domains (dev preview, staging, prod). Tokens protect the call.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
