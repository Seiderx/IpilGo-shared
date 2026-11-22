---
name: owner-debug-session
description: Upcoming phone debugging session (user connects phone ~1am 2026-10-31 via adb); no APK release until done; open owner-app gaps list
metadata:
  type: project
---

2026-10-30: user will NOT release APKs yet; plans "intense debugging" with phone connected to me (adb at %LOCALAPPDATA%/Android/Sdk/platform-tools/adb). Fixed already: owner full-name live validation + Forgot-password row (owner 00285d7, tourist 29c2863).

2026-10-31 FIXED: text rules for spot/service/event names + descriptions, tidyTitle on save (owner 00c6ad9); friendly offline errors on all auth screens (owner 00c6ad9, tourist a69dc64, tourist helper src/lib/errors.ts). Server full_name check written as supabase/migrations/20261031000000_owner_full_name_check.sql APPLIED + committed 2026-10-31 after user OK.

Original gaps: listing/service/event text fields have no rules (spot name "front yard" lowercase); some screens (apply-owner, spot/basic, password flows) lack try/catch for network failures; server doesn't enforce full_name; old "11111" owner account (pre-rules, Oct 10) + "front yard" listing = user's call.

**Why:** user wants owner app hardened before next release batch.
**How to apply:** at debug session, screenshot sparingly (costly); audit code first, use phone to confirm. Related: [[itinerary-draft-batch]], [[test-at-end]], [[cross-app-parity]].
