-- 0003: least-privilege database roles.
--
-- The API connects as lsa_api, which can read the published views and nothing
-- else — no base tables, so a compromised API cannot read row-level data.
-- Roles are cluster-wide in PostgreSQL while migrations are per-database,
-- hence the guarded creation. The role is created NOLOGIN with no password:
-- credentials are attached out-of-band by scripts/bootstrap.sh from the
-- environment, so no secret ever appears in a migration file.

DO $$
BEGIN
    CREATE ROLE lsa_api NOLOGIN;
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE 'role lsa_api already exists, skipping';
END
$$;

GRANT USAGE ON SCHEMA public TO lsa_api;
GRANT SELECT ON canton_competency TO lsa_api;
GRANT SELECT ON language_region_competency TO lsa_api;
GRANT SELECT ON canton_response_rate TO lsa_api;
