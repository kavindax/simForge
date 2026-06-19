-- Fix existing user simulations so share links work in incognito (anonymous access)
-- Run once if shared links only work when you are signed in

UPDATE public.simulations
SET is_public = true
WHERE author_id IS NOT NULL
  AND is_preset = false
  AND (is_public IS NULL OR is_public = false);
