---
name: round5-phone-test-2026-11-14
description: "2026-11-14 phone test of the Round 4 build; 10 findings with user decisions, NOT built yet; start here next session"
metadata:
  node_type: memory
  type: project
  originSessionId: ff4c03c3-ba83-4f1c-a1b7-1129b5633410
  modified: 2026-11-15T17:40:10.780Z
---

Round 4 (see [[round4-feedback-2026-11-13]]) is fully built and pushed except F19. On 2026-11-14 both release APKs (still version 1.7.2) were built locally and installed on the user's phone via adb ([[local-apk-builds]]). User tested and gave 10 findings. Decisions are final; NOTHING BUILT YET. User asked to continue in a new session (usage limit).

**STATUS 2026-11-14 late session: items 1, 2, 3, 5a, 5b, 5d (pin dot centering only), 6, 7, 8 BUILT, type-checked, committed and pushed in all repos; migration 20261114000200_open_days_and_hours applied. Untested on phone. Item 1 also blocks the owner's "closed today" switch (closed_until), which create_booking never checked before. New tourist files: components/MapSheet.tsx, lib/openHours.ts (copy in owner). Item 4 mockup approved 2026-11-15 and BUILT (tourist 7fadb3a: booking-review + booking-confirm screens), untested on phone. 2026-11-16: F19 DONE (paymongo-checkout v19, external-api v23 deployed), both apps 1.8.0 (versionCode 12) installed on phone for testing; NOT released yet (user tests first, then release-files/v1.8.0 + upload). REMAINING: user phone test results, 5c (user sets Front Yard pin), F19 deploy + 1.8.0 bump + rebuild. Admin Destinations form still edits hours as free text only.**

**Build list (user said "yes build the rest"):**
1. Booking allowed when spot is closed. Decision C: owner sets open days + open/close time with pickers (operating_hours is free text now, e.g. "8am-5pm"); tourist calendar greys out closed days; same-day booking blocked after closing time. Needs new structured columns on destinations + owner Basic info "Hours and contact" section + tourist booking calendar + create_booking check.
2. Owner Tags and amenities screen is messy. Rebuild: one box per group (Activities, Food, Amenities), suggestions are tap-to-select chips that turn solid when chosen, one "Add your own" line; replace "Recommendation and Culinary agents" wording with plain words.
3. Subheadings must be bold and dark everywhere applicable (SectionHeader, Group labels, form labels) in BOTH apps: change in shared design components.
4. Tourist booking screens (Request sent / Owner confirmed / Review booking) look messy. MOCKUP FIRST in design-refs, wait for approval: status banner on top with what to do now, Trip block, Payment block, booking ID small at bottom, drop the "live" tags.
5. Maps: (a) Directions/route screen must be satellite by default with the layers button (currently satellite={false} in app/route/[destinationId].tsx); (b) map should fill the screen with route details in a draggable bottom sheet, same idea for Explore > Map; (c) Front Yard route looked wrong: DB pin is 7.788240, 122.581256, route follows the pin, so the saved pin is likely off. USER WILL SET THE PIN THEMSELVES; (d) NEW: pin labels/tags on spots "are not in the exact location": check divIcon anchor and label offset in LeafletMap.tsx on a real phone, and whether saved coordinates are off.
6. Star (Sparkles) icon still on "Plan a new trip", "Generate itinerary" and other AI spots. Decision B: use a route/map icon for trip planning; AskIcon (icon A) stays for search only.
7. AI search: the arrow on the send button becomes a magnifier; no icon on the left of the input.
8. AI search reasoning: (a) "hey" ran a full search; greetings/non-searches should get a short hello asking what they want, no list; (b) overview paragraph must name the #1 ranked place first and follow the list order.
9. AI limit: keep 100 per user per day (external-api, committed, not deployed). Models: gemini-3.5-flash then two lite fallbacks. Real usage 12-116 requests/day total, top single user 89. User still to check actual free-tier quota in AI Studio.

**Still pending from Round 4:** F19 = deploy edge functions paymongo-checkout + external-api (needs user OK), bump both apps to 1.8.0, rebuild, retest. D17 reading (removed Change password + Notifications rows from owner Profile tab) not yet confirmed by user.

**How to apply:** next session start with item 4 mockup or the quick ones (3, 6, 7, 5a), show the progress checklist after every task, rebuild + reinstall on phone when a batch is ready.
