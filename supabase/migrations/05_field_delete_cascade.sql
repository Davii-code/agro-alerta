-- Deleting a field used to be impossible server-side.
-- samplings.field_id and risk_scores.field_id referenced public.fields with no
-- ON DELETE action, so Postgres defaults to NO ACTION: any field that had ever
-- been sampled rejected its own DELETE with 23503, and the app's delete button
-- only ever removed the local copy. The next refresh read the row back from the
-- server and the field reappeared.
--
-- Cascade is the right action here: a sampling or a risk score has no meaning
-- without the field it was taken on, and the app already drops both locally in
-- DatabaseService.deleteField.
ALTER TABLE public.samplings
    DROP CONSTRAINT IF EXISTS samplings_field_id_fkey;
ALTER TABLE public.samplings
    ADD CONSTRAINT samplings_field_id_fkey
    FOREIGN KEY (field_id) REFERENCES public.fields(id) ON DELETE CASCADE;

ALTER TABLE public.risk_scores
    DROP CONSTRAINT IF EXISTS risk_scores_field_id_fkey;
ALTER TABLE public.risk_scores
    ADD CONSTRAINT risk_scores_field_id_fkey
    FOREIGN KEY (field_id) REFERENCES public.fields(id) ON DELETE CASCADE;

-- The DELETE policy from 01_schema.sql covers the fields row itself. Cascaded
-- deletes on the child tables run as a referential action, not as the caller,
-- so they need no policy of their own - which is why samplings keeps having no
-- DELETE policy at all.
