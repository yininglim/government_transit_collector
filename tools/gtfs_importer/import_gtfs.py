#!/usr/bin/env python3
"""Validate a GTFS Static ZIP and optionally import it into existing Supabase tables."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import math
import re
import sys
import zipfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Iterator


REQUIRED_FILES = (
    "agency.txt",
    "stops.txt",
    "routes.txt",
    "calendar.txt",
    "trips.txt",
    "stop_times.txt",
    "shapes.txt",
)

REQUIRED_COLUMNS = {
    "agency.txt": {"agency_id", "agency_name", "agency_url", "agency_timezone"},
    "stops.txt": {"stop_id", "stop_name", "stop_lat", "stop_lon"},
    "routes.txt": {"route_id", "agency_id", "route_type"},
    "calendar.txt": {
        "service_id", "monday", "tuesday", "wednesday", "thursday",
        "friday", "saturday", "sunday", "start_date", "end_date",
    },
    "trips.txt": {"route_id", "service_id", "trip_id"},
    "stop_times.txt": {
        "trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence",
    },
    "shapes.txt": {"shape_id", "shape_pt_lat", "shape_pt_lon", "shape_pt_sequence"},
    "areas.txt": {"area_id"},
    "stop_areas.txt": {"area_id", "stop_id"},
    "fare_media.txt": {"fare_media_id", "fare_media_type"},
    "rider_categories.txt": {"rider_category_id"},
    "fare_leg_rules.txt": {"fare_product_id"},
    "fare_products.txt": {"fare_product_id", "amount", "currency"},
}

PRIMARY_KEYS = {
    "agency.txt": ("agency_id",),
    "stops.txt": ("stop_id",),
    "routes.txt": ("route_id",),
    "calendar.txt": ("service_id",),
    "trips.txt": ("trip_id",),
    "stop_times.txt": ("trip_id", "stop_sequence"),
    "shapes.txt": ("shape_id", "shape_pt_sequence"),
    "areas.txt": ("area_id",),
    "stop_areas.txt": ("area_id", "stop_id"),
    "fare_media.txt": ("fare_media_id",),
    "rider_categories.txt": ("rider_category_id",),
    "fare_products.txt": ("fare_product_id",),
}

ID_COLUMNS = {
    "agency.txt": ("agency_id",),
    "stops.txt": ("stop_id",),
    "routes.txt": ("route_id",),
    "calendar.txt": ("service_id",),
    "trips.txt": ("trip_id",),
    "shapes.txt": ("shape_id",),
    "areas.txt": ("area_id",),
    "fare_media.txt": ("fare_media_id",),
    "rider_categories.txt": ("rider_category_id",),
    "fare_products.txt": ("fare_product_id",),
}

FOREIGN_KEYS = (
    ("routes.txt", "agency_id", "agency.txt", "agency_id"),
    ("trips.txt", "route_id", "routes.txt", "route_id"),
    ("trips.txt", "service_id", "calendar.txt", "service_id"),
    ("trips.txt", "shape_id", "shapes.txt", "shape_id"),
    ("stop_times.txt", "trip_id", "trips.txt", "trip_id"),
    ("stop_times.txt", "stop_id", "stops.txt", "stop_id"),
    ("stops.txt", "parent_station", "stops.txt", "stop_id"),
    ("stop_areas.txt", "area_id", "areas.txt", "area_id"),
    ("stop_areas.txt", "stop_id", "stops.txt", "stop_id"),
    ("fare_products.txt", "fare_media_id", "fare_media.txt", "fare_media_id"),
    ("fare_products.txt", "rider_category_id", "rider_categories.txt", "rider_category_id"),
    ("fare_leg_rules.txt", "fare_product_id", "fare_products.txt", "fare_product_id"),
    ("fare_leg_rules.txt", "from_area_id", "areas.txt", "area_id"),
    ("fare_leg_rules.txt", "to_area_id", "areas.txt", "area_id"),
)

TIME_RE = re.compile(r"^[0-9]{2}:[0-5][0-9]:[0-5][0-9]$")
IMPORT_FILES = REQUIRED_FILES
ENV_PATH = Path(__file__).resolve().parent / ".env.importer"

IMPORT_TABLES = (
    ("agency.txt", "gtfs_agencies", "agency_id"),
    ("stops.txt", "gtfs_stops", "stop_id"),
    ("routes.txt", "gtfs_routes", "route_id"),
    ("calendar.txt", "gtfs_calendar", "service_id"),
    ("trips.txt", "gtfs_trips", "trip_id"),
    ("stop_times.txt", "gtfs_stop_times", "trip_id,stop_sequence"),
    ("shapes.txt", "gtfs_shapes", "shape_id,shape_pt_sequence"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", required=True, type=Path, dest="zip_path", help="GTFS ZIP path")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Validate only (the default)")
    mode.add_argument("--import", action="store_true", dest="import_mode", help="Import after validation")
    parser.add_argument("--batch-size", type=int, default=500, help="Rows per upsert request (default: 500)")
    args = parser.parse_args()
    if args.batch_size < 1:
        parser.error("--batch-size must be at least 1")
    return args


def add_error(errors: list[str], filename: str, row_number: int | None, message: str) -> None:
    location = filename if row_number is None else f"{filename} row {row_number}"
    errors.append(f"{location}: {message}")


def validate_number(
    errors: list[str], filename: str, row_number: int, column: str, value: str,
    minimum: float, maximum: float,
) -> None:
    try:
        number = float(value)
    except ValueError:
        add_error(errors, filename, row_number, f"{column} is not numeric: {value!r}")
        return
    if not minimum <= number <= maximum:
        add_error(errors, filename, row_number, f"{column} {number} is outside [{minimum}, {maximum}]")


def validate_zip(zip_path: Path) -> tuple[dict[str, int], list[str], list[str]]:
    counts: dict[str, int] = {}
    errors: list[str] = []
    warnings: list[str] = []
    ids: dict[tuple[str, str], set[str]] = defaultdict(set)
    references: dict[tuple[str, str], list[tuple[int, str]]] = defaultdict(list)

    try:
        archive = zipfile.ZipFile(zip_path)
    except (FileNotFoundError, zipfile.BadZipFile, OSError) as exc:
        return counts, [f"Could not open {zip_path}: {exc}"], warnings

    with archive:
        txt_entries: dict[str, zipfile.ZipInfo] = {}
        for info in archive.infolist():
            if info.is_dir() or not info.filename.lower().endswith(".txt"):
                continue
            basename = PurePosixPath(info.filename).name
            if basename in txt_entries:
                add_error(errors, basename, None, "appears more than once in the ZIP")
            else:
                txt_entries[basename] = info

        for filename in REQUIRED_FILES:
            if filename not in txt_entries:
                add_error(errors, filename, None, "required file is missing")

        ordered_names = list(REQUIRED_FILES) + sorted(set(txt_entries) - set(REQUIRED_FILES))
        for filename in ordered_names:
            info = txt_entries.get(filename)
            if info is None:
                continue
            counts[filename] = 0
            seen_keys: set[tuple[str, ...]] = set()
            try:
                with archive.open(info) as raw:
                    stream = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
                    reader = csv.DictReader(stream, strict=True)
                    columns = reader.fieldnames or []
                    missing = REQUIRED_COLUMNS.get(filename, set()) - set(columns)
                    if missing:
                        add_error(errors, filename, 1, f"missing required columns: {', '.join(sorted(missing))}")
                    if None in columns or len(columns) != len(set(columns)):
                        add_error(errors, filename, 1, "header has blank or duplicate column names")

                    for row_number, row in enumerate(reader, start=2):
                        if None in row:
                            add_error(errors, filename, row_number, "has more fields than the header")
                        if not any((value or "").strip() for key, value in row.items() if key is not None):
                            continue
                        counts[filename] += 1
                        clean = {key: (value or "").strip() for key, value in row.items() if key is not None}

                        for column in REQUIRED_COLUMNS.get(filename, set()):
                            if column in clean and not clean[column]:
                                add_error(errors, filename, row_number, f"required value {column} is empty")

                        key_columns = PRIMARY_KEYS.get(filename)
                        if key_columns and all(column in clean for column in key_columns):
                            key = tuple(clean[column] for column in key_columns)
                            if all(key):
                                if key in seen_keys:
                                    add_error(errors, filename, row_number, f"duplicate primary key {key}")
                                seen_keys.add(key)

                        for column in ID_COLUMNS.get(filename, ()):
                            value = clean.get(column, "")
                            if value:
                                ids[(filename, column)].add(value)

                        if filename == "stops.txt":
                            if clean.get("stop_lat"):
                                validate_number(errors, filename, row_number, "stop_lat", clean["stop_lat"], -90, 90)
                            if clean.get("stop_lon"):
                                validate_number(errors, filename, row_number, "stop_lon", clean["stop_lon"], -180, 180)
                        elif filename == "shapes.txt":
                            if clean.get("shape_pt_lat"):
                                validate_number(errors, filename, row_number, "shape_pt_lat", clean["shape_pt_lat"], -90, 90)
                            if clean.get("shape_pt_lon"):
                                validate_number(errors, filename, row_number, "shape_pt_lon", clean["shape_pt_lon"], -180, 180)
                        elif filename == "stop_times.txt":
                            for column in ("arrival_time", "departure_time"):
                                value = clean.get(column, "")
                                if value and not TIME_RE.fullmatch(value):
                                    add_error(errors, filename, row_number, f"invalid GTFS time in {column}: {value!r}")

                        for source_file, source_col, _, _ in FOREIGN_KEYS:
                            if filename == source_file:
                                value = clean.get(source_col, "")
                                if value:
                                    references[(source_file, source_col)].append((row_number, value))
            except (UnicodeDecodeError, csv.Error, OSError) as exc:
                add_error(errors, filename, None, f"could not be read as UTF-8 CSV: {exc}")

        for source_file, source_col, target_file, target_col in FOREIGN_KEYS:
            if source_file not in counts or target_file not in counts:
                continue
            valid_targets = ids[(target_file, target_col)]
            for row_number, value in references[(source_file, source_col)]:
                if value not in valid_targets:
                    add_error(
                        errors, source_file, row_number,
                        f"{source_col}={value!r} does not reference {target_file}.{target_col}",
                    )

        unknown = sorted(set(txt_entries) - set(REQUIRED_COLUMNS))
        for filename in unknown:
            warnings.append(f"{filename}: counted, but no table-specific schema rules are configured")

    return counts, errors, warnings


def load_import_credentials(path: Path) -> tuple[str, str]:
    """Read only the importer-specific env file; never fall back to the Flutter env."""
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except OSError as exc:
        raise RuntimeError(f"Could not read importer credentials at {path}: {exc}") from exc

    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise RuntimeError(f"Invalid credential file syntax at line {line_number}")
        name, value = line.split("=", 1)
        name = name.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[name] = value

    url = values.get("SUPABASE_URL", "")
    key = values.get("SUPABASE_SERVICE_ROLE_KEY", "")
    placeholders = {"your_supabase_project_url", "your_service_role_key"}
    if not url or not key or url in placeholders or key in placeholders:
        raise RuntimeError(
            f"Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in {path} before using --import"
        )
    return url, key


def safe_error(exc: BaseException, secrets: tuple[str, ...] = ()) -> str:
    message = " ".join(str(exc).split()) or exc.__class__.__name__
    for secret in secrets:
        if secret:
            message = message.replace(secret, "[REDACTED]")
    return message[:500]


def zip_entries(archive: zipfile.ZipFile) -> dict[str, zipfile.ZipInfo]:
    return {
        PurePosixPath(info.filename).name: info
        for info in archive.infolist()
        if not info.is_dir() and info.filename.lower().endswith(".txt")
    }


def iter_gtfs_rows(archive: zipfile.ZipFile, info: zipfile.ZipInfo) -> Iterator[dict[str, str]]:
    with archive.open(info) as raw:
        stream = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
        for row in csv.DictReader(stream, strict=True):
            clean = {key: (value or "").strip() for key, value in row.items() if key is not None}
            if any(clean.values()):
                yield clean


def optional_text(row: dict[str, str], column: str) -> str | None:
    return row.get(column) or None


def optional_int(row: dict[str, str], column: str, default: int | None = None) -> int | None:
    value = row.get(column, "")
    return int(value) if value else default


def optional_float(row: dict[str, str], column: str) -> float | None:
    value = row.get(column, "")
    return float(value) if value else None


def service_day_seconds(value: str) -> int:
    hours, minutes, seconds = (int(part) for part in value.split(":"))
    return hours * 3600 + minutes * 60 + seconds


def transform_row(filename: str, row: dict[str, str], import_id: str) -> dict[str, Any]:
    source = {"source_import_id": import_id}
    if filename == "agency.txt":
        return source | {
            "agency_id": row["agency_id"],
            "agency_name": row["agency_name"],
            "agency_url": row["agency_url"],
            "agency_timezone": row["agency_timezone"],
            "agency_phone": optional_text(row, "agency_phone"),
            "agency_lang": optional_text(row, "agency_lang"),
        }
    if filename == "stops.txt":
        return source | {
            "stop_id": row["stop_id"],
            "stop_code": optional_text(row, "stop_code"),
            "stop_name": row["stop_name"],
            "stop_desc": optional_text(row, "stop_desc"),
            "stop_lat": float(row["stop_lat"]),
            "stop_lon": float(row["stop_lon"]),
            "zone_id": optional_text(row, "zone_id"),
            "stop_url": optional_text(row, "stop_url"),
            "location_type": optional_int(row, "location_type", 0),
            "parent_station": optional_text(row, "parent_station"),
        }
    if filename == "routes.txt":
        return source | {
            "route_id": row["route_id"],
            "agency_id": row["agency_id"],
            "route_short_name": optional_text(row, "route_short_name"),
            "route_long_name": optional_text(row, "route_long_name"),
            "route_desc": optional_text(row, "route_desc"),
            "route_type": int(row["route_type"]),
            "route_url": optional_text(row, "route_url"),
            "route_color": optional_text(row, "route_color"),
            "route_text_color": optional_text(row, "route_text_color"),
        }
    if filename == "calendar.txt":
        return source | {
            "service_id": row["service_id"],
            **{day: row[day] == "1" for day in (
                "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
            )},
            "start_date": datetime.strptime(row["start_date"], "%Y%m%d").date().isoformat(),
            "end_date": datetime.strptime(row["end_date"], "%Y%m%d").date().isoformat(),
        }
    if filename == "trips.txt":
        return source | {
            "trip_id": row["trip_id"],
            "route_id": row["route_id"],
            "service_id": row["service_id"],
            "trip_headsign": optional_text(row, "trip_headsign"),
            "direction_id": optional_int(row, "direction_id"),
            "block_id": optional_text(row, "block_id"),
            "shape_id": optional_text(row, "shape_id"),
            "wheelchair_accessible": optional_int(row, "wheelchair_accessible", 0),
        }
    if filename == "stop_times.txt":
        arrival = row["arrival_time"]
        departure = row["departure_time"]
        return source | {
            "trip_id": row["trip_id"],
            "stop_sequence": int(row["stop_sequence"]),
            "stop_id": row["stop_id"],
            "arrival_seconds": service_day_seconds(arrival),
            "departure_seconds": service_day_seconds(departure),
            "arrival_time_text": arrival,
            "departure_time_text": departure,
            "stop_headsign": optional_text(row, "stop_headsign"),
            "shape_dist_traveled": optional_float(row, "shape_dist_traveled"),
            "pickup_type": optional_int(row, "pickup_type", 0),
            "drop_off_type": optional_int(row, "drop_off_type", 0),
        }
    if filename == "shapes.txt":
        return source | {
            "shape_id": row["shape_id"],
            "shape_pt_sequence": int(row["shape_pt_sequence"]),
            "shape_pt_lat": float(row["shape_pt_lat"]),
            "shape_pt_lon": float(row["shape_pt_lon"]),
            "shape_dist_traveled": optional_float(row, "shape_dist_traveled"),
        }
    raise ValueError(f"No import mapping for {filename}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def service_date_range(zip_path: Path) -> tuple[str, str]:
    with zipfile.ZipFile(zip_path) as archive:
        info = zip_entries(archive)["calendar.txt"]
        starts: list[str] = []
        ends: list[str] = []
        for row in iter_gtfs_rows(archive, info):
            starts.append(datetime.strptime(row["start_date"], "%Y%m%d").date().isoformat())
            ends.append(datetime.strptime(row["end_date"], "%Y%m%d").date().isoformat())
    return min(starts), max(ends)


class ImportBatchError(RuntimeError):
    def __init__(self, table: str, batch_number: int, cause: BaseException):
        self.table = table
        self.batch_number = batch_number
        self.cause = cause
        super().__init__(f"{table} batch {batch_number}: {cause}")


def import_feed(zip_path: Path, counts: dict[str, int], batch_size: int) -> None:
    url, service_key = load_import_credentials(ENV_PATH)
    secrets = (url, service_key)
    try:
        from supabase import create_client
    except ImportError as exc:
        raise RuntimeError("Missing dependency. Run: python -m pip install -r requirements.txt") from exc

    try:
        client = create_client(url, service_key)
    except Exception as exc:
        raise RuntimeError(f"Could not initialize Supabase client: {safe_error(exc, secrets)}") from exc
    start_date, end_date = service_date_range(zip_path)
    metadata = {
        "feed_type": "static",
        "source_name": zip_path.name,
        "source_filename": zip_path.name,
        "file_checksum": sha256_file(zip_path),
        "service_start_date": start_date,
        "service_end_date": end_date,
        "row_counts": {name: counts[name] for name in IMPORT_FILES},
        "status": "processing",
    }
    print("Creating gtfs_import_metadata: status=processing")
    try:
        response = client.table("gtfs_import_metadata").insert(metadata).execute()
        if not response.data or not response.data[0].get("import_id"):
            raise RuntimeError("metadata insert returned no import_id")
        import_id = str(response.data[0]["import_id"])
    except Exception as exc:
        raise RuntimeError(f"Could not create import metadata: {safe_error(exc, secrets)}") from exc

    failed: ImportBatchError | None = None
    try:
        with zipfile.ZipFile(zip_path) as archive:
            entries = zip_entries(archive)
            for filename, table, conflict_columns in IMPORT_TABLES:
                total_batches = math.ceil(counts[filename] / batch_size)
                batch: list[dict[str, Any]] = []
                batch_number = 0
                for row in iter_gtfs_rows(archive, entries[filename]):
                    try:
                        batch.append(transform_row(filename, row, import_id))
                    except Exception as exc:
                        raise ImportBatchError(table, batch_number + 1, exc) from exc
                    if len(batch) == batch_size:
                        batch_number += 1
                        print(f"Importing {table}: batch {batch_number} of {total_batches}")
                        try:
                            client.table(table).upsert(batch, on_conflict=conflict_columns).execute()
                        except Exception as exc:
                            raise ImportBatchError(table, batch_number, exc) from exc
                        batch = []
                if batch:
                    batch_number += 1
                    print(f"Importing {table}: batch {batch_number} of {total_batches}")
                    try:
                        client.table(table).upsert(batch, on_conflict=conflict_columns).execute()
                    except Exception as exc:
                        raise ImportBatchError(table, batch_number, exc) from exc
    except ImportBatchError as exc:
        failed = exc
    except Exception as exc:
        failed = ImportBatchError("local GTFS processing", 0, exc)

    if failed is not None:
        summary = safe_error(failed.cause, secrets)
        try:
            client.table("gtfs_import_metadata").update({
                "status": "failed",
                "error_summary": f"{failed.table} batch {failed.batch_number}: {summary}",
            }).eq("import_id", import_id).execute()
        except Exception as metadata_exc:
            print(f"Warning: could not mark metadata failed: {safe_error(metadata_exc, secrets)}", file=sys.stderr)
        raise RuntimeError(
            f"Import failed at {failed.table}, batch {failed.batch_number}: {summary}"
        ) from failed

    try:
        client.table("gtfs_import_metadata").update({
            "status": "completed",
            "imported_at": datetime.now(timezone.utc).isoformat(),
            "error_summary": None,
        }).eq("import_id", import_id).execute()
    except Exception as exc:
        summary = safe_error(exc, secrets)
        try:
            client.table("gtfs_import_metadata").update({
                "status": "failed", "error_summary": f"metadata completion update: {summary}",
            }).eq("import_id", import_id).execute()
        except Exception:
            pass
        raise RuntimeError(f"Records uploaded, but metadata completion failed: {summary}") from exc
    print("Import completed successfully.")


def main() -> int:
    args = parse_args()

    counts, errors, warnings = validate_zip(args.zip_path)
    print("\nGTFS validation summary")
    print("-" * 36)
    for filename, count in counts.items():
        print(f"{filename:.<24} {count} rows")

    if warnings:
        print("\nWarnings:")
        for warning in warnings:
            print(f"- {warning}")

    if errors:
        print(f"\nValidation failed with {len(errors)} error(s):")
        for error in errors:
            print(f"- {error}")
        return 1

    print("\nValidation passed.")
    if not args.import_mode:
        print("Dry run only; no records were imported.")
        return 0

    print("\nImport mode explicitly enabled.")
    try:
        import_feed(args.zip_path, counts, args.batch_size)
    except Exception as exc:
        print(f"Import aborted: {safe_error(exc)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
