---
name: hosting-domain-plan
description: "Render-only hosting for ipilgo-apps + admin (both Static, free tier, same Render project); plan = one custom domain, admin on subdomain"
metadata:
  node_type: memory
  type: project
  originSessionId: d676f890-295f-441d-a21e-d8140bfd9cce
  modified: 2026-10-30T12:42:11.206Z
---

2026-10-30: User wants ONE hosting platform (Render) to cut costs. Both sites are Render Static Sites (free, no sleep), now both in Render project "My project": ipilgo-apps (ipilgo-apps.onrender.com) and admin (ipilgo-admin-onrender-com.onrender.com).

Plan: buy ONE domain only (user leaning Hostinger, domain only, no hosting plan). Root + www -> ipilgo-apps, `admin.<domain>` -> admin. Then: Supabase Auth redirect URL for admin domain, update privacy/data-deletion URLs in Meta + Google consent, Google Search Console for ipilgo-apps.

Code to do once domain chosen: `noindex` on admin, sitemap.xml + robots.txt on ipilgo-apps. Apps' update check reads raw GitHub version.json, so domain change doesn't affect it.

**Why:** user wants sites reachable by typed address and findable on Google without paying for hosting.
**How to apply:** don't suggest Vercel/Netlify; next step is user buying the domain. Related: [[redesign-build-plan]], [[pending-email-hardening]].
