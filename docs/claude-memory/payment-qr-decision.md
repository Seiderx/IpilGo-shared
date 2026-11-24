---
name: payment-qr-decision
description: 2026-11-25 payment approach UNDER DISCUSSION (not decided) — owner e-wallet QR vs PayMongo; user wants discussion before any decision
metadata:
  node_type: memory
  type: project
  originSessionId: 2a3c8d77-9b44-435c-95e3-6db85b446f5b
  modified: 2026-11-24T22:37:07.687Z
---

2026-11-25: discussing payment approach. NOTHING DECIDED. User asked (as a question, not a decision) whether to remove PayMongo and use only the owner's own GCash/Maya/e-wallet QR.

Context: PayMongo live (and every gateway, Stripe not in PH) needs BIR/business papers a student can't get; panel at mock defense wants real money received by owner and suggested QR.

Idea on table: owner uploads QR; tourist scans, pays, uploads receipt + ref no.; Gemini checks receipt; owner confirms. My recommendation: QR as main path, keep PayMongo (test mode) as second option, not removed.

2026-11-25 later: mockups done in canvas https://claude.ai/artifact/2VZ1XjHv9WVjJBHR9yEzRG (rows: minimal flow T/O, floating F1-F5 over current booking screen, owner auto-detect O4/O5, QR home Q1-Q3 = Profile > Payments). Ideas on table: amount embedded in owner QR (needs phone test), tourist just taps "I've paid" (F5), owner app reads GCash notification to auto-mark paid (Android, needs native module + test). User OK'd mockups, asked what's needed before build; open decisions listed in chat. Build NOT started.

DECIDED 2026-11-25 (still discussion, build NOT started, wait for user go): floating Option A (bottom card, made shorter: no "Use Maya", smaller QR); tourist taps "I've paid" (F5, no ref no.); REMOVE PayMongo; auto-detect later; GCash first; refunds: tourist cancels = no refund ever (12h free window dropped); owner cancels = owner refunds manually (O3), admin sees it; show "down payment non-refundable" + I-understand checkbox before paying.

Also agreed: owner "Not received" = booking back to "Pay down payment" + message to tourist; owner refund deadline 3 days then shows in admin. GCash "My QR" has its own "Add amount" button, so QR Ph amount field is supported (strong sign amount-in-QR works).

Plan adds: local reminder notification ~1 min after tourist leaves to GCash ("Done paying? Tap to confirm") opening the I've-paid card; GCash can't auto-return to app. I've-paid card shows when app returns to foreground; booking screen keeps I've-paid button as fallback.

RESUME POINT: all decisions final 2026-11-25; user will build in a NEW session. Next = write step-by-step build plan for approval (tourist + owner + admin + DB/edge fn removal of PayMongo), then build. Ask if user did the ₱1 GCash "Add amount" QR test.

**Why:** user treats questions as discussion; earlier I wrongly saved a question as a decision.
**How to apply:** don't build or plan until user says decided. Explain in very short, plain language; long answers confused them. Refunds become manual with QR ([[cancellation-cutoff-plan]]).
