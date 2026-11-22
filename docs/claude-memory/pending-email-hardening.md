---
name: pending-email-hardening
description: "Agreed 5-step build plan (2026-10-05) — steps 1-4 DONE (email guard, OAuth code, signing keys, download site + v1.0.0 release); next: step 5 user setup guide"
metadata:
  node_type: memory
  type: project
  originSessionId: d1951be1-716a-445b-b352-b822eddba9d7
  modified: 2026-10-04T17:53:07.188Z
---

Classmate signed up as me@gmail.com; the OTP bounce landed in the user's personal Gmail (used as Supabase SMTP sender). User declined SMS (no budget).

Agreed build order (user approved 2026-10-05):
1. DONE (root commit 325bb79): `hook_before_user_created` Postgres hook (disposable list + DNS-over-HTTPS MX/A check, OAuth skips) + hourly pg_cron `purge_unverified_users`. User enabled the hook in Dashboard. me@gmail.com + resianbande deleted with user's OK.
2. DONE: Google + Facebook login (tourist c60de55, owner 2632aab, admin a844b88; root 3606be9 RPCs complete_oauth_signup / discard_unused_oauth_account). Buttons inert until user configures providers + redirect URLs (ipilgotourist://**, ipilgoowner://**, admin /auth/callback).
3. DONE: release keystores in <app>/credentials/ (gitignored) via plugins/withReleaseSigning (tourist 425cab9, owner 930efae). User must back up credentials/ folders; phones with old debug-signed APK must uninstall once.
4. DONE: site live at https://ipilgo-apps.onrender.com (repo Seiderx/ipilgo-apps, Render static site). Release v1.0.0 published with IpilGo-Tourist.apk / IpilGo-Owner.apk (latest/download links verified). Local APK staging: THESIS_IPILGO/release-files (gitignored). Update prompt reads raw.githubusercontent.com/Seiderx/ipilgo-apps/main/version.json. Contact email on legal pages: user's personal Gmail (user's choice, 'for now'). Tourist route screen falls back to 'Open in Google Maps' when no EXPO_PUBLIC_GOOGLE_MAPS_API_KEY (user has no Maps key/billing yet); app.config.js injects key when present.
5. One step-by-step guide for user: dedicated sender Gmail + app password into Supabase SMTP (chosen over Brevo), Google Cloud OAuth client, Meta app (privacy/data-deletion URLs on the site), Supabase redirect URLs, admin Render rewrite /* -> /index.html, optional Maps key + billing, release procedure.

**Why:** Play Store blocked by 12-tester/14-day rule for new accounts; instructor wants downloadable link.
**How to apply:** Continue from the first not-DONE step. Supabase apply_migration needed user's explicit go-ahead (auto-mode classifier blocks it otherwise). See [[nested-git-repos]], [[local-apk-builds]].
