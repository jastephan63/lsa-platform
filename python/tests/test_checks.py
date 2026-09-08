from lsa.ingest import checks
from lsa.ingest.models import ResponseRow, SchoolRow, StudentRow


def school(**overrides: object) -> SchoolRow:
    base: dict[str, object] = {
        "school_id": "SCH0001",
        "canton": "BE",
        "language_region": "de",
        "n_students": 50,
        "incl_prob": 0.4,
        "school_weight": 2.5,
    }
    return SchoolRow.model_validate(base | overrides)


def student(**overrides: object) -> StudentRow:
    base: dict[str, object] = {
        "student_id": "STU00001",
        "school_id": "SCH0001",
        "canton": "BE",
        "language_region": "de",
        "sex": "f",
        "ses_quintile": 3,
        "participated": True,
        "student_weight": 12.5,
        "final_weight": 14.1,
    }
    return StudentRow.model_validate(base | overrides)


def test_orphan_student_rejected() -> None:
    findings = checks.referential_integrity(
        [school()], [student(school_id="SCH9999")], [], [], set()
    )
    assert [f.severity for f in findings] == ["reject"]
    assert "unknown school" in findings[0].message


def test_response_for_unknown_item_rejected() -> None:
    resp = ResponseRow.model_validate(
        {"student_id": "STU00001", "item_id": "IT99", "correct": 1}
    )
    findings = checks.referential_integrity([school()], [student()], [resp], [], {"IT01"})
    assert findings and findings[0].key == "STU00001/IT99"


def test_canton_mismatch_rejected() -> None:
    findings = checks.school_consistency([school()], [student(canton="ZH")])
    assert findings and findings[0].severity == "reject"


def test_low_response_rate_is_warning_not_reject() -> None:
    students = [
        student(student_id=f"STU0000{i}", participated=(i == 1),
                final_weight=14.1 if i == 1 else None)
        for i in range(1, 5)
    ]
    findings = checks.response_rates(students, minimum=0.8)
    assert [f.severity for f in findings] == ["warn"]
    assert findings[0].key == "BE"


def test_duplicate_student_ids_rejected() -> None:
    findings = checks.duplicate_keys(["STU00001", "STU00001"], "students.csv")
    assert [f.message for f in findings] == ["duplicate primary key"]
