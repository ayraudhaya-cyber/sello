-- =============================================================================
-- Migration 032 — Schedule route / area planning seam
--
-- Adds optional area coverage on planned stops so Hub can plan
-- "Ravi covers Colombo" without a full territory-management system.
-- Operational customer_visits remain unchanged.
-- =============================================================================

alter table public.scheduled_visits
  add column if not exists area text;

alter table public.scheduled_visits
  drop constraint if exists scheduled_visits_area_not_blank;

alter table public.scheduled_visits
  add constraint scheduled_visits_area_not_blank
    check (area is null or length(trim(area)) > 0);

create index if not exists scheduled_visits_company_area_date_idx
  on public.scheduled_visits (company_id, area, visit_date)
  where deleted_at is null and area is not null;

comment on column public.scheduled_visits.area is
  'Optional coverage area / locality for the stop (e.g. Colombo). '
  'Free-text seam until formal territories exist. Not a second visit system.';
