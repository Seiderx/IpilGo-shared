---
name: round3-tourist-feedback
description: "2026-10-28 Round 3 tourist-app test feedback (group + adviser) — decisions agreed in discussion, build not started; owner-app review next day"
metadata:
  node_type: memory
  type: project
  originSessionId: ac69e31b-59c5-4c54-b439-a3ff1f6eeb3b
  modified: 2026-10-29T13:47:07.221Z
---

Discussion-first session 2026-10-28: user, groupmates and adviser tested the tourist app. User wants a debate before any building; owner app is reviewed 2026-10-29, then a final priority order.

Booking pivot (supersedes "guide-only" in [[scope-decisions]]): Ipil has no tour guide association, so booking becomes **spot-owner services** (boat, cottage, entrance, guide...). The approved Thesis 1 doc still holds because guides remain, as one service. Plan: structured `destination_services` table plus booking line items with price snapshots, not free text in the description. Rename "Book a Guide" to "Book" and hide it when a spot has no services. Flow: choose services, then "View your booking" summary, then payment method (e-pay or pay in person). ₱0 total means no payment needed.

Decisions made:
- Website: the incompatibility note is about iOS.
- Password: "X" and "X " must both log in. Trim at signup and login, with a raw fallback for old accounts.
- Budget step resets when going back (the adviser wants this).
- Family min 3, barkada min 2. Solo locked at 1, couple at 2, count starts at 0.
- Itinerary may add extra spots marked "Suggested", plus hotel and meals. No repeated spots.
- Phone: PH mobile format check only (no SMS OTP).
- Some owners require a down payment before accepting, so deposit support is needed.

Root causes found:
- The signup trigger claims the username before email verification. A re-signup with the same email keeps the old username.
- The itinerary prompt forces "2–4 stops/day", which causes repeats.

Answers 2026-10-28 (later): each owner decides whether the deposit is refundable or non-refundable. Tricycle fare is per passenger, with no discounts. Owner reject or no reply within 24h means auto-refund. Build the tourist app now; the owner app waits. Build order: 1 auth integrity, 2 quick fixes, 3 itinerary, 4 booking (tourist side + schema), 5 culinary/search, 6 fare engine, 7 website.

Permission (2026-10-28): user pre-approved all Round 3 migrations, applied without asking each time. List every migration in the summaries. Destructive changes still need a confirm.

The claude.ai Supabase connector declines apply_migration, but reads work. The user runs migration SQL in the dashboard SQL Editor instead (step 1 done that way). If declined again, hand the user the SQL file path rather than retrying.
Never run `npx expo lint`: there's no eslint in the tourist app, and it auto-installs one, rewriting package.json and the lockfile. Use `npx tsc --noEmit` only.
ROOT CAUSE of the declined migrations: the connector declines any SQL containing DROP (trigger, policy...), because it needs an interactive confirm this session can't show. Write migrations without DROP statements (use create-only on new objects, or `create or replace`). If a DROP is truly needed, hand that SQL to the user for the SQL Editor.
apply_migration worked again on 2026-10-28 (after the user changed connector settings), so try it first.
IMPORTANT: the installed v1.1.1 owner and tourist apps crash on payment statuses they don't know: `paymentStatusMeta[status].label` has no fallback. Migration 0800 reverted the 5 old ₱0 bookings to 'unpaid'. Re-apply 0500 (not_required) only after BOTH v1.2.0 apps are released. DONE 2026-10-29 (owner v1.2.0 released, migration 20261029000300). The owner-app work must handle not_required / pay_on_site / deposit_paid, plus a fallback for unknown statuses.
TOURIST v1.2.0 RELEASED 2026-10-28 (GitHub Release v1.2.0 with tourist 1.2.0 + unchanged owner 1.1.1 APK; version.json tourist 1.2.0, owner 1.1.1, ipilgo-apps 5f6c5bc). Maps API key still empty. STEP 7 DONE (ipilgo-apps ea66e42). ALL 7 TOURIST STEPS DONE 2026-10-28. Next: build the v1.2.0 tourist release (the user tests the batch) and the owner-app review (services/prices, deposit rule, accept/decline, mark cash paid, halal/no-pork tags).
STEP 6 DONE (tourist 89eb925, root 9efe64c migration 0700): fare_rules, fare_reference_points (56 LGU rows), fare_accuracy view at 56/56 = 100%. The Google road distance vs LGU distance comparison is still a field test to do. Next: step 7 website (ipilgo-apps).
STEP 5 DONE (tourist b5c6ca5): dietary hard filter in lib/ai/dietary.ts using tags halal / no-pork / pork-free / vegetarian / vegan. The owner app needs a way to set these tags on restaurants. Next: step 6 fare engine.
STEP 4 DONE (tourist a477362, root a7d3244; migrations 0300-0600; edge functions paymongo-checkout v2, paymongo-webhook v2, booking-refunds v2, with source now in supabase/functions/). No destination has services yet, so Book is hidden everywhere until the owner app adds services (owner app: services CRUD, deposit rule, accept/decline, mark cash paid). The booking DB rules were NOT live-tested: a rollback test was blocked as a shared-DB write. Next: step 5 culinary/search.
STEP 3 DONE (tourist fa160ed, root b8044ff migration 20261028000200 itinerary_item_kinds). The DB has 5 spots and 0 hotels/restaurants, so meals and stays show plain slots until owners or admin add listings. Next: step 4 booking.
STEP 2 DONE (tourist 9464240, root 091dca7 migration 20261028000100 review_authors). Next: step 3 itinerary rework.
Progress: STEP 1 DONE 2026-10-28 (tourist a124b16, root a844fb3 migration 20261028000000; emz_prince renamed to emz_2026). Next: step 2 quick fixes.

Fare data received: Ipil Municipal Ordinance 03-748-2026, tricycle fare = 20 + 5 × max(0, ceil(km) − 1), from Ipil Rotunda. It matches every row of the LGU fare guide images.

**Why:** these settle open questions so later sessions don't re-argue them.
**How to apply:** don't start the booking rework until after the owner review. Show priority and status as a checklist in chat ([[checklists-in-chat]]).
