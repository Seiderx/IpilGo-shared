---
name: owner-v120-build-plan
description: Strict build plan for owner app v1.2.0 so it matches the tourist v1.2.0 Round 3 changes; continue from first step not marked DONE
metadata:
  node_type: memory
  type: project
  originSessionId: ac69e31b-59c5-4c54-b439-a3ff1f6eeb3b
  modified: 2026-10-29T13:46:56.939Z
---

## Progress checklist
Update this list as each step finishes (tick box, add date + commit hash). Show it to the user in chat at the start and end of every owner session.

- [x] Step 0 — Prep: clean uncommitted files, remove mic permission, refresh database types (2026-10-29, a034b22)
- [x] Step 1 — Login/signup fixes from tourist app + username field + PH phone check (2026-10-29, owner 464ee3d + root migration f3ebd08 owner_username_on_verify. Spot contact number accepts mobile OR landline. Gap: Google/Facebook owners still get no username — revisit in Step 11)
- [x] Step 2 — Server fixes: record cash, block Accept until deposit paid, Mark completed, entrance fee sync (2026-10-29, root 74e57d0 migration owner_booking_actions + owner ebd54e2. owner_record_payment(p_booking_id, p_amount) derives full/balance itself. Cash-entry form still TODO in Step 7. Entrance fee field in My Spot should go read-only when an entrance service exists — do in Step 5. Owner gets own "Payment received" notification after recording cash — minor, consider in Step 7. Tourist types lack owner_record_payment/entrance_service_price — harmless)
- [x] Step 3 — Fix crash: labels for all 6 payment statuses + safe fallback (2026-10-29, a034b22; done with Step 0 since fresh types forced it. requests.tsx filter labels still say Approved/Rejected — dies in Step 4 merge)
- [x] Step 4 — Remove guided-tours switch, merge Requests + History into Bookings, trim Profile, Help & Support (2026-10-29, owner 2f8d8d4. Bookings filters: Pending / Upcoming (all confirmed, even past date) / Past. Tab names Home/Bookings/My Spot/Profile. Rule lives in api.ts showsBookings(). New-spot owners with 0 services see no Bookings tab — Step 5 empty state must point them to Services)
- [x] Step 5 — Services & prices screen (2026-10-29, owner 83bbb2b. Route /services from My Spot card, spots only. Entrance fee field read-only when entrance service active)
- [x] Step 6 — Deposit rule settings (2026-10-29, owner aeffb27. Lives on Services & Prices screen, not My Spot form — preview uses first priced active service or ₱1,000)
- [x] Step 7 — Booking detail screen rework (items, deposit, countdown, payments, refunds, actions) (2026-10-29, owner 8c23127 + root 182e5bd cash_payment_notice: owner-recorded cash notifies TOURIST "Cash payment recorded". Tourist app should show 'payment' notification type fine — verify in Step 11)
- [x] Step 8 — Halal / dietary tags for restaurants (2026-10-29, owner 3af2eda. Tourist gap for next tourist release: isFoodPlace in lib/ai/dietary.ts ignores category Cafe/Restaurant — owner works around by adding 'food' tag. Tag edits re-pend the spot for admin approval (existing rule))
- [x] Step 9 — Dashboard earnings include down payments (2026-10-29. Earned = amount_paid − refund_amount, bookings dated this month. Refunds don't reduce amount_paid — booking-refunds edge fn only sets refunded_at/status)
- [x] Step 10 — Wording: "services" not "tour guides" (2026-10-29, only stale comments left; UI already clean)
- [x] Step 11 — Compare owner vs tourist shared code, fix leftovers (2026-10-29, owner 1d40b81 + 28b9e65: AuthProvider retry; tourist 3411229 UNRELEASED: mic permission blocked + isFoodPlace counts category Cafe/Restaurant — ships next tourist release. Backlog: Google/Facebook signups (both apps) get no username; 0 OAuth accounts exist so not urgent)
- [x] Step 12 — Build + release owner v1.2.0, re-apply free-booking migration (2026-10-29 RELEASED: owner 3f36916; user swapped IpilGo-Owner.apk inside existing GitHub Release v1.2.0 and pushed version.json owner 1.2.0 (ipilgo-apps 21f9d39). Migration 0500 re-applied via new file 20261029000300 — 5 ₱0 bookings now not_required. Phone test skipped by user.)
- [ ] Admin portal updates (separate plan)
- [ ] Phone test of whole batch (16 checks below)

## Details
Owner app v1.2.0 build plan (written 2026-10-29, user approved all recommendations 2026-10-29, not started). Must match tourist v1.2.0 (released 2026-10-28, see [[round3-tourist-feedback]]). Follow [[cross-app-parity]]. Work step by step, commit + push each step (owner repo is separate, see [[nested-git-repos]]). User tests everything on phone at the end ([[test-at-end]]). Build locally ([[local-apk-builds]]).

Source of truth = migrations 20261028000300 (services/deposits/create_booking/refund rules/protect trigger), 0400 (cron expire + refunds), 0500/0800 (not_required). Tourist reference code: ipilgo-tourist/src/lib/bookings.ts (depositFor, depositLabel, status labels), ipilgo-tourist/src/lib/ai/dietary.ts (tag values), tourist commit a124b16 (auth fixes).

**Step 0 — Prep.** Owner repo has UNCOMMITTED app.json (RECORD_AUDIO permission + eas projectId) and package.json (scripts expo run:*) from a past prebuild. APPROVED: remove RECORD_AUDIO; keep/discard rest after looking. Regenerate src/lib/database.types.ts from Supabase (stale: payment_status only unpaid/paid/refunded; no destination_services, booking_items, booking_payments, deposit_* columns).

**Step 1 — Auth parity with tourist (port tourist a124b16 + username):**
- Passwords trimmed of leading/trailing spaces on signup, login, reset, change (login retries raw value for old accounts with a real edge space). Files: login.tsx, PasswordCodeFlow.tsx, passwordPolicy.ts, AuthProvider.tsx, change-password.tsx.
- Verify screen: 20s timeout with session recovery (no endless spinner), clear "expired or replaced" message, 10-minute code countdown that resets on resend.
- After verifying, the username typed on THIS signup is applied (repeat signUp with same unverified email kept first attempt's username) — handle_user_email_confirmed already does this server-side; owner signup must send it.
- Signup sends display_name so the Supabase user list isn't blank.
- Owner signup currently has NO username field, but one account = tourist + owner. Add username with live availability check (is_username_available) + 3 tappable suggestions when taken (suggest_usernames RPC), same rules as tourist lib/username.ts (copy USERNAME_RULE/checkUsername).
- Owner has no PH phone validation; use the tourist/create_booking rule ^(09|\+639)[0-9]{9}$ wherever owner enters a phone (profile, destination contact).

**Step 2 — Backend gaps (migrations):**
- Owner CANNOT record cash today: protect_booking_payment_fields blocks payment fields for non-admins. Add security-definer RPC `owner_record_payment(p_booking_id, p_amount, p_kind 'full'|'balance')`: caller must be booking owner, booking confirmed/completed, 0 < amount <= total_amount - amount_paid; inserts booking_payments (recorded_by 'owner', method 'cash'), updates amount_paid, payment_status 'paid' when fully paid. Revoke from anon.
- Guard: status -> 'confirmed' requires deposit_amount = 0 or amount_paid >= deposit_amount. App disables Accept with "Waiting for down payment".
- Online full payment with no deposit: owner MAY accept before payment (approved), show "Unpaid" clearly.
- Add owner "Mark as completed" (confirmed + booking_date <= today); completed triggers review prompt. Check tourist review gating.
- Entrance fee auto-sync (approved): when an active service of kind 'entrance' exists, destinations.entrance_fee follows its price (trigger on destination_services insert/update/deactivate). Tourist AI budget/itinerary + cards read entrance_fee.

**Step 3 — Status labels (crash fix).** paymentStatusMeta in src/lib/api.ts covers all 6: unpaid, paid, refunded, not_required ("Free"), pay_on_site ("Pay on site"), deposit_paid ("Down payment paid"), plus fallback for unknown values (never index map directly: dashboard.tsx:249, history.tsx:80, requests.tsx:115, booking/[id].tsx:109-110). Same for bookingStatusMeta. Wording must match tourist.

**Step 4 — Remove/merge (approved 2026-10-29):**
- REMOVE "Offers guided tours" switch (destination.tsx ~441-450, save ~261) and every UI rule using offers_guided_tours (dashboard.tsx 116/147/155/186, (tabs)/_layout.tsx 11/21 tab hiding). New rule: bookings UI shows when spot has >= 1 active service OR any booking exists. DB column stays (no DROP), just unused. Admin Destinations.tsx 25/105/178/320 toggle removed too (admin step).
- MERGE Requests + History tabs into one "Bookings" tab with filters Pending / Upcoming / Past. Tabs become Home, Bookings, My Spot, Profile. Keep notification routes working ('booking_request'/'payment' -> Bookings).
- REMOVE profile menu links duplicating tabs (requests/history/destination) and profile booking stats (This Month/Bookings/Rating — dashboard has them). Keep Events & Promos + Reviews links.
- Help & Support: REMOVE (user has no support phone/email, decided 2026-10-29).
- KEEP: Events & Promos, Reviews/replies, Tourist Reach stats, hotel/restaurant details, OAuth, notifications, update prompt.

**Step 5 — Services & prices CRUD** (new screen from My Spot). destination_services: name 1-80, kind guide|boat|cottage|entrance|other, description, price >= 0, price_unit per_person|per_group|per_hour|per_item, is_active, sort_order. Deactivate instead of delete when ever booked. Empty state: "Tourists can't book until you add a service." Guided tours = a service of kind 'guide'.

**Step 6 — Deposit rule** (My Spot): deposit_type none|fixed|percent, deposit_value (percent 1-100, fixed > 0), deposit_refundable. Live preview using tourist depositFor math. Plain explanation: declined or unanswered 24h = full auto refund; non-refundable only when tourist cancels after owner accepted.

**Step 7 — Booking detail rework:** booking_items lines, total, deposit, due now, paid, payment_choice, respond_by countdown, refund_due/amount/refunded_at, ledger from booking_payments. Actions: Accept (gated), Decline (warn full refund), Record cash payment, Mark completed. Refetch items/payments on realtime change.

**Step 8 — Dietary tags** for food places (listing_type 'restaurant' or category Cafe/Restaurant): fixed chips writing destinations.tags EXACT values 'halal', 'no-pork', 'vegetarian', 'vegan'. Keep free-form tags. Warn "Only tick halal if it really is halal".

**Step 9 — Dashboard:** revenue from amount_paid (deposits count); counts awaiting-deposit, to-refund.

**Step 10 — Wording sweep:** "services", not "tour guides".

**Step 11 — Parity audit (per [[cross-app-parity]]):** before release, diff owner vs tourist for shared code (login, verify-email, PasswordCodeFlow, passwordPolicy, AuthProvider, UpdatePrompt, appUpdate, oauth, validation) and list anything fixed in one app but not the other. Fix owner now; note tourist-side gaps for next tourist release.

**Step 12 — Release owner v1.2.0:** version 1.2.0, versionCode 4; prebuild; assembleRelease; verify aapt2 + apksigner (same owner key as 1.1.1); GitHub Release with BOTH APKs; version.json owner -> 1.2.0 only. Then re-apply migration 0500.

**Then admin portal (separate plan):** remove guided-tours toggle; Bookings shows deposits/refunds/ledger, revenue from amount_paid, filter adds Free/Pay on site/Down payment paid; services + dietary tags on Destinations; fare_rules + fare_reference_points editor; analytics for bookings/deposits/refunds/itinerary use.

**Test checklist at end (PayMongo test mode, dummy spot):** owner signup with taken username -> suggestions; password with trailing space logs in; verify code expiry/resend; free booking; pay-on-site; online full; deposit paid then accept; deposit unpaid -> Accept blocked; decline after deposit -> auto refund; no answer 24h -> auto cancel + refund; tourist cancels after accept with non-refundable deposit -> deposit kept; record cash balance -> Paid; mark completed -> review prompt; entrance service price -> tourist card fee updates; halal tag -> tourist halal filter; spot with services but no bookings -> Bookings tab visible.

**Why:** user demanded a strict plan with no mismatch against tourist v1.2.0. **How to apply:** next owner session, start at Step 0, mark steps DONE here as they finish.
