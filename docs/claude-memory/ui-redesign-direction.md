---
name: ui-redesign-direction
description: "User wants all 3 apps to stop looking AI-built — \"quiet premium\" minimal style (Linear/Vercel/Stripe/Apple/Airbnb) with uniform icons; design phase planned before admin portal"
metadata:
  node_type: memory
  type: project
  originSessionId: 134c205b-90ca-4dd2-a2ba-2034039db0e5
  modified: 2026-10-29T13:54:12.029Z
---

2026-10-29: user said the UI looks obviously AI-built and wants a premium-yet-simple look like the trending sites (Linear, Vercel, Stripe, Apple, Airbnb). Explicit requirement: **icons must be uniform** (one icon set, one stroke weight, one size scale, single color — no filled/outline mixing, no icons in tinted circles).

Current AI tells to remove: blue gradient header on every screen, white rounded cards with soft shadow everywhere, icons in pale tinted squares, 4-tile stat grids, pills on everything.

Target traits: lots of whitespace, restrained palette (neutrals + one accent), typography-led hierarchy, hairline 1px borders instead of shadows, big place photos as hero, small uppercase labels, thin monochrome line icons, subtle motion, bento layouts.

**Why:** thesis panel/public perception; user wants it to look designed, not generated.
**How to apply:** proposed order (pending user confirmation): design phase first (mockups → shared design tokens + one icon set → tourist restyle → owner restyle), then build the admin portal directly in the new look. See [[owner-v120-build-plan]] for the admin items. Follow [[cross-app-parity]] — the design system must be identical across apps.
