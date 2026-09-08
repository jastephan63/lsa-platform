"""Cross-file plausibility checks, kept as pure functions so they are trivially
unit-testable without a database."""

from collections import Counter
from dataclasses import dataclass

from lsa.ingest.models import (
    PlausibleValueRow,
    ReplicateRow,
    ReplicateWeightRow,
    ResponseRow,
    SchoolRow,
    StudentRow,
)


@dataclass(frozen=True)
class Finding:
    """One problem found during ingestion.

    severity 'reject' drops the record (and its dependents) from the load;
    severity 'warn' goes to the report but does not block anything.
    """

    severity: str  # "reject" | "warn"
    source: str  # file the finding refers to
    key: str  # identifier of the offending record or stratum
    message: str


def referential_integrity(
    schools: list[SchoolRow],
    students: list[StudentRow],
    responses: list[ResponseRow],
    pvs: list[PlausibleValueRow],
    item_ids: set[str],
) -> list[Finding]:
    """Every foreign key must resolve; orphans are rejected."""
    findings: list[Finding] = []
    school_ids = {s.school_id for s in schools}
    student_ids = {s.student_id for s in students}
    responder_ids = {s.student_id for s in students if s.participated}

    for st in students:
        if st.school_id not in school_ids:
            findings.append(
                Finding("reject", "students.csv", st.student_id,
                        f"unknown school {st.school_id}")
            )
    for r in responses:
        if r.student_id not in student_ids:
            findings.append(
                Finding("reject", "responses.csv", f"{r.student_id}/{r.item_id}",
                        "response for unknown student")
            )
        if r.item_id not in item_ids:
            findings.append(
                Finding("reject", "responses.csv", f"{r.student_id}/{r.item_id}",
                        f"unknown item {r.item_id}")
            )
    for pv in pvs:
        if pv.student_id not in responder_ids:
            findings.append(
                Finding("reject", "plausible_values.csv", pv.student_id,
                        "plausible values for a student who did not participate")
            )
    return findings


def school_consistency(schools: list[SchoolRow], students: list[StudentRow]) -> list[Finding]:
    """The canton/region denormalised onto students must match their school."""
    by_id = {s.school_id: s for s in schools}
    findings: list[Finding] = []
    for st in students:
        school = by_id.get(st.school_id)
        if school is None:
            continue  # already rejected by referential_integrity
        if (st.canton, st.language_region) != (school.canton, school.language_region):
            findings.append(
                Finding("reject", "students.csv", st.student_id,
                        f"canton/region {st.canton}/{st.language_region} does not match "
                        f"school {school.school_id} ({school.canton}/{school.language_region})")
            )
    return findings


def response_rates(students: list[StudentRow], minimum: float) -> list[Finding]:
    """Response rate per stratum (canton). Below-minimum strata are flagged as
    warnings: low response is an analytic problem, not a data error."""
    sampled: Counter[str] = Counter()
    responded: Counter[str] = Counter()
    for st in students:
        sampled[st.canton] += 1
        if st.participated:
            responded[st.canton] += 1
    findings: list[Finding] = []
    for canton in sorted(sampled):
        rate = responded[canton] / sampled[canton]
        if rate < minimum:
            findings.append(
                Finding("warn", "students.csv", canton,
                        f"response rate {rate:.3f} below minimum {minimum:.2f}")
            )
    return findings


def replicate_integrity(
    schools: list[SchoolRow],
    students: list[StudentRow],
    replicates: list[ReplicateRow],
    rep_weights: list[ReplicateWeightRow],
) -> list[Finding]:
    """Replicate structure: zones must partition each stratum's schools, and
    every replicate weight must reference a known replicate and a
    participating student."""
    findings: list[Finding] = []
    responder_ids = {s.student_id for s in students if s.participated}
    replicate_ids = {r.replicate_id for r in replicates}

    schools_per_canton = Counter(s.canton for s in schools)
    zoned_per_canton: Counter[str] = Counter()
    for rep in replicates:
        zoned_per_canton[rep.canton] += rep.n_schools
    for canton, n in schools_per_canton.items():
        if zoned_per_canton.get(canton, 0) != n:
            findings.append(
                Finding("reject", "replicates.csv", canton,
                        f"zones cover {zoned_per_canton.get(canton, 0)} schools "
                        f"but the stratum has {n}")
            )
    for w in rep_weights:
        key = f"{w.student_id}/{w.replicate_id}"
        if w.replicate_id not in replicate_ids:
            findings.append(
                Finding("reject", "replicate_weights.csv", key,
                        "unknown replicate")
            )
        if w.student_id not in responder_ids:
            findings.append(
                Finding("reject", "replicate_weights.csv", key,
                        "replicate weight for a non-participating student")
            )
    return findings


def duplicate_keys(ids: list[str], source: str) -> list[Finding]:
    """Primary keys must be unique within a file."""
    return [
        Finding("reject", source, key, "duplicate primary key")
        for key, n in Counter(ids).items()
        if n > 1
    ]
