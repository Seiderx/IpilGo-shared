# IpilGo — Project Status & Handoff Checklist

Last updated: 2026-10-28. Current release: **v1.1.1** (tourist + owner APKs, versionCode 3).
Overall completion (estimate, not yet verified by testing): **about 88%** (fair range 80–90%).

Read this file first in a new session. Scope rules and the history of each decision are in
[IpilGo_Scope_Decisions.md](IpilGo_Scope_Decisions.md). Do not re-discuss decisions marked as agreed.

Legend: `[x]` done · `[ ]` not done · `[~]` code done but waits on a setup step or confirmation

---

## 1. Where everything lives

| Part | Folder | GitHub repo | Notes |
|---|---|---|---|
| Root (DB migrations + docs) | `THESIS_IPILGO/` | — | Tracks only `supabase/migrations/` and `docs/` |
| Tourist app | `ipilgo-tourist/` | Seiderx/IpilGo-Tourist-app | React Native + Expo (TypeScript) |
| Owner app | `ipilgo-owner/` | Seiderx/IpilGo-Owner-app | React Native + Expo (TypeScript) |
| Admin panel | `ipilgo-admin/` | Seiderx/IpilGo-Admin-app | React + Vite (TypeScript), web only |
| Download site | `ipilgo-apps/` | Seiderx/ipilgo-apps | Live: https://ipilgo-apps.onrender.com |
| APK staging | `release-files/vX.Y.Z/` | (gitignored) | One folder per version, each with IpilGo-Tourist.apk + IpilGo-Owner.apk |

- These are **separate git repos** (not submodules). A feature can need up to 4 commits: one per
  touched app plus one at root for migrations. Commit and push each repo separately.
- Supabase project id: `dbkqemjfxtksjxrwrclf`.
- AI model: `gemini-3.5-flash`, called only through `ipilgo-tourist/src/lib/ai/reasoningModel.ts`
  (one-file switch to Claude API later).

---

## 2. Thesis panel requirements

| Requirement | Status | Where |
|---|---|---|
| Multi-agent AI (not a single chatbot) | [x] | `ipilgo-tourist/src/lib/ai/orchestrator.ts` + `agents/` |
| Profile agent | [x] | `agents/profileAgent.ts` (onboarding profiling) |
| Budget agent | [x] | `agents/budgetAgent.ts` |
| Itinerary agent + Itinerary Planner screens | [x] | `agents/itineraryAgent.ts`, `app/itinerary/` |
| Weather agent (OpenWeatherMap) | [x] | `agents/weatherAgent.ts` |
| Traffic agent | [x] | `agents/trafficAgent.ts` |
| Accommodation agent (recommend only, no booking) | [x] | `agents/accommodationAgent.ts` |
| Culinary agent (recommend only, no ordering) | [x] | `agents/culinaryAgent.ts` |
| Event monitoring agent (uses owner events/promos) | [x] | `agents/eventAgent.ts` |
| Safety agent (uses "Closed today") | [x] | `agents/safetyAgent.ts` |
| Translation agent | [x] | `agents/translationAgent.ts` |
| Feedback agent (uses reviews) | [x] | `agents/feedbackAgent.ts` |
| Recommendation agent | [x] | Built into the orchestrator (no separate file). Verify this is fine for the panel |
| "Why this was suggested" justification on every recommendation | [x] | orchestrator/assistant. **Verify on screen during testing** |
| Real-time map | [~] | Works without a key by opening Google Maps. In-app map needs a Maps API key + billing |
| Route distance/time per vehicle type | [x] | `app/route/[destinationId].tsx`, `lib/routes.ts` |
| Verifiable payment authenticity | [x] | Only the PayMongo webhook (server side) can set "paid", client cannot fake it. PayMongo is in **test/sandbox** mode |

---

## 3. Done — by portal

