-- 0006: jackknife replicate weights for design-based variance estimation.
--
-- One replicate per sampled school (JKn, delete-one-PSU within the canton
-- stratum); replicate_weight is long-format because SQL consumers join and
-- filter it, while R pivots it into a matrix per estimation group. Only the
-- analyst role reads these — variance machinery is microdata territory.

CREATE TABLE replicate (
    replicate_id smallint PRIMARY KEY,
    canton text NOT NULL,
    dropped_school_id text NOT NULL REFERENCES school (school_id),
    jk_factor double precision NOT NULL CHECK (jk_factor > 0 AND jk_factor < 1)
);

CREATE TABLE replicate_weight (
    student_id text NOT NULL REFERENCES student (student_id),
    replicate_id smallint NOT NULL REFERENCES replicate (replicate_id),
    weight double precision NOT NULL CHECK (weight >= 0),
    PRIMARY KEY (student_id, replicate_id)
);

GRANT SELECT ON replicate, replicate_weight TO lsa_analyst;
