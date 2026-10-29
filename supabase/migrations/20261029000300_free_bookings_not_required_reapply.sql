-- Re-applies 20261028000500 now that both v1.2.0 apps (tourist and owner) are
-- released and know the 'not_required' status (0800 had reverted it because
-- the v1.1.1 apps crashed on unknown payment statuses).
update public.bookings
   set payment_status = 'not_required'
 where total_amount = 0
   and payment_status = 'unpaid';
