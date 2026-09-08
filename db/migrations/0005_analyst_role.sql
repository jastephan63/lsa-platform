-- 0005: analyst role for the R analysis jobs.
--
-- Privilege split, deliberately asymmetric (see docs/datenschutz.md):
--   lsa_api     → aggregates only (published views), for the public surface
--   lsa_analyst → SELECT on the pseudonymised base tables, because weighted
--                 estimation needs microdata; still no write access and no
--                 access to the audit log.
-- Like lsa_api, the role is created NOLOGIN; credentials come from the
-- environment via scripts/bootstrap.sh.

DO $$
BEGIN
    CREATE ROLE lsa_analyst NOLOGIN;
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE 'role lsa_analyst already exists, skipping';
END
$$;

GRANT USAGE ON SCHEMA public TO lsa_analyst;
GRANT SELECT ON school, student, item, response, plausible_value TO lsa_analyst;
GRANT SELECT ON canton_competency, language_region_competency,
canton_response_rate TO lsa_analyst;
