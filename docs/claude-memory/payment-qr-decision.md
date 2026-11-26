---
name: payment-qr-decision
description: 2026-11-25 payment approach UNDER DISCUSSION (not decided) — owner e-wallet QR vs PayMongo; user wants discussion before any decision
metadata:
  node_type: memory
  type: project
  originSessionId: 2a3c8d77-9b44-435c-95e3-6db85b446f5b
  modified: 2026-11-24T22:39:00.958Z
---

2026-11-25: discussing payment approach. NOTHING DECIDED. User asked (as a question, not a decision) whether to remove PayMongo and use only the owner's own GCash/Maya/e-wallet QR.

Context: PayMongo live (and every gateway, Stripe not in PH) needs BIR/business papers a student can't get; panel at mock defense wants real money received by owner and suggested QR.

Idea on table: owner uploads QR; tourist scans, pays, uploads receipt + ref no.; Gemini checks receipt; owner confirms. My recommendation: QR as main path, keep PayMongo (test mode) as second option, not removed.

2026-11-25 later: mockups done in canvas https://claude.ai/artifact/2VZ1XjHv9WVjJBHR9yEzRG (rows: minimal flow T/O, floating F1-F5 over current booking screen, owner auto-detect O4/O5, QR home Q1-Q3 = Profile > Payments). Ideas on table: amount embedded in owner QR (needs phone test), tourist just taps "I've paid" (F5), owner app reads GCash notification to auto-mark paid (Android, needs native module + test). User OK'd mockups, asked what's needed before build; open decisions listed in chat. Build NOT started.

DECIDED 2026-11-25 (still discussion, build NOT started, wait for user go): floating Option A (bottom card, made shorter: no "Use Maya", smaller QR); tourist taps "I've paid" (F5, no ref no.); REMOVE PayMongo; auto-detect later; GCash first; refunds: tourist cancels = no refund ever (12h free window dropped); owner cancels = owner refunds manually (O3), admin sees it; show "down payment non-refundable" + I-understand checkbox before paying.

Also agreed: owner "Not received" = booking back to "Pay down payment" + message to tourist; owner refund deadline 3 days then shows in admin. GCash "My QR" has its own "Add amount" button, so QR Ph amount field is supported (strong sign amount-in-QR works).

Plan adds: local reminder notification ~1 min after tourist leaves to GCash ("Done paying? Tap to confirm") opening the I've-paid card; GCash can't auto-return to app. I've-paid card shows when app returns to foreground; booking screen keeps I've-paid button as fallback.

2026-11-25 BUILD STARTED (user said go; ₱1 amount-in-QR test WORKED). Plan: 1 DB, 2 remove PayMongo, 3 owner, 4 tourist, 5 admin, 6 terms, 7 typecheck/commit.
- Step 1 DONE root 5e7b383: migration 20261125000000_gcash_qr_payments (profiles.gcash_qr QR Ph text; bookings.paid_claimed_at, refund_by; RPCs booking_payment_qr, tourist_mark_paid, owner_review_payment, owner_mark_refunded; refund cron unscheduled). Rollback-tested OK.
- Step 2 DONE root d828c8d: PayMongo fn sources removed. DEPLOYED fns (paymongo-checkout/return/webhook, booking-refunds) still live: ask user before deleting (no supabase CLI installed).
- Step 3 DONE owner 6c94377: expo-camera scanFromURLAsync reads QR picture (CAMERA perm blocked), lib/qrph.ts (isQrPh/qrAccountName/qrWithAmount, self-checked), claim + refund cards.
- Step 4 DONE tourist d6cda2e: GcashPayCard (react-native-qrcode-svg, expo-media-library save, Open GCash gcash://, AppState "Done paying?", 60s local reminder with data.url routed in NotificationsProvider), payment-result removed.
- Step 5 DONE admin f91509c: 'Refunds owners owe' list on Booking problems (late badge), PayMongo ref check removed.
- Step 6 DONE terms: tourist b1eede9, owner 759a6e2. All typecheck/build clean.

RESUME POINT: BUILD COMPLETE 2026-11-25, untested on phone. Open: user OK to delete deployed PayMongo edge fns (dashboard, no CLI); phone test needs new APKs (tourist adds expo-media-library + qrcode-svg, owner adds expo-camera = native rebuild). Risk: GCash must accept our rebuilt amount QR (CRC self-checked).

**Why:** user treats questions as discussion; earlier I wrongly saved a question as a decision.
**How to apply:** don't build or plan until user says decided. Explain in very short, plain language; long answers confused them. Refunds become manual with QR ([[cancellation-cutoff-plan]]).
