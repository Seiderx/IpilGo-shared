---
name: admin-audit-2026-11-06
description: Strict admin panel test 2026-11-06 - findings, untested list, awaiting user decisions; nothing fixed yet
metadata:
  type: project
---

Admin colours changed to logo palette (admin b00688a, live). User then asked for strict admin test, DISCUSS BEFORE FIXING. Test ran on live site with writes blocked: no data changed.

Findings: no navigation under 1100px (sidebar hidden, no menu); Dashboard + Analytics overflow 354px at 390px; login overflows on phone; registration raw 'Failed to fetch' offline (also forgot password, and admin saves show 'TypeError: Failed to fetch'); blank/one-char full name accepted on register and on Profile; Reports inverted dates = silent no download; Esc doesn't close modals/bell; Owners defaults to Pending so looks empty; sidebar badges only owners/admins; inconsistent page titles; Google button shown but disabled; keyboard + label gaps; one approved admin only; tourist CSV has duplicate Name/Full name.

Passed: login errors, register duplicate/disposable/bad-domain errors, logout + back, route guards, money reconciles (P800 in, P200 refunded, P600 net), self-promotion blocked.

Not tested live: real approve/decline/block/reject/refund/delete/save, real register code flow, dark mode screens, PDF look.

User said font (Geist) looks AI and design bland; options to be chosen. GitHub admin repo renamed to Seiderx/IpilGo-Admin; local remote update needs user OK (classifier blocked it). Do not store the admin password in memory; user should change it after testing.

Related: [[final-test-pass]], [[ui-redesign-direction]]

DESIGN APPROVED by user 2026-11-06: Option A in design-refs/admin-design-options.html = top menu with dropdowns (Home, Approvals, Monitoring, Content, Records), sea teal #0F4C5C, photo banner on Dashboard only with wave edge, page background #EDF5F5, blue/red/gold stripe, Fraunces + DM Sans. Login/register = split photo layout in design-refs/admin-modern-preview.html (user loved it). Bookings stays as Monitoring page. User sets up Google sign-in themselves.
Real action test passed (reject/approve listing, suspend/reinstate owner, block/unblock tourist); state restored. New finding: reinstate message says owner must resubmit but admin can approve directly; listing stays hidden after reinstate.
Build order when user says go: 1 phone layout + top menu; 2 error messages + form checks; 3 login + Dashboard + other pages; 4 other fixes + full retest. Not started. Still untested: refunds/cancel, real signup code, dark mode, PDF look.
Build progress: step 1 DONE 2026-11-06 (top menu, phone drawer, table cards, palette, fonts). Next step 2 error messages + form checks, then step 3 login + Dashboard + pages, step 4 other fixes + retest. Auto-proceed between steps unless deploy input needed.
Step 2 DONE 2026-11-06 (errors.ts friendlyError/nameError, Toast maps errors, Modal Esc, Reports guard, Owners default All). Next step 3: login split-photo layout + Dashboard banner/wave/Needs you today cards + inner page look. Step 4: keyboard access, reinstate wording, reviews badge, tourist CSV duplicate column, retest incl. refunds, real signup, dark mode, PDF.
Step 3 login + Dashboard DONE 2026-11-06. User wants uniform icons (one line style, no coloured tiles) and data shown as lists with columns and photos, not sentences; apply same to other pages' stat cards. Obelisk photo is from Google, user told it needs permission or credit; user chose to keep for now. Remaining: other pages' cards, step 4 items.
2026-11-06 user wants Bookings page + Revenue removed from admin (owners are independent); confirmed rule: suspend cancels upcoming bookings, unpaid just cancel, paid refund + notice. Migration 20261106000000 applied + tested in rollback. Pending user yes: replace revenue with visitor totals, then remove Bookings page, revenue, Booking/Revenue reports, Analytics Bookings/Payments tabs. All PayMongo payments go to one account: no owner payout exists, tell panel as future work.
2026-11-06 Bookings page, revenue, Booking/Revenue reports, Analytics Bookings/Payments tabs REMOVED; visitors (guests of confirmed+completed trips) replace them; lib/visitors.ts. Cards + pills on all pages, Reviews count. Left: label/input linking, real signup test, real refund send test, PDF look, admin password change, GitHub remote rename. Tourist/owner apps may still mention admin bookings: unchecked.
2026-11-06 polish done: titles match menu, reinstate prompt, StatCard main prop per page. Next project = redesign ipilgo-apps (download website: index, privacy, data-deletion). User chose that meaning. Still on user: demo data, Google sign-in, admin password, photo permission, real signup + refund tests.
2026-11-06 ipilgo-apps website redesign pushed (mix design, Tara na sa Ipil, light only, dark mode dropped). Admin extras done (63be225). Ken Barnido pending admin request awaits user decision.
