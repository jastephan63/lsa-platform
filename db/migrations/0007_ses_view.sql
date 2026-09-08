-- 0007: finer-grained aggregates for the authenticated tier.
--
-- Canton x SES-quintile cells are much smaller than canton cells, so many
-- fall below the publication threshold — which is exactly the point: this
-- view demonstrates suppression under pressure, and the API only serves it
-- behind authentication (see docs/security.md).

CREATE VIEW canton_ses_competency AS
WITH per_pv AS (
    SELECT
        s.canton,
        s.ses_quintile,
        p.pv_no,
        sum(s.final_weight * p.pv) / sum(s.final_weight) AS wmean,
        count(*) AS n_students
    FROM student AS s
    INNER JOIN pv_long AS p ON s.student_id = p.student_id
    WHERE s.participated
    GROUP BY s.canton, s.ses_quintile, p.pv_no
)

SELECT
    canton,
    ses_quintile,
    min(n_students) AS n_students,
    CASE
        WHEN min(n_students) >= 10 THEN round(avg(wmean)::numeric, 2)
    END AS mean_score
FROM per_pv
GROUP BY canton, ses_quintile;

GRANT SELECT ON canton_ses_competency TO lsa_api;
GRANT SELECT ON canton_ses_competency TO lsa_analyst;
