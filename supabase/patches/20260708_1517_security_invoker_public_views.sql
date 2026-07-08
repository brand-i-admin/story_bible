-- Supabase Security Advisor: public read views must run with caller RLS.
-- `security_invoker = true` prevents these views from bypassing underlying
-- table policies as the view owner.

alter view if exists public.events_ordered
  set (security_invoker = true);

alter view if exists public.character_eras
  set (security_invoker = true);
