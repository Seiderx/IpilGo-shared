---
name: itinerary-draft-batch
description: 2026-10-30 approved batch — itinerary Draft flow + AI adjust/error/travel-gap fixes + admin noindex; step status inside
metadata:
  node_type: memory
  type: project
  originSessionId: d676f890-295f-441d-a21e-d8140bfd9cce
  modified: 2026-10-30T14:05:26.948Z
---

User approved 2026-10-30 ("yes and with other fixes"). Tourist app batch, tested at end in one release ([[test-at-end]]):

1. DONE 2026-10-30 (tourist 82aab11, admin a8cbb42 pushed, root a787ec5; migration applied + verified). Draft flow: generated itinerary saved as draft (is_draft flag), shown on normal itinerary screen with "Draft" badge, bottom bar [Try again] [Save]. Drafts hidden from Trips list, old drafts auto-cleaned. Admin itinerary counts ignore drafts.
2. DONE Adjust agent: nonsense request ("yow") -> "didn't understand", no plan; unchanged plan -> "No changes needed".
3. DONE (tourist+root commits 2026-10-30) Friendly AI errors (busy / daily limit) instead of raw JSON; one auto-retry on 503.
4. DONE Enforce min travel gap between visits in code (warning "Only 0 min after X").
5. DONE Admin noindex (domain-independent part of [[hosting-domain-plan]]).

Not in batch: "front yard" test listing = user cleans data. Sitemap waits for domain.

**Why:** user wants review-before-save and fewer confusing AI failures.
**How to apply:** continue from first step not marked DONE; update this file as steps finish.
