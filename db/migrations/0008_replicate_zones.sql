-- 0008: replicates become variance zones.
--
-- 0006 modelled one replicate per dropped school, which explodes at larger
-- samples (the replicate-weight table is students x replicates). Schools
-- are now grouped into at most ~120 jackknife zones per the standard
-- practice, so a replicate drops a zone. This is an ALTER on purpose:
-- schemas evolve by forward migration here, never by editing history.

ALTER TABLE replicate DROP COLUMN dropped_school_id;
ALTER TABLE replicate ADD COLUMN n_schools smallint NOT NULL DEFAULT 1;
ALTER TABLE replicate ALTER COLUMN n_schools DROP DEFAULT;
ALTER TABLE replicate ADD CONSTRAINT replicate_n_schools_positive
CHECK (n_schools >= 1);
