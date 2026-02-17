#!/usr/bin/env python3
"""
Prepare Titanic train/validation CSV files for SageMaker built-in XGBoost.

Outputs are numeric-only CSV files without headers:
- train_xgb.csv: label + features
- validation_xgb.csv: label + features
- validation_features_xgb.csv: features only (for batch transform)
- validation_labels.csv: label only (for offline metric calculation)
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare Titanic CSV files for XGBoost training.")
    parser.add_argument("--train-input", default="data/titanic/splits/train.csv", help="Train split CSV path.")
    parser.add_argument(
        "--validation-input",
        default="data/titanic/splits/validation.csv",
        help="Validation split CSV path.",
    )
    parser.add_argument(
        "--train-output",
        default="data/titanic/sagemaker/train_xgb.csv",
        help="Output CSV for XGBoost train channel (label + features).",
    )
    parser.add_argument(
        "--validation-output",
        default="data/titanic/sagemaker/validation_xgb.csv",
        help="Output CSV for XGBoost validation channel (label + features).",
    )
    parser.add_argument(
        "--validation-features-output",
        default="data/titanic/sagemaker/validation_features_xgb.csv",
        help="Output CSV with validation features only (for transform/inference).",
    )
    parser.add_argument(
        "--validation-labels-output",
        default="data/titanic/sagemaker/validation_labels.csv",
        help="Output CSV with validation labels only (for metric calculation).",
    )
    return parser.parse_args()


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
    stripped = value.strip()
    if not stripped:
        return None
    return float(stripped)


def median(values: list[float]) -> float:
    if not values:
        return 0.0
    sorted_values = sorted(values)
    mid = len(sorted_values) // 2
    if len(sorted_values) % 2 == 0:
        return (sorted_values[mid - 1] + sorted_values[mid]) / 2.0
    return sorted_values[mid]


def to_int(value: str | None, default: int = 0) -> int:
    if value is None:
        return default
    stripped = value.strip()
    if not stripped:
        return default
    return int(float(stripped))


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
    label_raw = row.get("Survived")
    if label_raw is None:
        raise ValueError("Missing 'Survived' column in row.")
    return to_int(label_raw, default=0)


def write_csv(path: Path, rows: list[list[float | int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerows(rows)


def main() -> None:
    args = parse_args()

    train_input = Path(args.train_input)
    validation_input = Path(args.validation_input)

    train_rows = read_rows(train_input)
    validation_rows = read_rows(validation_input)

    train_ages = [v for v in (parse_float(r.get("Age")) for r in train_rows) if v is not None]
    train_fares = [v for v in (parse_float(r.get("Fare")) for r in train_rows) if v is not None]
    age_fill = median(train_ages)
    fare_fill = median(train_fares)

    train_encoded: list[list[float | int]] = []
    validation_encoded: list[list[float | int]] = []
    validation_features: list[list[float | int]] = []
    validation_labels: list[list[float | int]] = []

    for row in train_rows:
        label = label_from_row(row)
        features = encode_features(row, age_fill=age_fill, fare_fill=fare_fill)
        train_encoded.append([label, *features])

    for row in validation_rows:
        label = label_from_row(row)
        features = encode_features(row, age_fill=age_fill, fare_fill=fare_fill)
        validation_encoded.append([label, *features])
        validation_features.append(features)
        validation_labels.append([label])

    write_csv(Path(args.train_output), train_encoded)
    write_csv(Path(args.validation_output), validation_encoded)
    write_csv(Path(args.validation_features_output), validation_features)
    write_csv(Path(args.validation_labels_output), validation_labels)

    print(
        "Prepared XGBoost inputs:",
        f"train={len(train_encoded)}",
        f"validation={len(validation_encoded)}",
        f"age_fill={age_fill:.4f}",
        f"fare_fill={fare_fill:.4f}",
    )


if __name__ == "__main__":
    main()
