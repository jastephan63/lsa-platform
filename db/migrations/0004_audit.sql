-- 0004: audit log of who queried what through the API.
--
-- The API writes one row per data request. The role can only INSERT: an
-- attacker with the API credentials cannot read or rewrite history. There is
-- no row-level data in here by design — endpoint and parameters only.

CREATE TABLE api_audit_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ts timestamptz NOT NULL DEFAULT now(),
    request_id text NOT NULL,
    client text NOT NULL,
    endpoint text NOT NULL,
    params text NOT NULL DEFAULT ''
);

CREATE INDEX api_audit_log_ts_idx ON api_audit_log (ts);

GRANT INSERT ON api_audit_log TO lsa_api;
