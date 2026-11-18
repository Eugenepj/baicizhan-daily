#!/usr/bin/env python3
"""Read the user's filled-in ledger Excel and apply it to the ledger.

Reads the "状态" column of the "台账" sheet, matches rows by topic_id,
writes <day_folder>/answers.json and then calls apply_answers.py, which
runs bcz.ps1 mark. Only words that were reviewable in <day_folder>/plan.json
are applied; other filled rows are reported and ignored.

Status mapping:
  认识   -> know       (mark known,   stage +1)
  不认识 -> dont_know  (mark unknown, stage 0, due tomorrow)
  不确定 / blank -> unsure (untouched)

Usage:
  python import_ledger_xlsx.py <ledger.xlsx> <day_folder> [--dry-run]
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

import openpyxl

HERE = Path(__file__).resolve().parent
APPLY = HERE / "apply_answers.py"
LEDGER_SHEET = "台账"
STATUS_MAP = {"认识": "know", "不认识": "dont_know", "不确定": "unsure"}


def read_statuses(xlsx: Path):
    wb = openpyxl.load_workbook(xlsx, data_only=True)
    if LEDGER_SHEET not in wb.sheetnames:
        raise RuntimeError(f"sheet '{LEDGER_SHEET}' not found in {xlsx}")
    ws = wb[LEDGER_SHEET]
    header = [c.value for c in ws[1]]
    try:
        id_col = header.index("topic_id")
        st_col = header.index("状态")
    except ValueError as e:
        raise RuntimeError(f"missing column: {e}")

    seen = {}
    problems = []
    for row in ws.iter_rows(min_row=2, values_only=True):
        tid = row[id_col]
        if tid is None:
            continue
        raw = row[st_col]
        status = str(raw).strip() if raw is not None else ""
        if not status:
            continue
        if status not in STATUS_MAP:
            problems.append(f"topic_id {tid}: 非法状态 '{status}'")
            continue
        tid = int(tid)
        if tid in seen:
            problems.append(f"topic_id {tid}: 重复出现")
            continue
        seen[tid] = STATUS_MAP[status]
    return seen, problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("xlsx")
    ap.add_argument("day_folder")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    xlsx = Path(args.xlsx)
    folder = Path(args.day_folder)
    plan = json.loads((folder / "plan.json").read_text(encoding="utf-8"))
    day = folder.name

    try:
        answers, problems = read_statuses(xlsx)
    except PermissionError:
        print("无法读取 Excel：文件可能正在被打开，请先关闭后重试。", file=sys.stderr)
        return 3

    if problems:
        print("发现问题，已中止导入（请修正 Excel 后重试）：", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        return 1

    markable = set(plan["markable_topic_ids"])
    ignored = [k for k in answers if k not in markable]
    if ignored:
        print(f"忽略（不在本次可复习范围内）: {ignored}")
    answers = {k: v for k, v in answers.items() if k in markable}

    counts = {}
    for v in answers.values():
        counts[v] = counts.get(v, 0) + 1
    print(f"待应用: {counts or '无'}")

    if not answers:
        print("没有需要更新的词。")
        return 0

    payload = {"date": day, "answers": {str(k): v for k, v in answers.items()}}
    (folder / "answers.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    cmd = [sys.executable, str(APPLY), str(folder)]
    if args.dry_run:
        cmd.append("--dry-run")
    res = subprocess.run(cmd, capture_output=True)
    print(res.stdout.decode("gbk", errors="replace"))
    if res.returncode != 0:
        print(res.stderr.decode("gbk", errors="replace"), file=sys.stderr)
        return res.returncode

    if not args.dry_run:
        # Clear the 状态 column so the same answers are never applied twice.
        try:
            clear_status_column(xlsx)
            print("已清空 Excel 的状态列，请重新导出最新台账。")
        except PermissionError:
            print("警告：台账已更新，但 Excel 文件被占用，无法清空状态列。"
                  "请关闭 Excel 后重新导出，否则下次导入会重复应用。", file=sys.stderr)
            return 4
    return 0


def clear_status_column(xlsx: Path):
    wb = openpyxl.load_workbook(xlsx)
    ws = wb[LEDGER_SHEET]
    header = [c.value for c in ws[1]]
    st_col = header.index("状态") + 1
    for r in range(2, ws.max_row + 1):
        ws.cell(row=r, column=st_col).value = None
    wb.save(xlsx)


if __name__ == "__main__":
    sys.exit(main())
