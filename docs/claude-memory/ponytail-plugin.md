---
name: ponytail-plugin
description: Ponytail Claude Code plugin (lazy-senior-dev coding style) installed user-scope 2026-11-16; clone in ~/tools/ponytail
metadata:
  node_type: memory
  type: reference
  originSessionId: 7e3446e8-6366-409e-9f12-1a2816d1eec2
  modified: 2026-11-15T17:33:49.002Z
---

Ponytail v5.3.3 installed 2026-11-16 via `claude plugin marketplace add DietrichGebert/ponytail` + `claude plugin install ponytail@ponytail` (user scope). Review clone at ~/tools/ponytail.
SessionStart hook injects "PONYTAIL MODE ACTIVE — level: full"; mode flag ~/.claude/.ponytail-active. Commands: /ponytail lite|full|ultra|off, /ponytail-review, -audit, -debt, -gain, -help.
Runs alongside caveman: ponytail = code minimalism, caveman = prose style. Both turn off on "normal mode".
Band ledger writes local CSV to ~/.config/ponytail/band/; webhook unset (nothing leaves machine).
Related: [[security-tools]]
