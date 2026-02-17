#!/usr/bin/env python3
"""
Create deterministic train/validation CSV splits from Titanic dataset.
"""

from __future__ import annotations

import argparse
import csv
import random
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare Titanic train/validation splits.")
    parser.add_argument(
        "--input",
        default="data/titanic/raw/titanic.csv",
        help="Input Titanic CSV path.",
    )
    parser.add_argument(
        "--train-output",
        default="data/titanic/splits/train.csv",
        help="Output training CSV path.",
    )
    parser.add_argument(
        "--validation-output",
        default="data/titanic/splits/validation.csv",
        help="Output validation CSV path.",
    )
    parser.add_argument(
        "--validation-ratio",
        type=float,
        default=0.2,
        help="Validation ratio between 0 and 1.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for deterministic splits.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not 0.0 < args.validation_ratio < 1.0:
        raise ValueError("--validation-ratio must be between 0 and 1.")

    input_path = Path(args.input)
    train_path = Path(args.train_output)
    validation_path = Path(args.validation_output)

    train_path.parent.mkdir(parents=True, exist_ok=True)
    validation_path.parent.mkdir(parents=True, exist_ok=True)

    with input_path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        if not fieldnames:
            raise ValueError("Input CSV has no headers.")
        if "Survived" not in fieldnames:
            raise ValueError("Input CSV must include 'Survived' column.")
        rows = list(reader)

    by_target: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_target.setdefault(row["Survived"], []).append(row)

    rng = random.Random(args.seed)
    train_rows: list[dict[str, str]] = []
    validation_rows: list[dict[str, str]] = []

    for target_rows in by_target.values():
        shuffled = list(target_rows)
        rng.shuffle(shuffled)
        val_count = max(1, int(round(len(shuffled) * args.validation_ratio)))
        validation_rows.extend(shuffled[:val_count])
        train_rows.extend(shuffled[val_count:])

    rng.shuffle(train_rows)
    rng.shuffle(validation_rows)

    with train_path.open("w", newline="", encoding="utf-8") as f_train:
        writer = csv.DictWriter(f_train, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(train_rows)

    with validation_path.open("w", newline="", encoding="utf-8") as f_val:
        writer = csv.DictWriter(f_val, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(validation_rows)

    total = len(train_rows) + len(validation_rows)
    print(
        "Created splits:",
        f"train={len(train_rows)}",
        f"validation={len(validation_rows)}",
        f"total={total}",
    )


if __name__ == "__main__":
    main()
