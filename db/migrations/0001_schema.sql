-- 0001: base schema for the synthetic assessment data.
-- Applied by scripts/migrate.sh inside a transaction; must be re-runnable
-- only via the schema_migrations guard, so no IF NOT EXISTS here — a partial
-- apply should fail loudly rather than paper over drift.

CREATE TABLE school (
    school_id text PRIMARY KEY,
    canton text NOT NULL CHECK (char_length(canton) = 2),
    language_region text NOT NULL CHECK (language_region IN ('de', 'fr', 'it')),
    n_students integer NOT NULL CHECK (n_students > 0),
    incl_prob double precision NOT NULL CHECK (incl_prob > 0 AND incl_prob <= 1),
    school_weight double precision NOT NULL CHECK (school_weight >= 1)
);

CREATE TABLE student (
    student_id text PRIMARY KEY,
    school_id text NOT NULL REFERENCES school (school_id),
    canton text NOT NULL,
    language_region text NOT NULL,
    sex text NOT NULL CHECK (sex IN ('f', 'm')),
    ses_quintile smallint NOT NULL CHECK (ses_quintile BETWEEN 1 AND 5),
    participated boolean NOT NULL,
    student_weight double precision NOT NULL CHECK (student_weight > 0),
    -- Present exactly when the student participated (nonresponse-adjusted).
    final_weight double precision,
    CONSTRAINT final_weight_iff_participated
    CHECK (
        (participated AND final_weight > 0)
        OR (NOT participated AND final_weight IS NULL)
    )
);

CREATE INDEX student_school_idx ON student (school_id);
CREATE INDEX student_canton_idx ON student (canton);

CREATE TABLE item (
    item_id text PRIMARY KEY,
    difficulty double precision NOT NULL,
    domain text NOT NULL CHECK (domain IN ('reading', 'math', 'science'))
);

CREATE TABLE response (
    student_id text NOT NULL REFERENCES student (student_id),
    item_id text NOT NULL REFERENCES item (item_id),
    correct smallint NOT NULL CHECK (correct IN (0, 1)),
    PRIMARY KEY (student_id, item_id)
);

CREATE TABLE plausible_value (
    student_id text PRIMARY KEY REFERENCES student (student_id),
    pv1 double precision NOT NULL,
    pv2 double precision NOT NULL,
    pv3 double precision NOT NULL,
    pv4 double precision NOT NULL,
    pv5 double precision NOT NULL
);
