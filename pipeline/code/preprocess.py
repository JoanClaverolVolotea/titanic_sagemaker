#!/usr/bin/env python3
"""Preprocess Titanic CSV splits from S3 into XGBoost-friendly numeric files."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
from statistics import median

import boto3


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-train-uri", required=True)
    parser.add_argument("--input-validation-uri", required=True)
    parser.add_argument("--output-prefix", default="")
    parser.add_argument("--code-bundle-uri", default="")
    return parser.parse_args()


def parse_s3_uri(uri: str) -> tuple[str, str]:
    if not uri.startswith("s3://"):
        raise ValueError(f"Invalid S3 URI: {uri}")
    no_scheme = uri[5:]
    bucket, key = no_scheme.split("/", 1)
    return bucket, key


def download_s3_csv(uri: str, target_path: Path) -> None:
    bucket, key = parse_s3_uri(uri)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    boto3.client("s3").download_file(bucket, key, str(target_path))


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        raise ValueError(f"Input CSV has no rows: {path}")
    return rows


def parse_float(value: str | None) -> float | None:
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    return float(value)


def to_int(value: str | None, default: int = 0) -> int:
    if value is None:
        return default
    value = value.strip()
    if not value:
        return default
    return int(float(value))


def encode_features(row: dict[str, str], age_fill: float, fare_fill: float) -> list[float]:
    sex_map = {"male": 0.0, "female": 1.0}
    embarked_map = {"C": 0.0, "Q": 1.0, "S": 2.0}

    pclass = float(to_int(row.get("Pclass"), default=3))
    sex = sex_map.get((row.get("Sex") or "").strip().lower(), -1.0)
    age = parse_float(row.get("Age"))
    age = age_fill if age is None else age
    sibsp = float(to_int(row.get("SibSp"), default=0))
    parch = float(to_int(row.get("Parch"), default=0))
    fare = parse_float(row.get("Fare"))
    fare = fare_fill if fare is None else fare
    embarked = embarked_map.get((row.get("Embarked") or "").strip().upper(), -1.0)

    return [pclass, sex, age, sibsp, parch, fare, embarked]


def label_from_row(row: dict[str, str]) -> int:
    value = row.get("Survived")
    if value is None:
        raise ValueError("Missing Survived column")
    return to_int(value, default=0)


def write_csv(path: Path, rows: list[list[float | int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerows(rows)


def main() -> None:
    args = parse_args()

    work_dir = Path("/tmp/titanic_preprocess")
    train_local = work_dir / "train.csv"
    validation_local = work_dir / "validation.csv"

    download_s3_csv(args.input_train_uri, train_local)
    download_s3_csv(args.input_validation_uri, validation_local)

    train_rows = read_rows(train_local)
    validation_rows = read_rows(validation_local)

    ages = [v for v in (parse_float(r.get("Age")) for r in train_rows) if v is not None]
    fares = [v for v in (parse_float(r.get("Fare")) for r in train_rows) if v is not None]
    age_fill = float(median(ages)) if ages else 0.0
    fare_fill = float(median(fares)) if fares else 0.0

    train_xgb: list[list[float | int]] = []
    validation_xgb: list[list[float | int]] = []

    for row in train_rows:
        label = label_from_row(row)
        features = encode_features(row, age_fill=age_fill, fare_fill=fare_fill)
        train_xgb.append([label, *features])

    for row in validation_rows:
        label = label_from_row(row)
        features = encode_features(row, age_fill=age_fill, fare_fill=fare_fill)
        validation_xgb.append([label, *features])

    train_out = Path("/opt/ml/processing/output/train/train_xgb.csv")
    validation_out = Path("/opt/ml/processing/output/validation/validation_xgb.csv")

    write_csv(train_out, train_xgb)
    write_csv(validation_out, validation_xgb)

    print(
        f"Prepared files train={len(train_xgb)} validation={len(validation_xgb)} "
        f"age_fill={age_fill:.4f} fare_fill={fare_fill:.4f}"
    )


if __name__ == "__main__":
    main()
