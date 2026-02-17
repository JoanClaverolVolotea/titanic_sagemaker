#!/usr/bin/env python3
"""
Compute binary classification metrics from prediction scores and labels.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate Titanic prediction scores.")
    parser.add_argument(
        "--predictions",
        default="data/titanic/sagemaker/validation_predictions.csv",
        help="Path to prediction scores file (one score per line or score as first CSV column).",
    )
    parser.add_argument(
        "--labels",
        default="data/titanic/sagemaker/validation_labels.csv",
        help="Path to label file (one label per line or first CSV column).",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.5,
        help="Probability threshold used to turn scores into class predictions.",
    )
    parser.add_argument(
        "--output",
        default="data/titanic/sagemaker/metrics.json",
        help="Output JSON path for computed metrics.",
    )
    return parser.parse_args()


def read_first_column_as_float(path: Path) -> list[float]:
    values: list[float] = []
    with path.open("r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            first = line.split(",")[0].strip()
            values.append(float(first))
    if not values:
        raise ValueError(f"No values found in file: {path}")
    return values


def read_first_column_as_int(path: Path) -> list[int]:
    values: list[int] = []
    with path.open("r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            first = line.split(",")[0].strip()
            values.append(int(float(first)))
    if not values:
        raise ValueError(f"No values found in file: {path}")
    return values


def safe_div(num: float, den: float) -> float:
    return num / den if den else 0.0


def main() -> None:
    args = parse_args()
    predictions_path = Path(args.predictions)
    labels_path = Path(args.labels)
    output_path = Path(args.output)

    scores = read_first_column_as_float(predictions_path)
    labels = read_first_column_as_int(labels_path)

    if len(scores) != len(labels):
        raise ValueError(
            f"Predictions/labels size mismatch: predictions={len(scores)} labels={len(labels)}"
        )

    tp = tn = fp = fn = 0
    for score, label in zip(scores, labels):
        pred = 1 if score >= args.threshold else 0
        if pred == 1 and label == 1:
            tp += 1
        elif pred == 0 and label == 0:
            tn += 1
        elif pred == 1 and label == 0:
            fp += 1
        else:
            fn += 1

    total = len(labels)
    accuracy = safe_div(tp + tn, total)
    precision = safe_div(tp, tp + fp)
    recall = safe_div(tp, tp + fn)
    f1 = safe_div(2 * precision * recall, precision + recall)

    metrics = {
        "total": total,
        "threshold": args.threshold,
        "accuracy": accuracy,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "confusion_matrix": {"tp": tp, "tn": tn, "fp": fp, "fn": fn},
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")

    print(
        "Computed metrics:",
        f"accuracy={accuracy:.4f}",
        f"precision={precision:.4f}",
        f"recall={recall:.4f}",
        f"f1={f1:.4f}",
        f"output={output_path}",
    )


if __name__ == "__main__":
    main()
