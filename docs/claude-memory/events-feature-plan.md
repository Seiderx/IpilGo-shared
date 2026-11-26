---
name: events-feature-plan
description: "Events build steps 1-6 DONE 2026-11-27 (v1.9.0 code 14 bumped); next = step 7 user builds APKs + phone test"
metadata:
  node_type: memory
  type: project
  originSessionId: ef0c6b2b-0e21-4845-aab3-98da4c43927a
  modified: 2026-11-26T21:52:38.776Z
---

Problem (found 2026-11-25): town-wide events (admin, destination_id null) had no screen in the tourist app; only the AI event agent saw them when trip dates overlapped.

Mockups: https://claude.ai/artifact/BYZJG98b5t7J6n5y2WMQ6E (HomeB = PICKED carousel, AdminEvent, AdminFilter, EventDetail, AgentTrip, Notify).

DECIDED 2026-11-27 (user said "continue the build, another session"):
- Only TOWN events (admin) get Home banner + poster + notification. Spot events (owners) stay only on that spot's page, no poster, no change.
- Home = banner carousel (Home option 2). Every slide SAME size as "Where to in Ipil?" card (~150px). Auto-slide every 5 s, dots tappable. Order: town event today first, then "Where to in Ipil?", then town events within next 3 days (one slide each). Show from 3 days before until end.
- Notification to all tourists 3 days before + on the day.
- Event page: big poster, date/time/place, What's on, Why go (weather/route/safety agents), Remind me + Add to my trip.
- Agent: 3 days before, if tourist has a saved trip on that date, add event to that day + notify, Keep it / Remove. New trip on that date: planner includes it with why. No trip: nothing.
- Admin "New town event" modal: keep it, add Poster upload, Start time, Place (name + map pin).
- Admin filter bars (all list pages): search ~320px with icon, dropdowns beside it, result count right. CSS .filter-row + inline flex:1 in 6 pages.
- PayMongo edge fns (paymongo-checkout/return/webhook, booking-refunds): user deletes in Supabase dashboard (no MCP delete tool).

BUILD PLAN: 0 user deletes PayMongo fns · 1 DONE (posters in destination-images/admin/events/, no new bucket) DB (events: image_url, start_time, place_name, lat/lng; poster storage bucket + RLS) · 2 DONE (SearchBox component + .filter-count) admin form + filter bars · 3 DONE (lib/events.ts, EventCarousel, app/event/[id].tsx, itinerary_items.event_id + kind event, Add to my trip w/ no trip -> planner ?start&days=1&event=id; planner ignores event param until step 5) tourist carousel + event page · 4 DONE (SQL send_town_event_notices + cron town-event-notices 00:00 UTC; event_notices table; no new edge fn) push notifications (send-push + cron, 3 days before + day of) · 5 DONE (same SQL job adds to saved trips is_suggested; planner adds town events client side) event agent adds to saved trips · 6 DONE both apps 1.9.0/code 14; version.json NOT yet pushed (do after APKs built) · 7 user builds both APKs, one phone test of GCash + events.

**Why:** panel wants a real Event Monitoring agent that acts and explains why.
**How to apply:** start at Step 1 next session (ask if Step 0 done). Ship with GCash QR batch ([[payment-qr-decision]]) in one release ([[test-at-end]]). Keep replies VERY short and plain; user got lost on long answers.
