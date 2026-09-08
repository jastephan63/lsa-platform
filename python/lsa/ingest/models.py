"""Row-level validation models for the raw CSV files.

Each model mirrors one file from docs/data-spec.md. Validation failures are
collected per row into the rejection report rather than aborting the run.
"""

from typing import Literal

from pydantic import BaseModel, Field, model_validator

CANTONS = frozenset(
    ["AG", "AI", "AR", "BE", "BL", "BS", "FR", "GE", "GL", "GR", "JU", "LU", "NE",
     "NW", "OW", "SG", "SH", "SO", "SZ", "TG", "TI", "UR", "VD", "VS", "ZG", "ZH"]
)


class SchoolRow(BaseModel):
    school_id: str = Field(pattern=r"^SCH\d{4}$")
    canton: str
    language_region: Literal["de", "fr", "it"]
    n_students: int = Field(gt=0)
    incl_prob: float = Field(gt=0, le=1)
    school_weight: float = Field(ge=1)

    @model_validator(mode="after")
    def known_canton(self) -> "SchoolRow":
        if self.canton not in CANTONS:
            raise ValueError(f"unknown canton {self.canton!r}")
        return self


class StudentRow(BaseModel):
    student_id: str = Field(pattern=r"^STU\d{5}$")
    school_id: str = Field(pattern=r"^SCH\d{4}$")
    canton: str
    language_region: Literal["de", "fr", "it"]
    sex: Literal["f", "m"]
    ses_quintile: int = Field(ge=1, le=5)
    participated: bool
    student_weight: float = Field(gt=0)
    final_weight: float | None = None

    @model_validator(mode="after")
    def weight_iff_participated(self) -> "StudentRow":
        if self.participated and (self.final_weight is None or self.final_weight <= 0):
            raise ValueError("participating student must have a positive final_weight")
        if not self.participated and self.final_weight is not None:
            raise ValueError("non-participating student must not have a final_weight")
        return self


class ItemRow(BaseModel):
    item_id: str = Field(pattern=r"^IT\d{2}$")
    difficulty: float = Field(ge=-5, le=5)
    domain: Literal["reading", "math", "science"]


class ResponseRow(BaseModel):
    student_id: str = Field(pattern=r"^STU\d{5}$")
    item_id: str = Field(pattern=r"^IT\d{2}$")
    # CSV input arrives as strings; a constrained int coerces "0"/"1" while
    # still rejecting anything outside the dichotomous range.
    correct: int = Field(ge=0, le=1)


class ReplicateRow(BaseModel):
    replicate_id: int = Field(ge=1)
    canton: str
    n_schools: int = Field(ge=1)
    # (G_h - 1) / G_h with at least two zones per stratum: strictly (0, 1).
    jk_factor: float = Field(gt=0, lt=1)


class ReplicateWeightRow(BaseModel):
    student_id: str = Field(pattern=r"^STU\d{5}$")
    replicate_id: int = Field(ge=1)
    weight: float = Field(ge=0)


class PlausibleValueRow(BaseModel):
    student_id: str = Field(pattern=r"^STU\d{5}$")
    # The reporting scale is mean 500, SD 100; values far outside are a sign
    # of a broken upstream scaling step, not a very able student.
    pv1: float = Field(ge=0, le=1000)
    pv2: float = Field(ge=0, le=1000)
    pv3: float = Field(ge=0, le=1000)
    pv4: float = Field(ge=0, le=1000)
    pv5: float = Field(ge=0, le=1000)
