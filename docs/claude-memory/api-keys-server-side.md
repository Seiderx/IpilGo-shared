---
name: api-keys-server-side
description: Gemini/OpenWeather/Maps-web keys moved to external-api edge function (code committed 2026-10-30); migration + deploy + secrets still pending
metadata:
  node_type: memory
  type: project
  originSessionId: d676f890-295f-441d-a21e-d8140bfd9cce
  modified: 2026-10-30T13:09:29.857Z
---

2026-10-30: user can't pay for Gemini billing yet; asked to "safekeep" keys first. Done in code: tourist aaf4877 (src/lib/externalApi.ts; reasoningModel, weatherAgent, trafficAgent, routes call edge fn), root f40aa8b (supabase/functions/external-api + migration 20261030000000_api_usage_limits.sql, daily per-user quotas).

DONE 2026-10-30: migration applied, external-api deployed v1, user added GEMINI_API_KEY + OPENWEATHER_API_KEY secrets in dashboard and removed them from ipilgo-tourist/.env. Not yet exercised by a real app build (verify on next tourist release). GOOGLE_MAPS_SERVER_KEY added later with Maps setup.

When billing is enabled later: create NEW Gemini key (old one is in released APKs), restrict native Maps key to Android package com.ipilgo.tourist + SHA-1.

**Why:** EXPO_PUBLIC_ keys are inlined into the APK; billing on a leaked key = charges on user's card.
**How to apply:** finish pending steps before next tourist release. Related: [[hosting-domain-plan]], [[local-apk-builds]].
