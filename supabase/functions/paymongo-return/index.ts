// Browser return trampoline after PayMongo checkout. PayMongo requires an
// https success/cancel URL; this bounces the user back into the app via the
// ipilgotourist:// scheme so the in-app browser session closes. It grants
// nothing — payment state comes only from the signed webhook.
//
// A plain 302 redirect, not an HTML page: Supabase serves function HTML as
// text/plain, so a page with a script redirect showed its raw source and
// never returned to the app. Same pattern as the OAuth sign-in redirect.
//
// Auth: none needed — no data access (verify_jwt false because the redirect
// arrives from PayMongo's checkout, not the app).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve((req: Request) => {
  const url = new URL(req.url);
  const bid = url.searchParams.get("bid") ?? "";
  const outcome = url.searchParams.get("outcome") === "cancelled" ? "cancelled" : "success";
  const deepLink =
    `ipilgotourist://payment-result?bid=${encodeURIComponent(bid)}&outcome=${outcome}`;
  return new Response(null, { status: 302, headers: { Location: deepLink } });
});
