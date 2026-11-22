---
name: cross-app-parity
description: "Any fix in tourist or owner app that touches shared logic (auth, validation, payments, statuses, update prompt) must be applied to the other app too"
metadata:
  node_type: memory
  type: feedback
  originSessionId: ac69e31b-59c5-4c54-b439-a3ff1f6eeb3b
  modified: 2026-10-29T11:46:11.741Z
---

When a fix lands in one app (tourist or owner) and the same logic exists in the other app — signup/login/verify/password, username rules, phone validation, booking/payment status labels, update prompt, OAuth, shared DB contracts — apply the same fix to the other app in the same batch, or list it explicitly as pending for that app's next release. Also check the admin portal when the fix touches shared data (statuses, destination fields).

**Why:** user saw that the tourist auth fixes (commit a124b16) never reached the owner app, and one account is both tourist and owner, so mismatched logic breaks the same user in one app. Stated 2026-10-29.

**How to apply:** after any fix, ask "does the other app have this code path?" (grep the sibling repo) and port it; mention in the end-of-session summary which app got which fix. Related: [[owner-v120-build-plan]], [[nested-git-repos]].
