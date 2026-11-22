---
name: supabase-mcp-destructive-decline
description: "Supabase MCP apply_migration returns \"declined\" for SQL with drop/mass update even though the tool is allowed; avoid those statements"
metadata:
  node_type: memory
  type: reference
  originSessionId: 134c205b-90ca-4dd2-a2ba-2034039db0e5
  modified: 2026-10-29T12:46:30.644Z
---

In this VS Code setup, `mcp__claude_ai_Supabase__apply_migration` returned `{"status":"declined"}` twice for a migration containing `drop trigger if exists` and a table-wide `update`, even though the tool is in the project allow rules. The same migration applied fine once `drop trigger` became `create or replace trigger` and the backfill `update` was removed (2026-10-29).

**How to apply:** write migrations without DROP / mass UPDATE where possible (`create or replace trigger`, check if backfill is even needed first). If one is truly needed, split it out and tell the user it may need to be run from the Supabase SQL Editor.
