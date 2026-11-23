---
name: owner-home-uncrowded
description: "Owner Home redesign goal 2026-11-23 — no overcrowded UI; dominant = day summary, never one tourist; user keeps own visual style"
metadata:
  node_type: memory
  type: feedback
  originSessionId: c1e69f99-2de9-454c-ae0f-792e0ebf9c79
  modified: 2026-11-23T05:26:07.641Z
---

Owner app Home restructure goal (2026-11-23): the user's main complaint is an OVERCROWDED UI. Keep their own design/architecture (colours, header, 4 tabs); the problem is what information goes on Home, not the look.

Rules agreed:
- Dominant item = summary of the day (bookings + guests count), never one featured tourist (biased, breaks with many same-day bookings; bookings have date only, no time).
- Every tourist gets an equal row; long lists truncate with "See all".
- Few sections; anything else belongs in Bookings / My Spot / Profile tabs.

**Why:** user rejected ~25 mockups (canvas https://claude.ai/artifact/GEmCSsnRCjcgZ6JY23n4D3) for being confusing, crowded, or biased toward one guest. They have no reference app and struggle to articulate, so ask one focused question at a time and show few options.
RESUME POINT (end of 2026-11-23 session): proposed a 3-block Home: (1) spot name + Live, (2) big "Today" box: "N bookings · M guests" or "No guests today · next: <date>", (3) today's guests as equal rows, max 5 + "See all". Move out: money to Profile > Payments, views/saves/AI picks to My Spot > Insights, snapshot removed (already in My Spot), 7-day strip to Bookings tab, zero tiles removed, "mark done"/"requests" become a badge on the Bookings tab. OPEN QUESTION to user: is 3 blocks right, or even less (just the today box + "See bookings")? Also open: check-in buttons vs list only. Nothing built in the app yet.

**How to apply:** max ~3 blocks on Home; plain wording; no stats/AI/weather/money clutter unless asked. Related: [[neat-organized-ui]], [[ui-redesign-direction]].
