// Sends one notification row to the user's phones through Firebase Cloud
// Messaging, so it arrives while the app is closed. Called by the
// notifications_forward_to_push database trigger.
//
// Auth: shared secret in the x-push-secret header, compared with the one kept
// in Supabase Vault (verify_jwt off; the trigger has no user session).
//
// Secret: FCM_SERVICE_ACCOUNT, the Firebase service account JSON.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

type ServiceAccount = { client_email: string; private_key: string; project_id: string };

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const CHANNEL_ID = "default";

let cachedAccess: { token: string; expiresAt: number } | null = null;

async function accessToken(account: ServiceAccount): Promise<string> {
  if (cachedAccess && Date.now() < cachedAccess.expiresAt) return cachedAccess.token;
  const key = await importPKCS8(account.private_key, "RS256");
  const assertion = await new SignJWT({ scope: SCOPE })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setAudience(TOKEN_URL)
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`Google token request failed (${res.status})`);
  const data = await res.json();
  cachedAccess = { token: data.access_token, expiresAt: Date.now() + (data.expires_in - 60) * 1000 };
  return cachedAccess.token;
}

Deno.serve(async (req: Request) => {
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: secret } = await admin.rpc("push_webhook_secret");
  if (!secret || req.headers.get("x-push-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return new Response("Push is not configured", { status: 500 });
  const account = JSON.parse(raw) as ServiceAccount;

  const { user_id, title, body, type } = await req.json();
  const { data: devices, error } = await admin
    .from("device_push_tokens")
    .select("token")
    .eq("user_id", user_id);
  if (error) return new Response(error.message, { status: 500 });
  if (!devices?.length) return Response.json({ sent: 0 });

  const bearer = await accessToken(account);
  const url = `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;
  let sent = 0;
  for (const { token } of devices) {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${bearer}` },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body: body ?? "" },
          data: { type: type ?? "" },
          android: { priority: "HIGH", notification: { channel_id: CHANNEL_ID, sound: "default" } },
        },
      }),
    });
    if (res.ok) {
      sent += 1;
    } else if (res.status === 404) {
      // The app was uninstalled or the token rotated.
      await admin.from("device_push_tokens").delete().eq("token", token);
    } else {
      console.warn(`fcm ${res.status}: ${(await res.text()).slice(0, 200)}`);
    }
  }
  return Response.json({ sent });
});
