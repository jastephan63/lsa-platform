-- 0002: analytical views.
--
-- Aggregation happens in SQL (not in application code) so that every consumer
-- — the R package, the API, an analyst with psql — sees the same definitions.
-- Variance estimation across plausible values stays in R, where it belongs
-- (see docs/adr/0003-aggregation-in-sql.md).
--
-- Small-cell suppression: cells with fewer than 10 responding students are
-- published as NULL. The threshold is duplicated in the R package and the API
-- configuration; the API refuses to serve rows the view has suppressed. Ten
-- is a common minimum cell size in official statistics disclosure control.

-- Long form of the five plausible values, one row per student and PV.
CREATE VIEW pv_long AS
SELECT
    pv.student_id,
    v.pv_no,
    v.pv
FROM plausible_value AS pv
CROSS JOIN LATERAL (
    VALUES (1, pv.pv1), (2, pv.pv2), (3, pv.pv3), (4, pv.pv4), (5, pv.pv5)
) AS v (pv_no, pv);

-- Weighted competency mean by canton.
-- Methodology: compute the weighted mean separately per plausible value, then
-- average the five estimates (Rubin's rule for the point estimate). For a
-- weighted mean this equals averaging PVs per student first, but the per-PV
-- form is the one that generalises to variance estimation, so we keep it.
CREATE VIEW canton_competency AS
WITH per_pv AS (
    SELECT
        s.canton,
        s.language_region,
        p.pv_no,
        sum(s.final_weight * p.pv) / sum(s.final_weight) AS wmean,
        count(*) AS n_students
    FROM student AS s
    INNER JOIN pv_long AS p ON s.student_id = p.student_id
    WHERE s.participated
    GROUP BY s.canton, s.language_region, p.pv_no
)

SELECT
    canton,
    language_region,
    min(n_students) AS n_students,
    -- Suppress the estimate, not the row: consumers can see that a canton
    -- exists but published no value, which is more honest than dropping it.
    CASE
        WHEN min(n_students) >= 10 THEN round(avg(wmean)::numeric, 2)
    END AS mean_score
FROM per_pv
GROUP BY canton, language_region;

-- Weighted competency mean by language region (same construction).
CREATE VIEW language_region_competency AS
WITH per_pv AS (
    SELECT
        s.language_region,
        p.pv_no,
        sum(s.final_weight * p.pv) / sum(s.final_weight) AS wmean,
        count(*) AS n_students
    FROM student AS s
    INNER JOIN pv_long AS p ON s.student_id = p.student_id
    WHERE s.participated
    GROUP BY s.language_region, p.pv_no
)

SELECT
    language_region,
    min(n_students) AS n_students,
    CASE
        WHEN min(n_students) >= 10 THEN round(avg(wmean)::numeric, 2)
    END AS mean_score
FROM per_pv
GROUP BY language_region;

-- Response rates by stratum, with regional and national context.
--
-- Why a CTE plus window functions: the CTE does the one expensive pass over
-- student (counting sampled vs responding per stratum); the window functions
-- then place each stratum in context — rank within its language region and
-- deviation from the national rate — without re-scanning or self-joining the
-- table. Written as nested subqueries this would either scan student three
-- times or bury the grouping logic; this form keeps one scan and reads
-- top-to-bottom: count, then compare.
CREATE VIEW canton_response_rate AS
WITH stratum AS (
    SELECT
        canton,
        language_region,
        count(*) AS n_sampled,
        count(*) FILTER (WHERE participated) AS n_responded
    FROM student
    GROUP BY canton, language_region
)

SELECT
    canton,
    language_region,
    n_sampled,
    n_responded,
    round(n_responded::numeric / n_sampled, 4) AS response_rate,
    rank() OVER (
        PARTITION BY language_region
        ORDER BY n_responded::numeric / n_sampled DESC
    ) AS rank_in_region,
    round(
        n_responded::numeric / n_sampled
        - sum(n_responded) OVER ()::numeric / sum(n_sampled) OVER (),
        4
    ) AS diff_from_national
FROM stratum;
