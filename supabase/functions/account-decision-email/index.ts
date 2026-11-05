// Emails an owner or admin the outcome of their request, sent from the admin
// panel right after a status change.
//
// Auth: the caller must be an approved admin (verify_jwt on, plus getUser and
// a profile check). The address comes from the auth user, never the request,
// and the event must agree with the stored status, so this can't be used to
// send arbitrary mail or to announce a decision that wasn't made.
//
// Gmail over port 465: Supabase Edge Functions block outgoing 25 and 587.
// Secrets: SMTP_USER, SMTP_APP_PASSWORD.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6";

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

// Same logo as the admin panel. PNG, because mail apps can't all show WebP.
const LOGO_URL = "https://ipilgo-admin-onrender-com.onrender.com/favicon.png";

function escapeHtml(text: string): string {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

type Kind = "owner" | "admin";
type Mail = { subject: string; body: string };

// Each event, the stored status it requires, and the wording per account kind.
const EVENTS: Record<string, { status: "approved" | "rejected"; mail: Partial<Record<Kind, Mail>> }> = {
  approved: {
    status: "approved",
    mail: {
      owner: {
        subject: "Your IpilGo owner account is approved",
        body: "Your owner registration has been approved. You can now log in to the IpilGo Owner app and publish your destination.",
      },
      admin: {
        subject: "Your IpilGo admin access is approved",
        body: "Your request for admin access has been approved. You can now log in to the IpilGo admin console.",
      },
    },
  },
  reinstated: {
    status: "approved",
    mail: {
      owner: {
        subject: "Your IpilGo owner account is reinstated",
        body: "Your owner account has been reinstated. Your listings stay hidden until the Ipil Tourism Office reviews them again.",
      },
    },
  },
  declined: {
    status: "rejected",
    mail: {
      owner: {
        subject: "Your IpilGo owner registration was declined",
        body: "Your owner registration was not approved. For questions, please contact the Ipil Tourism Office.",
      },
      admin: {
        subject: "Your IpilGo admin request was declined",
        body: "Your request for admin access was not approved. For questions, please contact the Ipil Tourism Office.",
      },
    },
  },
  suspended: {
    status: "rejected",
    mail: {
      owner: {
        subject: "Your IpilGo owner account is suspended",
        body: "Your owner account has been suspended and your listings are hidden. Upcoming bookings were cancelled, and paid ones are refunded in full. For questions, please contact the Ipil Tourism Office.",
      },
    },
  },
  removed: {
    status: "rejected",
    mail: {
      admin: {
        subject: "Your IpilGo admin access was removed",
        body: "Your admin access has been removed. For questions, please contact the Ipil Tourism Office.",
      },
    },
  },
};

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

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: caller } = await admin
    .from("profiles")
    .select("role, admin_status")
    .eq("id", user.id)
    .maybeSingle();
  if (caller?.role !== "admin" || caller.admin_status !== "approved") {
    return json({ error: "Approved admins only" }, 403);
  }

  const input = await req.json().catch(() => null);
  const kind: unknown = input?.kind;
  const event = typeof input?.event === "string" && Object.hasOwn(EVENTS, input.event)
    ? EVENTS[input.event]
    : undefined;
  const userId = typeof input?.user_id === "string" ? input.user_id : "";
  if ((kind !== "owner" && kind !== "admin") || !event || !userId) {
    return json({ error: "Bad request" }, 400);
  }
  const mail = event.mail[kind];
  if (!mail) return json({ error: "Bad request" }, 400);

  const { data: target } = await admin
    .from("profiles")
    .select("full_name, role, owner_status, admin_status")
    .eq("id", userId)
    .maybeSingle();
  const status = kind === "owner" ? target?.owner_status : target?.admin_status;
  if (target?.role !== kind || status !== event.status) {
    return json({ error: "Status does not match this notice" }, 409);
  }

  const smtpUser = Deno.env.get("SMTP_USER");
  const smtpPass = Deno.env.get("SMTP_APP_PASSWORD");
  if (!smtpUser || !smtpPass) return json({ error: "Email not configured", code: "not_configured" }, 503);

  const { data: authUser, error: authErr } = await admin.auth.admin.getUserById(userId);
  const to = authUser?.user?.email;
  if (authErr || !to) return json({ error: "No email on this account" }, 404);

  const name = target.full_name || "there";
  const transport = nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 465,
    secure: true,
    auth: { user: smtpUser, pass: smtpPass },
  });

  try {
    await transport.sendMail({
      from: { name: "IpilGo", address: smtpUser },
      to,
      subject: mail.subject,
      text: `Hi ${name},\n\n${mail.body}\n\nIpil Tourism Office`,
      html: `<div style="max-width:480px;margin:0 auto;padding:24px;font-family:Arial,sans-serif;font-size:15px;line-height:1.6;color:#0F4C5C">
<img src="${LOGO_URL}" width="64" height="64" alt="IpilGo" style="display:block;margin-bottom:16px">
<p>Hi ${escapeHtml(name)},</p>
<p>${escapeHtml(mail.body)}</p>
<p>Ipil Tourism Office</p>
</div>`,
    });
  } catch (e) {
    console.error("decision email failed", e instanceof Error ? e.message : e);
    return json({ error: "Email could not be sent" }, 502);
  }
  return json({ sent: true });
});
