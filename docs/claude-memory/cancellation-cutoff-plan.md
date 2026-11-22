---
name: cancellation-cutoff-plan
description: "Approved 2026-11-10, NOT built — replace refundable on/off switch with cancellation cutoff; 5 fixes + 3 open questions"
metadata:
  node_type: memory
  type: project
  originSessionId: b23c1e89-6729-4f07-b673-393142319512
  modified: 2026-11-10T07:31:47.555Z
---

User agreed on 2026-11-10 to the 5 fixes below but said do not build yet ("tackle it soon"). Wait for user go.

**Why:** Owner prepares for a booked service, tourist cancels last minute, down payment is refunded, owner is lugi. Current system has only an on/off switch `destinations.deposit_refundable` (default true), snapshotted onto the booking; `booking_refund_rules()` has no time check, so one month early and one hour early are treated the same.

**Agreed fixes:**
1. Cancellation cutoff replaces the switch. Owner picks: free cancel anytime / until 24h before / until 48h before / no refund once accepted. After cutoff owner keeps the whole down payment; before it, full refund. Existing bookings keep the rule they were booked under.
2. Default for new owners = 24h before, not "anytime".
3. Tourist must agree: booking review screen shows the exact deadline and peso amount, checkbox before Pay works; cancel popup and booking details show the same deadline.
4. Weather: no automatic rule. Tourist asks, admin cancels (already full refund). Zero new code.
5. Down payment screen cleanup in owner `src/app/services.tsx`: red warning right away when percent > 100; preview labelled "Example" with a realistic total (now uses first priced service price, misleading).

**Open questions, ask before building:**
- Are the four choices right, or different hours?
- Late cancel: owner keeps whole down payment or half?
- Bookings have a date only, no hour. Proposed wording "Free cancel until 1 day before trip" (count from start of trip day). Confirm.

**How to apply:** Touches DB (refund rule trigger, `create_booking`), owner app setting, tourist destination page + booking-review + cancel popup in `BookingList.tsx`, admin destination view. Follow [[cross-app-parity]]; drop/mass-update SQL per [[supabase-mcp-destructive-decline]]; test per [[test-at-end]]. Not yet verified: whether tourist can cancel on or after trip day, and the Save check for fixed amount.
