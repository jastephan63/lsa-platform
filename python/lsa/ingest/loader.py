"""Load the raw CSV files into PostgreSQL.

The load is a batch replace inside one transaction: validate everything,
delete existing rows in FK-safe order, insert the accepted rows, and write a
rejection report. Either the whole load commits or nothing does, which is what
makes re-running safe (idempotent for identical input, self-correcting for
fixed input).
"""

import csv
import json
from collections.abc import Sequence
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import TypeVar

import psycopg
from psycopg import sql
from pydantic import BaseModel, ValidationError

from lsa.ingest import checks
from lsa.ingest.models import (
    ItemRow,
    PlausibleValueRow,
    ReplicateRow,
    ReplicateWeightRow,
    ResponseRow,
    SchoolRow,
    StudentRow,
)

M = TypeVar("M", bound=BaseModel)

Accepted = dict[str, Sequence[BaseModel]]


@dataclass
class LoadResult:
    loaded: dict[str, int] = field(default_factory=dict)
    findings: list[checks.Finding] = field(default_factory=list)

    @property
    def rejects(self) -> list[checks.Finding]:
        return [f for f in self.findings if f.severity == "reject"]

    @property
    def warnings(self) -> list[checks.Finding]:
        return [f for f in self.findings if f.severity == "warn"]


def _read_rows(path: Path, model: type[M], findings: list[checks.Finding]) -> list[M]:
    """Parse one CSV; invalid rows become 'reject' findings, valid rows return."""
    rows: list[M] = []
    with path.open(newline="") as fh:
        for line_no, raw in enumerate(csv.DictReader(fh), start=2):
            # R writes booleans as TRUE/FALSE and missing values as NA.
            cleaned = {
                k: (None if v == "NA" else v.lower() if v in ("TRUE", "FALSE") else v)
                for k, v in raw.items()
            }
            try:
                rows.append(model.model_validate(cleaned))
            except ValidationError as exc:
                first = exc.errors()[0]
                findings.append(
                    checks.Finding(
                        "reject",
                        path.name,
                        f"line {line_no}",
                        f"{'.'.join(str(p) for p in first['loc'])}: {first['msg']}",
                    )
                )
    return rows


def validate(data_dir: Path, min_response_rate: float) -> tuple[LoadResult, Accepted]:
    """Run all validations and return the accepted rows per target table."""
    result = LoadResult()
    schools = _read_rows(data_dir / "schools.csv", SchoolRow, result.findings)
    students = _read_rows(data_dir / "students.csv", StudentRow, result.findings)
    items = _read_rows(data_dir / "items.csv", ItemRow, result.findings)
    responses = _read_rows(data_dir / "responses.csv", ResponseRow, result.findings)
    pvs = _read_rows(data_dir / "plausible_values.csv", PlausibleValueRow, result.findings)
    replicates = _read_rows(data_dir / "replicates.csv", ReplicateRow, result.findings)
    rep_weights = _read_rows(
        data_dir / "replicate_weights.csv", ReplicateWeightRow, result.findings
    )

    result.findings += checks.duplicate_keys([s.school_id for s in schools], "schools.csv")
    result.findings += checks.duplicate_keys([s.student_id for s in students], "students.csv")
    result.findings += checks.referential_integrity(
        schools, students, responses, pvs, {i.item_id for i in items}
    )
    result.findings += checks.school_consistency(schools, students)
    result.findings += checks.response_rates(students, min_response_rate)
    result.findings += checks.replicate_integrity(schools, students, replicates, rep_weights)

    # Drop rejected records, then everything that depends on a dropped record.
    # Rejection keys per source: students.csv → student_id,
    # responses.csv → "student_id/item_id", plausible_values.csv → student_id.
    bad_students = {f.key for f in result.rejects if f.source == "students.csv"}
    bad_responses = {f.key for f in result.rejects if f.source == "responses.csv"}
    bad_pvs = {f.key for f in result.rejects if f.source == "plausible_values.csv"}

    students = [s for s in students if s.student_id not in bad_students]
    student_ids = {s.student_id for s in students}
    responses = [
        r
        for r in responses
        if r.student_id in student_ids and f"{r.student_id}/{r.item_id}" not in bad_responses
    ]
    pvs = [
        p for p in pvs if p.student_id in student_ids and p.student_id not in bad_pvs
    ]
    rep_weights = [w for w in rep_weights if w.student_id in student_ids]

    return result, {
        "school": schools,
        "student": students,
        "item": items,
        "response": responses,
        "plausible_value": pvs,
        "replicate": replicates,
        "replicate_weight": rep_weights,
    }


def load(conn: psycopg.Connection, accepted: Accepted) -> dict[str, int]:
    """Replace all assessment data in one transaction."""
    counts: dict[str, int] = {}
    with conn.transaction(), conn.cursor() as cur:
        for table in ("replicate_weight", "replicate", "plausible_value",
                      "response", "student", "item", "school"):
            cur.execute(sql.SQL("DELETE FROM {}").format(sql.Identifier(table)))
        for table in ("school", "student", "item", "response", "plausible_value",
                      "replicate", "replicate_weight"):
            rows = accepted[table]
            if not rows:
                counts[table] = 0
                continue
            cols = list(rows[0].__class__.model_fields)
            # COPY is the fast path for bulk loads (60k+ response rows) and
            # keeps this function free of per-model INSERT statements.
            with cur.copy(
                sql.SQL("COPY {} ({}) FROM STDIN").format(
                    sql.Identifier(table),
                    sql.SQL(", ").join(map(sql.Identifier, cols)),
                )
            ) as copy:
                for row in rows:
                    copy.write_row(tuple(getattr(row, c) for c in cols))
            counts[table] = len(rows)
    return counts


def write_report(result: LoadResult, report_dir: Path) -> Path:
    """Write the rejection/warning report as JSON plus a CSV of findings."""
    report_dir.mkdir(parents=True, exist_ok=True)
    report = {
        "generated_at": datetime.now(UTC).isoformat(timespec="seconds"),
        "loaded": result.loaded,
        "n_rejected": len(result.rejects),
        "n_warnings": len(result.warnings),
        "findings": [asdict(f) for f in result.findings],
    }
    json_path = report_dir / "ingest-report.json"
    json_path.write_text(json.dumps(report, indent=2) + "\n")
    with (report_dir / "ingest-findings.csv").open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["severity", "source", "key", "message"])
        writer.writeheader()
        writer.writerows(asdict(f) for f in result.findings)
    return json_path
