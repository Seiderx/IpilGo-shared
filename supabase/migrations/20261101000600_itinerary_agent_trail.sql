-- Itinerary agent trail: the "How this plan was made" section on a trip.
-- When the planner builds an itinerary it consults several agents (profile,
-- weather, events, safety, traffic, budget, culinary, accommodation,
-- itinerary). Each agent's one-line decision is stored with the trip so the
-- tourist (and the thesis panel) can see why the plan looks the way it does.
--
-- Shape: [{ "agent": "weather", "status": "ok", "summary": "..." }, ...]
-- Null for plans made before this column existed or built by hand.

alter table public.itineraries
  add column if not exists agent_trail jsonb;
