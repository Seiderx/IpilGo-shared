// Sends PayMongo refunds for bookings the database marked refund_due:
// the owner declined, nobody answered within 24h, or the tourist cancelled
// (see booking_refund_rules()). Called every few minutes by pg_cron.
//
// Each booking is claimed (refund_due -> false) before any money moves, so two
// overlapping runs can never refund the same booking twice. If PayMongo
// rejects a refund the claim is released and the next run retries.
//
// Auth: custom — shared secret in the x-cron-secret header, compared with the
// one pg_cron reads from Supabase Vault (verify_jwt off; pg_cron sends no
// Supabase JWT). See migration 20261028000400_booking_jobs.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type LedgerRow = { amount: number; reference: string | null; method: string | null };

Deno.serve(async (req: Request) => {
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: cronSecret } = await admin.rpc("booking_refunds_secret");
  if (!cronSecret || req.headers.get("x-cron-secret") !== cronSecret) {
    return new Response("Unauthorized", { status: 401 });
  }
  const secretKey = Deno.env.get("PAYMONGO_SECRET_KEY");
  if (!secretKey) return new Response("PayMongo is not configured", { status: 500 });

  const { data: claimed, error: claimErr } = await admin
    .from("bookings")
    .update({ refund_due: false })
    .eq("refund_due", true)
    .is("refunded_at", null)
    .select("id, refund_amount, amount_paid");
  if (claimErr) return new Response(`Claim failed: ${claimErr.message}`, { status: 500 });

  const results: { booking_id: string; ok: boolean; detail?: string }[] = [];

  for (const b of claimed ?? []) {
    let remaining = Number(b.refund_amount);
    let failed: string | null = null;

    const { data: ledger } = await admin
      .from("booking_payments")
      .select("amount, reference, method")
      .eq("booking_id", b.id)
      .eq("recorded_by", "paymongo")
      .in("kind", ["deposit", "full", "balance"])
      .order("created_at", { ascending: true });

    for (const p of (ledger ?? []) as LedgerRow[]) {
      if (remaining <= 0 || !p.reference) continue;
      const amount = Math.min(remaining, Number(p.amount));
      const res = await fetch("https://api.paymongo.com/v1/refunds", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Basic ${btoa(`${secretKey}:`)}`,
        },
        body: JSON.stringify({
          data: {
            attributes: {
              amount: Math.round(amount * 100),
              payment_id: p.reference,
              reason: "requested_by_customer",
              notes: `IpilGo booking ${b.id}`,
            },
          },
        }),
      });
      const payload = await res.json().catch(() => null);
      if (!res.ok) {
        failed = payload?.errors?.[0]?.detail ?? `PayMongo error ${res.status}`;
        break;
      }
      await admin.from("booking_payments").insert({
        booking_id: b.id,
        kind: "refund",
        amount,
        method: p.method,
        reference: payload?.data?.id ?? null,
        recorded_by: "paymongo",
      });
      remaining -= amount;
    }

    if (failed) {
      // Release the claim so the next run tries again.
      await admin.from("bookings").update({ refund_due: true }).eq("id", b.id);
      results.push({ booking_id: b.id, ok: false, detail: failed });
      continue;
    }

    const fullyRefunded = Number(b.refund_amount) >= Number(b.amount_paid);
    await admin
      .from("bookings")
      .update({
        refunded_at: new Date().toISOString(),
        ...(fullyRefunded ? { payment_status: "refunded" } : {}),
      })
      .eq("id", b.id);
    results.push({ booking_id: b.id, ok: true });
  }

  return new Response(JSON.stringify({ processed: results.length, results }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
