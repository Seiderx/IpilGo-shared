---
name: owner-home-uncrowded
description: "Owner Home redesign goal 2026-11-23 — no overcrowded UI; dominant = day summary, never one tourist; user keeps own visual style"
metadata:
  node_type: memory
  type: feedback
  originSessionId: c1e69f99-2de9-454c-ae0f-792e0ebf9c79
  modified: 2026-11-23T07:01:58.702Z
---

Owner app Home restructure goal (2026-11-23): the user's main complaint is an OVERCROWDED UI. Keep their own design/architecture (colours, header, 4 tabs); the problem is what information goes on Home, not the look.

Rules agreed:
- Dominant item = summary of the day (bookings + guests count), never one featured tourist (biased, breaks with many same-day bookings; bookings have date only, no time).
- Every tourist gets an equal row; long lists truncate with "See all".
- Few sections; anything else belongs in Bookings / My Spot / Profile tabs.

**Why:** user rejected ~25 mockups (canvas https://claude.ai/artifact/GEmCSsnRCjcgZ6JY23n4D3) for being confusing, crowded, or biased toward one guest. They have no reference app and struggle to articulate, so ask one focused question at a time and show few options.
RESUME POINT (end of 2026-11-23 session): proposed a 3-block Home: (1) spot name + Live, (2) big "Today" box: "N bookings · M guests" or "No guests today · next: <date>", (3) today's guests as equal rows, max 5 + "See all". Move out: money to Profile > Payments, views/saves/AI picks to My Spot > Insights, snapshot removed (already in My Spot), 7-day strip to Bookings tab, zero tiles removed, "mark done"/"requests" become a badge on the Bookings tab. OPEN QUESTION to user: is 3 blocks right, or even less (just the today box + "See bookings")? Also open: check-in buttons vs list only. Nothing built in the app yet.

UPDATE 2026-11-23 afternoon: user CHOSE the lively 3-block Home (spot cover photo header + "Good morning, <name>", filled plum Today box, guest rows with profile photos, plain rows that open /booking/[id], no check-in button since owners have no arrival step). Now picking a new tab bar (applies to whole owner app; port to tourist per parity). Mockup page https://claude.ai/artifact/BV9xAr94sejCXBBzM5KzYH, top = finalists 6 Light drop, 7 Lamp, 8 Bubble, 9 Wave (bar bends around bubble, from TikTok @settigation "Navigation Tabs V2"). User wants white bar, only pressed/hovered tab coloured. DECIDED 2026-11-23: tab bar = 8 · Bubble (white floating rounded bar with shadow, 4 tabs Home/Bookings/My Spot/Profile, lucide icons; active icon pops up into a 48px plum circle above the bar with white ring, bounces when sliding; active label plum; others grey; red badge on Bookings). Screens need bottom padding so the raised bubble never covers the last item ("See all" overlapped in mockup). Later wave/line/expanding experiments are DISCARDED. Build order: owner Home (lively) + bubble tab bar, then port tab bar to tourist app.
RESUME POINT (end 2026-11-23): bubble tab bar BUILT + pushed in ipilgo-owner cc43104 (src/components/BubbleTabBar.tsx, wired in src/app/(tabs)/_layout.tsx; tsc clean; not phone-tested). User APPROVED final Home plan, mockup + recap: https://claude.ai/artifact/7hY1tG3SCk5ov3VjAWGjW9. NEXT SESSION: (1) check owner app has Profile > Payments and My Spot > Insights (where money / views-saves-AI picks move); (2) rewrite src/app/(tabs)/dashboard.tsx (~490 lines) to: cover photo header with time-of-day greeting + spot name + Live, plum Today box (N bookings · M guests / quiet day + next date), today's guests equal rows (avatar, name, "N people · service", opens /booking/[id], max 5 + See all), quiet-day illustration; move 7-day strip to Bookings tab; (3) port BubbleTabBar to ipilgo-tourist (parity); commit each, user tests whole batch at end.

**How to apply:** max ~3 blocks on Home; plain wording; no stats/AI/weather/money clutter unless asked. Related: [[neat-organized-ui]], [[ui-redesign-direction]].
