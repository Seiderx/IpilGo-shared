---
name: security-tools
description: "SkillSpector + graphify installed 2026-10-30 in ~/tools; how to run on Windows, graphify pinned via ~/bin shim"
metadata:
  node_type: memory
  type: reference
  originSessionId: 7669836c-e9a3-4945-9b24-773d53fb9abe
  modified: 2026-10-30T14:11:32.348Z
---

- **SkillSpector** (NVIDIA skill scanner): `~/tools/SkillSpector/.venv/Scripts/skillspector scan <dir> --no-llm --format json > out.json` (PYTHONIOENCODING=utf-8). `--output` unsupported on Windows. Slow (~4 min small plugin, ~90s for one skill); hits runtime limit on big dirs — scan only the installable skill files, never a whole repo (.git creates 29 noise findings). Verdicts are keyword-driven: graphify got DO_NOT_INSTALL but all HIGHs were false positives. Reports in ~/tools/reports.
- **graphify 0.9.97**: installed from scanned source (~/tools/graphify-src) into ~/tools/graphify-venv; `~/bin/graphify` python-shebang shim makes the skill find it, so it never pip-installs unpinned graphifyy from PyPI. Skill at ~/.claude/skills/graphify, registration in ~/.claude/CLAUDE.md. Project hooks (`graphify claude install`) NOT installed. To upgrade: git pull source, re-scan, re-pip-install.
- 2026-10-30 manual review: cloudflare/security-audit-skill = SAFE (markdown + 2 offline node validators, no network/exec). OmniRoute + freellmapi = not skills, LLM gateway servers; advised against (prompts/code to free third-party providers, OmniRoute has MITM/TLS-stealth/cookie/subscription-sharing features, freellmapi auto-pulls remote routing catalog). Installed to ~/.claude/skills/security-audit. Its CLI validators fail on Windows (no O_NOFOLLOW) — call exported validateDocument via wrapper instead. No sandbox here, so audits are source-only and max verdict is needs_validation.
- 2026-10-30 audit run-1 (quick, everything) at ~/security-audit-skill/ipilgo/run-1/REPORT.md: top leads = Gemini+OpenWeather keys in ipilgo-tourist/eas.json and APKs v1.0-1.4 (rotate); bookings table: direct INSERT bypasses create_booking, owner_id/tourist_id not locked on UPDATE, tourist can cancel completed booking -> refund. 4 deferred units (owner revocation, reviews, services/deposits, Realtime). No fixes applied yet.
- User's worry: skills leaking `.env` (Maps key). Full scan of all ~1000 installed skills not done (hours) — see [[redesign-build-plan]] for release state.
