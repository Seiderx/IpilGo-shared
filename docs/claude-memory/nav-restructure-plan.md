---
name: nav-restructure-plan
description: "2026-10-30 approved navigation/organization rework for tourist + owner apps (Trips tab, Explore map, owner My Spot hub, owner color B ink blue); prototype artifact is the spec"
metadata:
  node_type: memory
  type: project
  originSessionId: 6a8b3bb0-25b1-4a78-8f35-c1faf74cc791
  modified: 2026-10-30T07:39:42.814Z
---

User found the current apps disorganized (features hard to find, e.g. itinerary only reachable from Home cards). Approved rework, spec = clickable prototype https://claude.ai/artifact/CiEiyhj5yFpPcBFsrAjAU5 (local: IpilGo_Nav_Prototype.html at repo root, untracked).

Decisions:
- Owner accent = **B Ink blue**: light #2F4C86 (onAccent #FFFFFF), dark #94AEE6 (onAccent #0E1730). Tourist keeps terracotta #A8492A / #E39372. Rest of palette identical. NOTE: src/design is byte-identical between apps — accent must become a per-app override (e.g. small appAccent file outside design/) so design/ stays shared.
- Owner gets "Owner" label next to logo (header, login, welcome) + owner app icon in ink blue.
- Tourist tabs: Home · Explore · Trips · Profile. Trips = segmented Itineraries / Bookings / Saved. Saved tab removed; Profile loses My Bookings + Saved Places rows.
- Home trimmed to 4 sections: For you (merged Suggested+Recommended, with Why), Plan a trip card -> Trips, Popular in Ipil (Top+Trending), New in Ipil. "Your interests" chips leave Home.
- Tourist destination page: REMOVE the separate Photos grid section; hero photo is a swipeable gallery with dot indicator (user 2026-10-30: redundant).
- Explore gets List/Map switch (pins, user dot, tap pin -> preview card). Needs Google Maps key (see [[redesign-build-plan]] R step).
- Owner tabs unchanged (Home · Bookings · My Spot · Profile). My Spot becomes hub; old long edit form SPLIT by topic (user 2026-10-30: two rows opening same form was redundant): Basic info (name, description, category, location map+address+lat/lng, hours, contact) · Photos & 360° tour (own screen: cover photo, reorder, add/remove, panorama section) · Tags & amenities (activities/AI matching, food & dietary, amenities, with 'why this matters' note) · Services & prices (entrance fee MOVED here + services + down payment rule). Then Engage: Events & promos (moved from Profile), Reviews (moved from Profile, badge = need reply). Each sub-screen own Save. Owner Profile = account only.
- Admin: already redesigned (A1-A7). No recolor needed (web, different users); at most an "Admin" label in sidebar. Optional: tag tourist-side data terracotta, owner-side ink blue.

**Why:** organization, not looks — panel must find Itinerary Planner + real-time map easily; owner/tourist apps must be distinguishable in demo.
Progress 2026-10-30: step 1 DONE (owner 19ee3a1, tourist b7d27f3 — accent override lives in each app's src/appAccent.ts, ThemeProvider merges it; owner icon recolored with jimp-compact). Step 2 DONE (owner d0bbfe3 — hub in (tabs)/destination.tsx, screens src/app/spot/{basic,photos,tags,prices}.tsx, src/lib/mySpot.ts useMySpot/saveMySpot; entrance fee in services.tsx; no map on Basic info yet, waits for Maps key). Step 3 DONE (tourist 17cf81b — (tabs)/trips.tsx, src/components/trips/*, /itinerary + /bookings redirect to /trips?view=). Step 4 DONE (tourist 8d3ee67). Step 5 DONE (tourist 2468e43 — HeroGallery component). Step 6 DONE (tourist 4017c12 — src/components/ExploreMap.tsx, gated on EXPO_PUBLIC_GOOGLE_MAPS_API_KEY like route screen). ALL 6 STEPS BUILT 2026-10-30, typecheck clean, NOT phone-tested. v1.4.0 (versionCode 6) BUILT 2026-10-30: owner 7221763, tourist 6f9015f, APKs in release-files/v1.4.0 (signers match v1.3.0). RELEASED 2026-10-30: GitHub Release v1.4.0 live (sizes verified), ipilgo-apps 8fa88b2 version.json pushed. Next: Maps key -> owner Basic info map + v1.4.1; fix whatever user finds testing. User tests on installed release, no previews. Old plan said: user end test, then version bump/release (tourist with Maps key per R step; owner too). Not done: owner Basic info map (needs key), photo drag-reorder (tap-to-make-cover instead), admin "Admin" label (optional).

**How to apply:** build in this order, commit each: 1 owner accent+label+icon, 2 owner My Spot hub, 3 tourist Trips tab, 4 remove Saved tab/profile rows, 5 trim Home, 6 Explore map. Port shared bits per [[cross-app-parity]]. Release together after user's end test ([[test-at-end]]).
