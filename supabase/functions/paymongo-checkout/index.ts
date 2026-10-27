// Creates a PayMongo Checkout Session (GCash + Maya) for one of the caller's
// bookings. The amount comes from the DB row, never from the client: the
// down payment when one is required and nothing is paid yet, otherwise the
// remaining balance. The paid state is set exclusively by paymongo-webhook.

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

  const secretKey = Deno.env.get("PAYMONGO_SECRET_KEY");
  if (!secretKey) return json({ error: "PayMongo is not configured yet" }, 500);

  const { booking_id } = await req.json().catch(() => ({}));
  if (!booking_id) return json({ error: "booking_id is required" }, 400);

  // Client with the caller's JWT — RLS guarantees they can only see their own booking
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
  );

  const { data: booking, error } = await supabase
    .from("bookings")
    .select(
      "id, total_amount, amount_due_now, amount_paid, deposit_amount, payment_status, status, destinations(name)",
    )
    .eq("id", booking_id)
    .maybeSingle();
  if (error) return json({ error: error.message }, 500);
  if (!booking) return json({ error: "Booking not found" }, 404);

  const total = Number(booking.total_amount);
  const paid = Number(booking.amount_paid);
  const deposit = Number(booking.deposit_amount);

  if (booking.payment_status === "paid" || (total > 0 && paid >= total)) {
    return json({ error: "Booking is already paid" }, 400);
  }
  if (booking.payment_status === "not_required") {
    return json({ error: "Nothing to pay for this booking" }, 400);
  }
  if (booking.payment_status === "refunded") {
    return json({ error: "This booking was refunded" }, 400);
  }
  if (booking.status === "cancelled" || booking.status === "rejected") {
    return json({ error: `Cannot pay for a ${booking.status} booking` }, 400);
  }
  // Without a down payment, the owner accepts first and the tourist pays after.
  if (deposit === 0 && paid === 0 && booking.status !== "confirmed") {
    return json({ error: "Please wait for the owner to accept your booking before paying." }, 400);
  }

  // First payment: the down payment if one applies (or the full amount); after
  // that, whatever balance is left. Older bookings have no amount_due_now.
  const dueNow = paid === 0
    ? (Number(booking.amount_due_now) > 0 && deposit > 0 ? Number(booking.amount_due_now) : total)
    : total - paid;
  const kind = paid === 0 && deposit > 0 && dueNow < total ? "deposit" : paid === 0 ? "full" : "balance";

  const amountCentavos = Math.round(dueNow * 100);
  if (!amountCentavos || amountCentavos < 100) {
    return json({ error: "Booking amount is too small for online payment" }, 400);
  }

  const destName = (booking as any).destinations?.name ?? "IpilGo destination";
  const label = kind === "deposit" ? "Down payment" : kind === "balance" ? "Remaining balance" : "Booking";
  const returnUrl =
    `${Deno.env.get("SUPABASE_URL")}/functions/v1/paymongo-return?bid=${booking.id}`;

  const res = await fetch("https://api.paymongo.com/v1/checkout_sessions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Basic ${btoa(`${secretKey}:`)}`,
    },
    body: JSON.stringify({
      data: {
        attributes: {
          line_items: [
            {
              name: `${label} — ${destName}`,
              amount: amountCentavos,
              currency: "PHP",
              quantity: 1,
            },
          ],
          payment_method_types: ["gcash", "paymaya"],
          description: `Booking ${booking.id}`,
          reference_number: booking.id,
          metadata: { booking_id: booking.id, payment_kind: kind },
          success_url: `${returnUrl}&outcome=success`,
          cancel_url: `${returnUrl}&outcome=cancelled`,
          send_email_receipt: false,
          show_line_items: true,
        },
      },
    }),
  });

  const payload = await res.json().catch(() => null);
  if (!res.ok) {
    const detail = payload?.errors?.[0]?.detail ?? `PayMongo error ${res.status}`;
    return json({ error: detail }, 502);
  }

  return json({
    checkout_url: payload.data.attributes.checkout_url,
    checkout_session_id: payload.data.id,
    amount: dueNow,
    kind,
  });
});
