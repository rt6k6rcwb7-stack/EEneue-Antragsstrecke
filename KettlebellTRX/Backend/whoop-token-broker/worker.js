/**
 * WHOOP-Token-Broker (Cloudflare Worker)
 *
 * Zweck: Das WHOOP-OAuth-Client-Secret darf nicht in der App liegen. Dieser minimale
 * Dienst tauscht den Autorisierungscode gegen Token und erneuert Token – sonst nichts.
 * Er speichert KEINE Token und KEINE Gesundheitsdaten und protokolliert keine Inhalte.
 *
 * Secrets (wrangler secret put …):
 *   WHOOP_CLIENT_ID, WHOOP_CLIENT_SECRET
 * Variablen (wrangler.toml [vars]):
 *   ALLOWED_REDIRECT_URI = "kbtrx://oauth/whoop"
 *
 * Endpunkte:
 *   POST /whoop/token    { "code": "...", "redirect_uri": "kbtrx://oauth/whoop" }
 *   POST /whoop/refresh  { "refresh_token": "..." }
 */
const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
const SCOPES = "offline read:recovery read:sleep read:cycles read:workout";

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    const url = new URL(request.url);
    let body;
    try { body = await request.json(); } catch { return json({ error: "invalid_json" }, 400); }

    const form = new URLSearchParams({
      client_id: env.WHOOP_CLIENT_ID,
      client_secret: env.WHOOP_CLIENT_SECRET,
    });

    if (url.pathname === "/whoop/token") {
      if (typeof body.code !== "string" || body.redirect_uri !== env.ALLOWED_REDIRECT_URI) {
        return json({ error: "invalid_request" }, 400);
      }
      form.set("grant_type", "authorization_code");
      form.set("code", body.code);
      form.set("redirect_uri", body.redirect_uri);
    } else if (url.pathname === "/whoop/refresh") {
      if (typeof body.refresh_token !== "string") return json({ error: "invalid_request" }, 400);
      form.set("grant_type", "refresh_token");
      form.set("refresh_token", body.refresh_token);
      form.set("scope", SCOPES);
    } else {
      return json({ error: "not_found" }, 404);
    }

    const upstream = await fetch(WHOOP_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const text = await upstream.text();
    // Antwort unverändert durchreichen (enthält access_token, refresh_token, expires_in, scope).
    return new Response(text, {
      status: upstream.status,
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  },
};

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
