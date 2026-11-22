---
name: test-at-end
description: "User tests the whole backlog at once after all builds are done, not item by item; publish APKs once per batch"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 6440da40-2e5d-4ccc-8b22-d69cd8320404
  modified: 2026-10-10T16:31:08.779Z
---

User wants to test everything together after the whole backlog is built, not after each item (stated 2026-10-11).

**Why:** avoids repeated APK rebuilds/installs and repeated "update available" prompts for testers.
**How to apply:** keep building through the backlog in [[scope-decisions]] without pausing for per-item phone testing; typecheck/build each item and commit. At the end, give one combined test checklist plus the release steps (version bump + version.json on the download site, see [[local-apk-builds]]).
