// PayMongo webhook receiver — the server-side payment verification step.
// Verifies the Paymongo-Signature HMAC before trusting anything, then records
// the payment in booking_payments (the payment ledger) and updates the
// booking with the service role. This (not the client) is the source of truth
// for payment authenticity; the stored payment id is the reference tourists,
// owners and admins verify against.
//
// Auth: custom — HMAC signature verification (verify_jwt must stay false;
// PayMongo cannot send a Supabase JWT).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const webhookSecret = Deno.env.get("PAYMONGO_WEBHOOK_SECRET");
  if (!webhookSecret) return new Response("Webhook secret not configured", { status: 500 });

  const rawBody = await req.text();

  // Header format: t=<timestamp>,te=<test-mode sig>,li=<live-mode sig>
  const sigHeader = req.headers.get("Paymongo-Signature") ?? "";
  const parts = Object.fromEntries(
    sigHeader.split(",").map((p) => p.split("=").map((s) => s.trim())),
  ) as Record<string, string>;
  const timestamp = parts["t"];
  const received = parts["li"] || parts["te"]; // live sig when present, else test
  if (!timestamp || !received) return new Response("Missing signature", { status: 401 });

  const expected = await hmacHex(webhookSecret, `${timestamp}.${rawBody}`);
  if (!timingSafeEqual(expected, received)) {
    return new Response("Invalid signature", { status: 401 });
  }

  const event = JSON.parse(rawBody);
  const type: string = event?.data?.attributes?.type ?? "";
  const resource = event?.data?.attributes?.data;

  // Only checkout_session.payment.paid records a payment. Failed/expired
  // events are acknowledged but change nothing, so the tourist can retry.
  if (type !== "checkout_session.payment.paid") {
    return new Response(JSON.stringify({ received: true, ignored: type }), { status: 200 });
  }

  const attrs = resource?.attributes ?? {};
  const bookingId: string | undefined =
    attrs?.metadata?.booking_id ?? attrs?.reference_number;
  const payment = attrs?.payments?.[0];
  const paymentId: string | undefined = payment?.id;
  const method: string =
    payment?.attributes?.source?.type ?? attrs?.payment_method_used ?? "paymongo";
  const centavos = Number(
    payment?.attributes?.amount ??
      (attrs?.line_items ?? []).reduce(
        (s: number, li: any) => s + Number(li.amount ?? 0) * Number(li.quantity ?? 1),
        0,
      ),
  );
  const amount = centavos / 100;

  if (!bookingId || !paymentId || !(amount > 0)) {
    return new Response("Event missing booking reference, payment id or amount", { status: 400 });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: booking, error: bErr } = await admin
    .from("bookings")
    .select("id, total_amount, amount_paid, deposit_amount")
    .eq("id", bookingId)
    .maybeSingle();
  if (bErr) return new Response(`DB read failed: ${bErr.message}`, { status: 500 });
  if (!booking) return new Response("Booking not found", { status: 404 });

  const total = Number(booking.total_amount);
  const paidBefore = Number(booking.amount_paid);
  const kind = paidBefore === 0
    ? (Number(booking.deposit_amount) > 0 && amount < total ? "deposit" : "full")
    : "balance";

  // The unique payment reference makes webhook retries a no-op.
  const { error: ledgerErr } = await admin.from("booking_payments").insert({
    booking_id: bookingId,
    kind,
    amount,
    method,
    reference: paymentId,
    recorded_by: "paymongo",
  });
  if (ledgerErr) {
    if (ledgerErr.code === "23505") {
      return new Response(JSON.stringify({ received: true, duplicate: true }), { status: 200 });
    }
    return new Response(`Ledger insert failed: ${ledgerErr.message}`, { status: 500 });
  }

  const paidAfter = paidBefore + amount;
  const { error } = await admin
    .from("bookings")
    .update({
      amount_paid: paidAfter,
      payment_status: paidAfter >= total ? "paid" : "deposit_paid",
      payment_reference: paymentId,
      payment_method: method,
    })
    .eq("id", bookingId);
  if (error) return new Response(`DB update failed: ${error.message}`, { status: 500 });

  return new Response(JSON.stringify({ received: true, booking_id: bookingId, kind }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
