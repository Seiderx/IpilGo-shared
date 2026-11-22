---
name: nested-git-repos
description: "IpilGo is four separate git repos — root (migrations) plus ipilgo-tourist, ipilgo-owner, ipilgo-admin each with their own GitHub remote; commit/push each separately"
metadata: 
  node_type: memory
  type: project
  originSessionId: 25366b57-3ace-4bca-89ec-3e19d4b29570
  modified: 2026-09-16T18:52:32.369Z
---

Root `C:\Projects\THESIS_IPILGO` repo tracks only `supabase/migrations/` and root docs. The three apps are nested standalone repos, NOT submodules, each with its own remote:
- `ipilgo-tourist` → github.com/Seiderx/IpilGo-Tourist-app
- `ipilgo-owner` → github.com/Seiderx/IpilGo-Owner-app
- `ipilgo-admin` → github.com/Seiderx/IpilGo-Admin-app

**Why:** `git status` at root shows nothing for app changes, so edits look uncommitted-but-invisible.
**How to apply:** after a change, `cd` into each touched app and commit+push there; commit migrations at root. One feature = up to 4 commits.
