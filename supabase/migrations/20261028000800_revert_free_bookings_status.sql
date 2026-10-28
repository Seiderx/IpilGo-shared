-- Reverts 20261028000500 for now. The owner app and tourist app already on
-- phones (v1.1.1) look up a label per payment status and crash on statuses
-- they don't know, so the old ₱0 bookings go back to 'unpaid' until v1.2.0 of
-- both apps (which know 'not_required') is released. Re-apply 0500 then.
update public.bookings
   set payment_status = 'unpaid'
 where total_amount = 0
   and payment_status = 'not_required'
   and created_at < '2026-10-28';
