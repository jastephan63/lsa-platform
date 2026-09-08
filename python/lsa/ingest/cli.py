"""Command-line interface: `lsa-ingest load`."""

import sys
from pathlib import Path
from typing import Annotated

import typer

from lsa import db
from lsa.ingest import loader

app = typer.Typer(help="Validate and load the synthetic assessment data into PostgreSQL.")


@app.callback()
def main() -> None:
    """Keep `load` an explicit subcommand even while it is the only one."""


@app.command()
def load(
    data_dir: Annotated[
        Path, typer.Option(help="Directory containing the raw CSV files.")
    ] = Path("data/raw"),
    report_dir: Annotated[
        Path, typer.Option(help="Where to write the rejection report.")
    ] = Path("data/reports"),
    min_response_rate: Annotated[
        float, typer.Option(help="Strata below this response rate are flagged.")
    ] = 0.8,
    strict: Annotated[
        bool, typer.Option("--strict", help="Exit non-zero if any record was rejected.")
    ] = False,
) -> None:
    """Validate the CSVs, load accepted rows, write a rejection report.

    The load replaces existing data in one transaction and is safe to re-run.
    """
    result, accepted = loader.validate(data_dir, min_response_rate)
    with db.connect() as conn:
        result.loaded = loader.load(conn, accepted)
    report = loader.write_report(result, report_dir)

    for table, n in result.loaded.items():
        typer.echo(f"loaded {n:>6} rows into {table}")
    typer.echo(
        f"rejected {len(result.rejects)} record(s), "
        f"{len(result.warnings)} warning(s) — report: {report}"
    )
    if strict and result.rejects:
        sys.exit(1)


if __name__ == "__main__":
    app()
