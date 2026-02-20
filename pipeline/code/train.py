#!/usr/bin/env python3
"""Optional custom training script placeholder for phase 03.

The canonical workflow in this phase uses SageMaker built-in XGBoost, so this script is
kept for repository completeness and future custom container/script mode experiments.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--train", default="/opt/ml/input/data/train/train_xgb.csv")
    parser.add_argument("--validation", default="/opt/ml/input/data/validation/validation_xgb.csv")
    parser.add_argument("--output-dir", default="/opt/ml/model")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    Path(args.output_dir).mkdir(parents=True, exist_ok=True)
    print(
        "train.py is present for completeness. "
        "Phase 03 uses built-in XGBoost training job by default.",
        f"train={args.train}",
        f"validation={args.validation}",
    )


if __name__ == "__main__":
    main()
