-- =============================================================================
-- Migration 006 — Product Catalog foundation
--
-- Builds the server-side foundation for the Product Catalog domain using the
-- normalized tables already present in the base schema.
--
-- Scope:
-- - Add `brand` to products
-- - Add reusable tenant helper functions
-- - Enable RLS for categories / products / product_images / inventory
-- - Create tenant-safe storage bucket + policies for product images
-- =============================================================================

alter table public.products
  add column if not exists brand text;

alter table public.products
  add constraint products_brand_not_blank
    check (brand is null or length(trim(brand)) > 0);

create index if not exists products_company_updated_at_idx
  on public.products (company_id, updated_at desc)
  where deleted_at is null;

create index if not exists products_company_brand_idx
  on public.products (company_id, brand)
  where brand is not null and deleted_at is null;

-- ---------------------------------------------------------------------------
-- Reusable tenant helpers
-- ---------------------------------------------------------------------------

create or replace function public.current_employee_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select e.id
  from public.employees e
  where e.user_id = auth.uid()
    and e.deleted_at is null
  limit 1
$$;

create or replace function public.current_company_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select e.company_id
  from public.employees e
  where e.user_id = auth.uid()
    and e.deleted_at is null
  limit 1
$$;

create or replace function public.current_branch_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select e.branch_id
  from public.employees e
  where e.user_id = auth.uid()
    and e.deleted_at is null
  limit 1
$$;

revoke all on function public.current_employee_id() from public;
revoke all on function public.current_company_id() from public;
revoke all on function public.current_branch_id() from public;
grant execute on function public.current_employee_id() to authenticated;
grant execute on function public.current_company_id() to authenticated;
grant execute on function public.current_branch_id() to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.inventory enable row level security;

create policy "categories_select_own_company"
  on public.categories
  for select
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null);

create policy "categories_insert_own_company"
  on public.categories
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
    and updated_by = public.current_employee_id()
  );

create policy "categories_update_own_company"
  on public.categories
  for update
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null)
  with check (
    company_id = public.current_company_id()
    and updated_by = public.current_employee_id()
  );

create policy "products_select_own_company"
  on public.products
  for select
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null);

create policy "products_insert_own_company"
  on public.products
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
    and updated_by = public.current_employee_id()
  );

create policy "products_update_own_company"
  on public.products
  for update
  to authenticated
  using (company_id = public.current_company_id() and deleted_at is null)
  with check (
    company_id = public.current_company_id()
    and updated_by = public.current_employee_id()
  );

create policy "product_images_select_own_company"
  on public.product_images
  for select
  to authenticated
  using (company_id = public.current_company_id());

create policy "product_images_insert_own_company"
  on public.product_images
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
    and updated_by = public.current_employee_id()
  );

create policy "product_images_update_own_company"
  on public.product_images
  for update
  to authenticated
  using (company_id = public.current_company_id())
  with check (
    company_id = public.current_company_id()
    and updated_by = public.current_employee_id()
  );

create policy "product_images_delete_own_company"
  on public.product_images
  for delete
  to authenticated
  using (company_id = public.current_company_id());

create policy "inventory_select_own_company"
  on public.inventory
  for select
  to authenticated
  using (company_id = public.current_company_id());

create policy "inventory_insert_own_company"
  on public.inventory
  for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and created_by = public.current_employee_id()
    and updated_by = public.current_employee_id()
  );

create policy "inventory_update_own_company"
  on public.inventory
  for update
  to authenticated
  using (company_id = public.current_company_id())
  with check (
    company_id = public.current_company_id()
    and updated_by = public.current_employee_id()
  );

-- ---------------------------------------------------------------------------
-- Supabase Storage bucket + policies
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "product_images_storage_select_own_company"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );

create policy "product_images_storage_insert_own_company"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );

create policy "product_images_storage_update_own_company"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  )
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );

create policy "product_images_storage_delete_own_company"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );
