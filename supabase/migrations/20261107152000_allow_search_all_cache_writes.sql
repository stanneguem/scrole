-- search_all_internal maintains search_result_cache (INSERT/UPDATE/DELETE).
-- The public wrapper must therefore be VOLATILE, not STABLE, so PostgREST
-- executes it in a writable transaction while retaining the event visibility filter.
alter function public.search_all(text) volatile;