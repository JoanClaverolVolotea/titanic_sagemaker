#!/usr/bin/env python3
"""Evaluate Titanic XGBoost model and emit SageMaker pipeline-compatible evaluation.json."""

from __future__ import annotations

import argparse
import csv
import json
import tarfile
from pathlib import Path

import xgboost as xgb


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-artifact", default="/opt/ml/processing/model/model.tar.gz")
    parser.add_argument("--validation", default="/opt/ml/processing/validation/validation_xgb.csv")
    parser.add_argument("--accuracy-threshold", type=float, default=0.78)
    parser.add_argument("--output", default="/opt/ml/processing/evaluation/evaluation.json")
    return parser.parse_args()


def read_validation(path: Path) -> tuple[list[int], list[list[float]]]:
    labels: list[int] = []
    features: list[list[float]] = []
    with path.open("r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            labels.append(int(float(row[0])))
            features.append([float(v) for v in row[1:]])
    if not labels:
        raise ValueError(f"No validation rows in {path}")
    return labels, features


def safe_div(num: float, den: float) -> float:
    return num / den if den else 0.0


def ensure_model_file(model_artifact: Path) -> Path:
    if model_artifact.is_file() and model_artifact.suffix == ".json":
        return model_artifact

    extract_dir = Path("/tmp/model_extract")
    extract_dir.mkdir(parents=True, exist_ok=True)

    with tarfile.open(model_artifact, "r:gz") as tar:
        tar.extractall(extract_dir)

    # Built-in XGBoost commonly stores model as xgboost-model
    candidates = [
        extract_dir / "xgboost-model",
        extract_dir / "model.json",
        extract_dir / "xgboost-model.json",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate

    found = sorted(str(p) for p in extract_dir.rglob("*") if p.is_file())
    raise FileNotFoundError(f"Could not find model file in extracted artifact. Found: {found}")


def main() -> None:
    args = parse_args()

    model_path = ensure_model_file(Path(args.model_artifact))
    labels, features = read_validation(Path(args.validation))

    dmatrix = xgb.DMatrix(features)
    booster = xgb.Booster()
    booster.load_model(str(model_path))

    scores = booster.predict(dmatrix)

    tp = tn = fp = fn = 0
    for score, label in zip(scores, labels):
        pred = 1 if float(score) >= 0.5 else 0
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

    payload = {
        "metrics": {
            "accuracy": accuracy,
            "precision": precision,
            "recall": recall,
            "f1": f1,
        },
        "thresholds": {
            "accuracy_threshold": args.accuracy_threshold,
            "passed": accuracy >= args.accuracy_threshold,
        },
        "confusion_matrix": {
            "tp": tp,
            "tn": tn,
            "fp": fp,
            "fn": fn,
        },
        "samples": total,
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    print(f"Evaluation written to {output_path}")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
