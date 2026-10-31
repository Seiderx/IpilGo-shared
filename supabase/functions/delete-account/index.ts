// Self-service account deletion for the tourist and owner apps.
//
// The app shows the warning and makes the user type their username (or
// DELETE when the account has none); this function checks that again, lets
// prepare_account_deletion() settle bookings (unpaid upcoming ones cancelled,
// past ones anonymised, blocked while money or an owner's booking is still
// open), removes the profile photo, then deletes the auth user. Everything
// else goes with the profile through the foreign keys.
//
// Auth: the caller must be a signed-in user (verify_jwt on, plus getUser);
// a user can only ever delete their own account.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "Sign in required" }, 401);

  const input = await req.json().catch(() => null);
  const typed = typeof input?.confirm === "string" ? input.confirm.trim().toLowerCase() : "";

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: profile } = await admin
    .from("profiles")
    .select("username")
    .eq("id", user.id)
    .maybeSingle();
  const expected = (profile?.username || "delete").toLowerCase();
  if (typed !== expected) {
    return json({ error: "Type your username exactly to confirm.", code: "confirm_mismatch" }, 400);
  }

  const { data: blockers, error: blockErr } = await admin.rpc("account_deletion_blockers", { p_user: user.id });
  if (blockErr) return json({ error: blockErr.message }, 500);
  if (blockers?.length) {
    return json({ error: "Settle these bookings first.", code: "blocked", blockers }, 409);
  }

  const { error: prepErr } = await admin.rpc("prepare_account_deletion", { p_user: user.id });
  if (prepErr) return json({ error: prepErr.message }, 500);

  // Profile photos live under avatars/<user id>/.
  const { data: files } = await admin.storage.from("avatars").list(user.id, { limit: 100 });
  if (files?.length) {
    await admin.storage.from("avatars").remove(files.map((f) => `${user.id}/${f.name}`));
  }

  const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
  if (delErr) return json({ error: delErr.message }, 500);

  return json({ ok: true });
});
