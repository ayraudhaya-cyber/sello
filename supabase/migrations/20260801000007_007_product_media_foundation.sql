-- Product media foundation notes
-- UI limit: 3 images (MediaConstants.kMaxProductImages)
-- Schema already gallery-oriented: product_images(sort_order, is_primary)
-- Storage paths: product-images/<company>/<product>/primary.(webp|jpg)
--                product-images/<company>/<product>/image-2.(webp|jpg)
--                product-images/<company>/<product>/image-3.(webp|jpg)
-- No schema change required for Milestone 4.2.

comment on table public.product_images is
  'Product gallery assets. UI may limit count; schema stays unbounded for future scale.';