### Tourist app (v1.1.1)
- [x] Sign up with **username** (unique, live availability check, strict rules), login, email verify by 6-digit code
- [x] Password rules: min 8, letters + numbers, common passwords blocked, strength meter
- [x] Forgot password and change password via 6-digit email code (hidden for Google/Facebook accounts)
- [~] Google + Facebook login (code done; buttons do nothing until providers are set up, see section 5)
- [x] Onboarding/profiling (no longer re-asks after a failed load)
- [x] Home, Explore, Favorites, Profile tabs; destination page with photos, 360°, info
- [x] Destination page: Closed today banner, hotel "rooms from", restaurant featured dishes, owner FB/website links, What's On (events/promos), reviews with owner replies
- [x] AI search: honest "isn't listed in IpilGo yet", "You might also like" only when related, "Search on Google Maps" button
- [x] Chat assistant: refuses non-Ipil topics, real address for "where is X", fast keyword routing, thinking indicator
- [x] **Book a Guide** only on spots with "offers guided tours"; others show Get Directions
- [x] Booking form asks contact name + mobile; saves mobile to profile if missing
- [x] PayMongo checkout (GCash / Maya), payment result screen, live booking status
- [x] Itinerary planner (create, view, list)
- [x] Route screen with distance/time per vehicle type
- [x] Avatar upload (pick, crop, compress)
- [x] Mobile number shown/editable on Profile
- [x] Live in-app notifications: pop-up on booking confirmed/declined, bell with unread badge
- [x] One view per tourist per day recorded for owner stats
- [x] Update prompt reads `version.json` from the download site; About row shows installed version

### Owner app (v1.1.1)
- [x] Register/login (keeps **real full name + business name**, letters-only name check), verify email, forgot/change password via code
- [x] Pending-approval screen; approval refreshes access instantly
- [x] **One account = tourist + owner**: tourist accounts see "Apply as Owner" instead of being signed out
- [x] Dashboard: Tourist Reach stats (views, saves, AI top-3 picks); booking tiles only for guided spots
- [x] Edit listing: type (spot/hotel/restaurant), category dropdown, photos, description, hours, contact, FB/website links, hotel rooms-from price, restaurant price range + featured dishes
- [x] "Offers guided tours" switch; "Closed today" + reason
- [x] Events & Promos screen
- [x] Reviews screen: read reviews, post/edit/delete public reply
- [x] Requests / History tabs (only for guided spots) with red pending-count badge; booking detail shows tourist contact
- [x] Business logo upload
- [x] Live notifications: pop-ups, bell with unread badge, notifications screen
- [x] Save message explains that editing core fields sends a live spot back to "pending" for admin review (kept on purpose)

### Admin panel
- [x] Login, register with email code, Sign in with Google (code done, needs provider setup), forgot/change password via code
- [x] Dashboard, Analytics, Reports
- [x] Destinations: create/edit (loads fresh row so owner edits are not overwritten), listing type, guided-tours checkbox, links, hotel price, 360° panorama file upload
- [x] Pending Owners and Pending Admins approval; Admin Status
- [x] Bookings and Tourists pages
- [x] Profile
- [ ] Not deployed to the web yet (Render/Vercel). Needs a rewrite rule `/* -> /index.html`

### Backend (Supabase) — all applied to the live database
- [x] Baseline schema, roles, admin approval, owner approval
- [x] Signup email guard: blocks disposable/undeliverable emails; hourly cleanup of unverified accounts (pg_cron)
- [x] OAuth signup support RPCs
- [x] Guided-tours flag, avatars bucket, usernames, booking contact fields
- [x] Listing details (type, closed today, links, prices, featured dishes)
- [x] Events kind, review owner replies (forgery-proof), destination views + owner stats
- [x] Spots that lose their owner go back to pending
- [x] `apply_as_owner` RPC (dual role)
- [x] Database-generated notifications (bookings, payments, spot approval, owner approval) + realtime
- [x] PayMongo `paymongo-checkout` and webhook edge functions are called by the app. **Verify in the new session that their source code is saved somewhere** (it was not found in these repos)

### Release / distribution
- [x] Release signing keys in each app's `credentials/` folder (gitignored) — **keep a backup copy**
- [x] Download site with landing page, privacy policy, data deletion page, `version.json`
- [x] GitHub releases: v1.0.0, v1.1.0 (pre-release), v1.1.1 (Latest)

---

## 4. Not done yet (to-do, in suggested order)

1. [ ] **Full test pass of v1.1.1** on all three portals (you test everything at once, then one fix batch)
2. [ ] **Phone push notifications** (Round 2 item 9). Needs your free Firebase project first
3. [ ] **Email to owner when approved** (Round 2 item 10). Needs the dedicated sender Gmail (step 5 below)
4. [ ] **Setup guide** (old plan step 5) — one step-by-step guide covering section 5
5. [ ] **Deploy admin panel** to the web
6. [ ] **Booking ownership** (old backlog item 13) — on hold until the tour guide question is answered (section 7)
7. [ ] **Old hidden duplicate "Front yard"** — currently hidden; merge or delete only with your explicit OK
8. [ ] Verify the panel items marked "verify" in section 2 (justification on every suggestion, recommendation agent)
9. [ ] Your own new fixes and additions

