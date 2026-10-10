# IpilGo — Scope Decisions & Feature Backlog

Agreed 2026-10-10. This is the source of truth for what each app does and does not do.
Update this file when a decision changes, so it never needs to be re-discussed.

---

## Scope rule (most important)

IpilGo **showcases** places in Ipil and **books tour guides only**.

- Hotels: no room booking, no room inventory.
- Restaurants: no ordering, no menu/stock management.
- Each destination has an **"offers guided tours"** flag. The **Book** button shows only when it is on.
- The accommodation and culinary agents **recommend with a justification**. They do not book.
  (Panel requirement = recommendation + "why this was suggested", not transactions.)

| Place type | Tourist app shows |
|---|---|
| Spot with guides | Info, photos, map, route, weather + **booking** (date, guide, GCash/Maya) |
| Spot without guides | Info, photos, map, route, weather. No Book button |
| Hotel | Info, photos, "Rooms from PHP X", contact, link to own FB page / booking site |
| Restaurant | Info, photos, featured dishes (photos only), price range, hours |

Places with no owner (plaza, church, public beach) are managed by the **admin**.

---

## Tourist app — backlog (in build order)

1. **Password rules**: min 8 characters, must contain letters and numbers, block common passwords
   (e.g. `12345678`, `password1`), strength meter while typing. Enforced in Supabase Auth
   settings too, not only in the app. Existing weak passwords keep working until changed.
2. **Change password**: Profile -> Change password -> 6-digit code sent to the account's email ->
   enter code -> form (new password + confirm, same rules as #1) -> save -> sign out all other
   devices. Old password stops working. Hidden for Google/Facebook accounts (they have no password).
3. **Fix misleading AI search**: when nothing matches well, say "<query> isn't listed in IpilGo yet".
   Show other places only under a clear "You might also like" label and only if actually related.
   Add **"Search on Google Maps"** button (opens Maps app, free, no API key).
   Optional: **"Suggest this place"** -> note sent to admin.
4. **Booking only for guided spots**: add the "offers guided tours" flag; hide Book button otherwise.
5. **Change avatar**: upload photo to Supabase Storage, compressed before upload.
6. **Username instead of full name** at signup: unique, 3-20 characters, letters/numbers/underscore.
   Guides identify tourists by the contact name/number entered on the booking form.

**Dropped:** change email (account-takeover risk, not needed for thesis).

---

## Owner app — features (every owner, any place type)

Purpose: keep listing information fresh, because the AI agents are only as good as the data.

| Feature | Feeds which agent |
|---|---|
| Edit listing: photos, description, hours, price range, contact, links | Recommendation, accommodation, culinary |
| Mark **"Closed today"** with reason (repairs, weather, private event) | Safety, weather, itinerary |
| Post **events / promos** with dates | Event monitoring |
| Read and **reply to reviews** | Feedback |
| Stats: views, saves, times recommended | — (owner value) |

Account features shared with the tourist app (same behavior, built once, reused):
- Password rules (Supabase Auth setting applies to all three apps automatically).
- Change password via email code; hidden for Google/Facebook accounts.
- Avatar / business logo upload.
- **Keeps real full name + business name** (not username): admin approves owners, so identity must be checkable.
- Change email: dropped, same as tourist.

Owners of **guided spots** additionally: manage guides, accept/decline bookings
(existing Requests and History tabs).

Hotel owners: set "rooms from PHP X" and a booking link. No room management.
Restaurant owners: featured dishes as photos with price. No ordering.

---

## Open questions

- **Who employs the tour guides?** User believes they are government (LGU / tourism office)
  employees — **to confirm**. If true, guide booking may belong to the tourism office (admin side)
  rather than to spot owners, which changes who accepts bookings. Do not change booking ownership
  until confirmed.
