#!/usr/bin/env python3
"""Apply the user's per-word answers to the ledger, via bcz.ps1 mark.

The answers file is written only after the user has replied to the choice
questions. Nothing is marked before that.

answers.json format (written by the agent from the user's replies):
  {
    "date": "2026-10-21",
    "answers": {
      "<topic_id>": "know" | "dont_know" | "unsure"
    }
  }

Behaviour:
  know       -> mark known   (stage +1)
  dont_know  -> mark unknown (stage reset to 0, due tomorrow)
  unsure     -> left untouched
  Preview words and words not in plan.json markable_topic_ids are rejected.

Usage:
  python apply_answers.py <day_folder> [--dry-run]
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BCZ = HERE / "bcz.ps1"


def run_mark(day: str, ids, result: str, dry_run: bool) -> str:
    # bcz.ps1 declares -TopicIds as int[]. Build the array literal explicitly
    # so PowerShell gets a real array, not one comma-joined string and not
    # several positional arguments.
    id_list = ",".join(str(int(i)) for i in ids)
    script = (
        f"& '{BCZ}' mark -Date {day} -Result {result} "
        f"-TopicIds @({id_list})"
    )
    cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script]
    if dry_run:
        return "DRY RUN: " + script
    # PowerShell on Windows writes the console codepage (GBK on zh-CN), not
    # UTF-8. Decode leniently so a non-UTF-8 byte cannot crash the run.
    out = subprocess.run(cmd, capture_output=True)
    stdout = out.stdout.decode("gbk", errors="replace")
    stderr = out.stderr.decode("gbk", errors="replace")
    if out.returncode != 0:
        raise RuntimeError(stderr or stdout)
    return stdout


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("day_folder")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    folder = Path(args.day_folder)
    answers_doc = json.loads((folder / "answers.json").read_text(encoding="utf-8"))
    plan = json.loads((folder / "plan.json").read_text(encoding="utf-8"))

    day = answers_doc["date"]
    markable = set(plan["markable_topic_ids"])
    answers = {int(k): v for k, v in answers_doc["answers"].items()}

    valid_values = {"know", "dont_know", "unsure"}
    bad = [k for k, v in answers.items() if v not in valid_values]
    if bad:
        print(f"invalid answer values for ids: {bad}", file=sys.stderr)
        return 1

    not_markable = [k for k in answers if k not in markable]
    if not_markable:
        print(f"ignored (not reviewable today): {not_markable}")
        answers = {k: v for k, v in answers.items() if k in markable}

    know = [k for k, v in answers.items() if v == "know"]
    dont = [k for k, v in answers.items() if v == "dont_know"]
    unsure = [k for k, v in answers.items() if v == "unsure"]

    if know:
        print(run_mark(day, know, "known", args.dry_run))
    if dont:
        print(run_mark(day, dont, "unknown", args.dry_run))
    print(f"unsure (unchanged): {unsure}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
