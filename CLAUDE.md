# IpilGo — Claude Code Project Instructions

This file is read automatically by Claude Code at the start of every session in this project. 
Follow these rules without needing to be asked each time.

---

## Git & Commit Workflow (follow automatically, do not wait to be asked)

1. **Commit proactively, without asking permission first.** Whenever you finish a meaningful, 
   working chunk of work — a screen that renders and functions, a working API integration, a 
   completed build phase from the build plan — commit it immediately as part of finishing that 
   task. Do not wait for me to say "commit this." Do not ask "should I commit now?" — just do it 
   and tell me afterward what you committed.

2. **What counts as "a good point to commit"** (use your judgment, but these are the signals):
   - The code runs without errors
   - The feature/screen does what it was supposed to do, even if not 100% polished
   - You're about to start a different, unrelated piece of work
   - You've just finished one of the numbered phases from the build plan document
   
   You do NOT need to wait for a feature to be 100% finished/polished — commit working, 
   incremental progress. A rough-but-working booking screen committed now is more valuable than 
   a polished one that only exists uncommitted on disk.

3. **Commit message format** — use clear, descriptive messages, not generic ones:
   - Good: `"Phase 1: tourist auth, login/signup, and destination browsing screens working"`
   - Good: `"Fix: booking status wasn't updating in real-time, added Supabase Realtime subscription"`
   - Bad: `"update"`, `"fix stuff"`, `"changes"`

4. **Push to GitHub after committing**, not just committing locally, so the work is backed up 
   remotely — unless I've told you I'm working offline for that session.

5. **Do NOT commit broken code.** If something doesn't run or has an obvious error, fix it first, 
   then commit. If you genuinely can't get something working and need to stop, tell me clearly 
   what's broken before committing — don't silently commit broken code and move on.

6. **One thing to still ask me about, always:** never force-push, never rewrite git history, 
   never delete a branch, and never run any destructive git command (reset --hard on shared work, 
   git clean, etc.) without explicitly telling me first and getting confirmation. Routine commits 
   don't need permission; anything that could destroy work does.

7. **At the end of each session**, give me a short summary of what got committed during that 
   session, so I have a running record of progress without needing to check git history myself.

---

## Project Context (so you don't need this re-explained each session)

- **IpilGo** — AI-powered tourist assistance app for Ipil, Zamboanga Sibugay (BSCS thesis project)
- **Three separate systems**, built in this priority order: Tourist app (priority 1) → Destination 
  Owner app (priority 2) → Admin panel (priority 3)
- **Tourist app + Owner app:** React Native + Expo (TypeScript) — must be Play Store-deployable
- **Admin panel:** React + Vite (TypeScript) — web-only, deployed via Vercel/Netlify
- **Backend:** Supabase (already connected via MCP) — Auth, Database, Storage, Realtime
- **AI reasoning:** Gemini API, specifically `gemini-3.5-flash` (free tier) for now — all agent 
  calls must go through one shared wrapper function so migrating to Claude API later is a 
  one-file change, not a rebuild
- **Maps/routing:** Leaflet in a WebView with OpenStreetMap data (CARTO tiles), OpenRouteService for routes through the external-api edge function; no live traffic, estimates by time of day
- **Weather:** OpenWeatherMap (One Call API 3.0)
- **Payment:** PayMongo (test/sandbox mode) — GCash and Maya as payment methods
- Full build plan and phase-by-phase prompts are in `IpilGo_Build_Plan_and_ClaudeCode_Prompts.md`

## Panel Recommendations to Keep in Mind Throughout

The thesis panel specifically asked for a genuine **multi-agent AI system** (not a single chatbot) 
covering: profile, budget, itinerary, weather, traffic, accommodation, culinary, event monitoring, 
safety, translation, feedback, and recommendation agents — with each recommendation including a 
plain-language justification ("why this was suggested"). Also required: an Itinerary Planner, 
real-time map, route distance/time per vehicle type, and verifiable payment authenticity. Keep 
these requirements in mind when making architecture decisions, even in phases that don't 
explicitly mention them.

## Session Memory

Past-session notes are copied in `docs/claude-memory/` (index: `MEMORY.md`). Read the index at session start when running remotely. Test passwords are removed from the copy.