---

## 5. Setup steps only you can do (accounts, keys, passwords)

Never paste passwords or keys into the chat. Put them directly into the Supabase dashboard or `.env` files.

- [ ] Create a **dedicated sender Gmail** + app password; put it in Supabase Auth SMTP (chosen over Brevo). Currently your personal Gmail sends the codes
- [ ] Supabase "Magic Link" email template must include `{{ .Token }}` (needed for the 6-digit codes)
- [ ] **Google Cloud OAuth client** (Google login)
- [ ] **Meta app** (Facebook login) — use the privacy and data-deletion URLs from the download site
- [ ] Supabase redirect URLs: `ipilgotourist://**`, `ipilgoowner://**`, admin `/auth/callback`
- [ ] **Firebase project** (for push notifications)
- [ ] Optional: **Google Maps API key + billing** for the in-app map (`EXPO_PUBLIC_GOOGLE_MAPS_API_KEY`)
- [ ] PayMongo: stays in test mode for the thesis unless you decide otherwise

---

## 6. Decisions already made (do not re-discuss)

**Scope**
- IpilGo **showcases** places and **books tour guides only**.
- Hotels: no room booking. Restaurants: no ordering. Accommodation/culinary agents recommend with a reason, never book.
- Book button only on spots with "offers guided tours".
- Places with no owner (plaza, church, public beach) are managed by the admin.
- **Change email: dropped** (account-takeover risk, not needed for the thesis).

**Accounts**
- Tourists sign up with a **username**; owners keep **real full name + business name** (admin must check identity).
- One account can be both tourist and owner.
- Password rules and email-code password change/forgot apply to all three apps. Reset links were replaced by 6-digit codes; 10-minute code expiry; neutral wording "if this email has an account".
- SMS verification declined (no budget). Email guard used instead.

**Data behavior**
- Editing core fields of a live spot sends it back to "pending" for admin review (kept on purpose).
- A spot whose owner account is deleted goes back to pending for the admin to reassign or delete.

**Build & release**
- APKs are built **locally** with Android Studio's JBR (JDK 17), not EAS cloud builds or Expo Go:
  `JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"` then `npx expo run:android --variant release --no-bundler`.
  If it fails with a hermes/getAbsolutePath error: `npx expo prebuild --clean --platform android --no-install` first.
- Play Store is blocked for now (new-account 12-tester / 14-day rule), so apps are distributed through the download site + GitHub Releases.
- Release steps: bump version + versionCode in both apps → build APKs → put them in `release-files/vX.Y.Z/` → GitHub release → bump `version.json` in `ipilgo-apps` (you do this step yourself to learn it).
- Contact email on the legal pages is your personal Gmail "for now".

**How we work**
- Build the whole batch first, then you test everything at once; one release per batch.
- One migration per item, built and committed item by item.
- Additive DB migrations are pre-approved; destructive changes (delete/merge data) always need your OK.
- Commit and push automatically after each working piece (see `CLAUDE.md`).

---

## 7. Open questions

- **Who employs the tour guides?** You believe they are LGU / tourism office employees — to confirm.
  If yes, guide bookings may belong to the tourism office (admin side) instead of spot owners.
  Do not change booking ownership until this is confirmed.
- What to do with the old hidden duplicate "Front yard" (merge, delete, or leave hidden).

---

## 8. Loose ends in the working folders

- `ipilgo-owner`: `app.json` and `package.json` have uncommitted local changes (your prebuild script edits, left out of commits on purpose). Decide whether to keep them.
- `ipilgo-admin`: `tsconfig.tsbuildinfo` modified (build cache, safe to ignore or gitignore).
- Root folder has untracked files (prototype HTML, flowcharts, thesis .docx, screenshots). Not part of the code.

---

## 9. How to start the next session

Paste something like this:

> Read `docs/IpilGo_Project_Status.md` and `docs/IpilGo_Scope_Decisions.md` first.
> Then help me with: <your fixes and additions>.
