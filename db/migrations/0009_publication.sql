-- 0009: a broader public surface, and a home for the statistician's output.
--
-- Four new aggregate views (same suppression rule as everything published),
-- plus analysis_result: the table the R analysis job publishes its
-- design-based estimates into, so the API can serve standard errors and
-- confidence intervals without re-implementing the jackknife in SQL
-- (see docs/adr/0003-aggregation-in-sql.md — SQL aggregates, R infers).

-- Classical item analysis. Aggregates over test items, not persons, so no
-- disclosure risk; still useful: facility (share correct) per item and the
-- weighted version that respects the sampling design.
CREATE VIEW item_stats AS
SELECT
    i.item_id,
    i.domain,
    count(*) AS n_responses,
    round(avg(r.correct)::numeric, 3) AS facility,
    round(
        (sum(s.final_weight * r.correct) / sum(s.final_weight))::numeric, 3
    ) AS weighted_facility
FROM item AS i
INNER JOIN response AS r ON i.item_id = r.item_id
INNER JOIN student AS s ON r.student_id = s.student_id
WHERE s.participated
GROUP BY i.item_id, i.domain;

-- Weighted share of students per proficiency band (below 450 / 450-549 /
-- 550 and above on the reporting scale), averaged over the five plausible
-- values, per canton. Same minimum-cell rule as the means.
CREATE VIEW proficiency_levels AS
WITH per_pv AS (
    SELECT
        s.canton,
        p.pv_no,
        count(*) AS n_students,
        sum(s.final_weight) AS total_w,
        sum(s.final_weight) FILTER (WHERE p.pv < 450) AS w_below,
        sum(s.final_weight) FILTER (WHERE p.pv >= 450 AND p.pv < 550) AS w_mid,
        sum(s.final_weight) FILTER (WHERE p.pv >= 550) AS w_above
    FROM student AS s
    INNER JOIN pv_long AS p ON s.student_id = p.student_id
    WHERE s.participated
    GROUP BY s.canton, p.pv_no
)

SELECT
    canton,
    min(n_students) AS n_students,
    CASE
        WHEN min(n_students) >= 10
            THEN round(avg(coalesce(w_below, 0) / total_w)::numeric * 100, 1)
    END AS pct_below,
    CASE
        WHEN min(n_students) >= 10
            THEN round(avg(coalesce(w_mid, 0) / total_w)::numeric * 100, 1)
    END AS pct_middle,
    CASE
        WHEN min(n_students) >= 10
            THEN round(avg(coalesce(w_above, 0) / total_w)::numeric * 100, 1)
    END AS pct_above
FROM per_pv
GROUP BY canton;

-- Weighted means by sex and language region: six large cells.
CREATE VIEW sex_competency AS
WITH per_pv AS (
    SELECT
        s.sex,
        s.language_region,
        p.pv_no,
        sum(s.final_weight * p.pv) / sum(s.final_weight) AS wmean,
        count(*) AS n_students
    FROM student AS s
    INNER JOIN pv_long AS p ON s.student_id = p.student_id
    WHERE s.participated
    GROUP BY s.sex, s.language_region, p.pv_no
)

SELECT
    sex,
    language_region,
    min(n_students) AS n_students,
    CASE
        WHEN min(n_students) >= 10 THEN round(avg(wmean)::numeric, 2)
    END AS mean_score
FROM per_pv
GROUP BY sex, language_region;

-- One-row national overview for the page header and the API.
CREATE VIEW national_summary AS
WITH per_pv AS (
    SELECT
        p.pv_no,
        sum(s.final_weight * p.pv) / sum(s.final_weight) AS wmean
    FROM student AS s
    INNER JOIN pv_long AS p ON s.student_id = p.student_id
    WHERE s.participated
    GROUP BY p.pv_no
)

SELECT
    (SELECT count(*) FROM school) AS n_schools,
    (SELECT count(*) FROM student) AS n_students_sampled,
    (
        SELECT count(*) FROM student
        WHERE participated
    ) AS n_participants,
    (SELECT round(avg(participated::int)::numeric, 3) FROM student)
        AS response_rate,
    (SELECT round(avg(wmean)::numeric, 2) FROM per_pv) AS mean_score,
    (SELECT count(*) FROM item) AS n_items;

-- Where the R job publishes its inference. The analyst role owns the
-- content (write + replace), the API may only read it. A row is either
-- published with full inference or suppressed with none — the constraint
-- makes half-published rows impossible.
CREATE TABLE analysis_result (
    group_type text NOT NULL CHECK (group_type IN ('canton', 'language_region')),
    group_id text NOT NULL,
    n integer NOT NULL CHECK (n >= 0),
    estimate numeric(6, 2),
    se numeric(6, 2),
    ci_lower numeric(6, 2),
    ci_upper numeric(6, 2),
    suppressed boolean NOT NULL,
    computed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (group_type, group_id),
    CONSTRAINT all_or_nothing CHECK (
        (
            suppressed AND estimate IS NULL AND se IS NULL
            AND ci_lower IS NULL AND ci_upper IS NULL
        )
        OR (
            NOT suppressed AND estimate IS NOT NULL AND se IS NOT NULL
            AND ci_lower IS NOT NULL AND ci_upper IS NOT NULL
        )
    )
);

GRANT SELECT ON item_stats, proficiency_levels, sex_competency,
national_summary TO lsa_api;
GRANT SELECT ON item_stats, proficiency_levels, sex_competency,
national_summary TO lsa_analyst;
GRANT SELECT ON analysis_result TO lsa_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON analysis_result TO lsa_analyst;
