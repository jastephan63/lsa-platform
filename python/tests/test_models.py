import pytest
from pydantic import ValidationError

from lsa.ingest.models import PlausibleValueRow, SchoolRow, StudentRow

VALID_STUDENT = {
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


def test_valid_student_passes() -> None:
    assert StudentRow.model_validate(VALID_STUDENT).canton == "BE"


def test_participant_without_final_weight_rejected() -> None:
    with pytest.raises(ValidationError, match="final_weight"):
        StudentRow.model_validate({**VALID_STUDENT, "final_weight": None})


def test_nonparticipant_with_final_weight_rejected() -> None:
    with pytest.raises(ValidationError, match="final_weight"):
        StudentRow.model_validate({**VALID_STUDENT, "participated": False})


def test_unknown_canton_rejected() -> None:
    with pytest.raises(ValidationError, match="unknown canton"):
        SchoolRow.model_validate(
            {
                "school_id": "SCH0001",
                "canton": "XX",
                "language_region": "de",
                "n_students": 50,
                "incl_prob": 0.4,
                "school_weight": 2.5,
            }
        )


def test_out_of_scale_pv_rejected() -> None:
    with pytest.raises(ValidationError):
        PlausibleValueRow.model_validate(
            {"student_id": "STU00001", "pv1": 1500, "pv2": 500, "pv3": 500,
             "pv4": 500, "pv5": 500}
        )
