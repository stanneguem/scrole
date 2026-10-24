-- Align legacy photos-array constraint with the create_post RPC media budget.
-- The RPC validates the combined photos + videos count (maximum 20).
ALTER TABLE public.community_posts
  DROP CONSTRAINT IF EXISTS community_posts_max_photos;

ALTER TABLE public.community_posts
  ADD CONSTRAINT community_posts_max_photos
  CHECK (cardinality(photos) >= 0 AND cardinality(photos) <= 20);
