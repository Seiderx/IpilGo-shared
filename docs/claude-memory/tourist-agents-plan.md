---
name: tourist-agents-plan
description: "Agreed 2026-11-01 plan for tourist app (planner uses all agents, visible agent trail, weather on Home, picks vs fill) — do in a later session after admin polish; then final 3-portal test pass"
metadata:
  node_type: memory
  type: project
  originSessionId: 83ceb107-7156-41ab-b5fd-fcbe1e413c43
  modified: 2026-10-31T18:47:25.668Z
---

User agreed 2026-11-01 to ALL these tourist-app changes, to be done in a separate session AFTER admin polishing is finished:

1. Home "Itinerary" card is a duplicate shortcut to Trips → Itineraries. Change to "Plan a new trip" opening /itinerary/new directly; Trips stays for saved trips.
2. Planner picks: currently targets 2 visits/day (VISITS_PER_DAY in itineraryAgent.ts) and silently fills with suggestions — user found it confusing. New flow: "Plan it for me" (no picks, AI from interests) / "Only my picks" (no additions) / mix with toggle "Fill free time with places I'd like". Each suggested stop shows why ("because you like beaches") + one-tap remove.
3. Agents: all 12 exist in src/lib/ai/agents + orchestrator, but itinerary/new.tsx only runs profile, traffic, itinerary. Make planner consult weather (rain → reorder), events (festivals on dates), safety (skip closed), budget (trip total), culinary (meals). Add "How this plan was made" section listing each agent's one-line decision. Show Ipil weather on Home and per itinerary day. User considers #3 most important for the panel.

After EVERYTHING is finished: final intense pass — Claude navigates all three portals (tourist, owner, admin) testing everything to find flaws. This is the very last step; takes long.

**Why:** thesis panel demands visible multi-agent system; user wants it understandable. **How to apply:** don't start until admin polish done; explain in plain language. Related: [[phone-test-session]], [[cross-app-parity]].

STATUS 2026-11-01: items 1-3 BUILT (tourist 60f0fa8, root migration 65b3e9b agent_trail applied). Planner: mode auto/picks + fill toggle (default off); weather/events/safety/traffic feed itinerary prompt; reviewTrip() = budget/culinary/accommodation; trail saved + 'How this plan was made' on [id]; per-day weather; Home weather + 'Plan a new trip'. NOT phone-tested (needs next APK). Next: v1.4.1 release, then final 3-portal pass.
