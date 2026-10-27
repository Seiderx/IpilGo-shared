-- Bookings made before the services rework with a ₱0 total were left as
-- 'unpaid', so a free booking read "Unpaid". They have nothing to pay.
update public.bookings
   set payment_status = 'not_required'
 where total_amount = 0
   and payment_status = 'unpaid';
