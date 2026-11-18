#!/usr/bin/env python3
"""Export the ledger to an Excel sheet the user can fill in.

One row per active word. The user fills the 状态 column with a dropdown:
  认识 / 不认识 / 不确定 / (blank = no answer, nothing changes)

topic_id is kept in column A so the import can match rows by id, never by
row position. Columns B-G are read-only context. Only 状态 is meant to be
edited.

Usage:
  <venv python> export_ledger_xlsx.py <out.xlsx>
"""
import json
import sys
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.worksheet.datavalidation import DataValidation

DATA_ROOT = Path.home() / "baicizhan-daily"
LEDGER = DATA_ROOT / "ledger.json"

HEADERS = ["topic_id", "单词", "释义", "收藏日期", "stage", "下次复习", "状态", "上次结果"]
STATUS_CHOICES = ['"认识,不认识,不确定"']


def load_today_ids():
    """topic_ids from the latest plan.json, i.e. the words to fill in today."""
    days = sorted(p for p in DATA_ROOT.iterdir() if p.is_dir() and (p / "plan.json").exists())
    if not days:
        return set(), ""
    plan = json.loads((days[-1] / "plan.json").read_text(encoding="utf-8"))
    return set(plan.get("markable_topic_ids", [])), days[-1].name


def load_active_words(today_ids):
    doc = json.loads(LEDGER.read_text(encoding="utf-8"))
    words = [w for w in doc["words"] if not w.get("removed")]
    # Today's words first (the ones to fill in), then the rest, oldest due first.
    words.sort(key=lambda w: (
        0 if w["topic_id"] in today_ids else 1,
        w["due_date"], w["stage"], w["created_at"],
    ))
    return words


def last_result(w):
    hist = w.get("history") or []
    return hist[-1]["result"] if hist else ""


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: export_ledger_xlsx.py <out.xlsx>", file=sys.stderr)
        return 1
    out = Path(sys.argv[1])

    wb = Workbook()
    ws = wb.active
    ws.title = "台账"

    ws.append(HEADERS)
    header_fill = PatternFill("solid", fgColor="DDEBF7")
    for cell in ws[1]:
        cell.font = Font(bold=True)
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center")

    # 状态 is the only editable column; mark it visually.
    input_fill = PatternFill("solid", fgColor="FFF2CC")
    today_fill = PatternFill("solid", fgColor="C6EFCE")
    today_ids, today_day = load_today_ids()
    today_count = 0
    for w in load_active_words(today_ids):
        ws.append([
            w["topic_id"],
            w["word"],
            w.get("mean", ""),
            w.get("collected_date", ""),
            w["stage"],
            w["due_date"],
            "",
            last_result(w),
        ])
        row = ws.max_row
        ws.cell(row=row, column=7).fill = input_fill
        if w["topic_id"] in today_ids:
            today_count += 1
            # Today's words: green row so they stand out from the rest.
            for col in range(1, len(HEADERS) + 1):
                if col != 7:
                    ws.cell(row=row, column=col).fill = today_fill
            ws.cell(row=row, column=2).font = Font(bold=True)

    print(f"today ({today_day}): {today_count} words highlighted green at the top")

    last = ws.max_row
    dv = DataValidation(type="list", formula1=STATUS_CHOICES[0], allow_blank=True)
    dv.error = "请从下拉列表选择：认识 / 不认识 / 不确定"
    dv.errorTitle = "状态无效"
    dv.add(f"G2:G{last}")
    ws.add_data_validation(dv)

    widths = {"A": 12, "B": 22, "C": 40, "D": 14, "E": 8, "F": 14, "G": 12, "H": 12}
    for col, width in widths.items():
        ws.column_dimensions[col].width = width
    ws.freeze_panes = "A2"

    # Instructions sit on a separate sheet so the main sheet stays clean.
    help_ws = wb.create_sheet("说明")
    help_ws.append(["使用方法"])
    help_ws["A1"].font = Font(bold=True)
    help_ws.append(["1. 绿色的行是今天要填的词（前 12 行），只在「状态」列（黄色）填写：认识 / 不认识 / 不确定。"])
    help_ws.append(["2. 其他没有绿色的词今天不用管，留空即可，导入时会被忽略。"])
    help_ws.append(["3. 不要修改 topic_id、stage、下次复习 等列，它们只用于显示。"])
    help_ws.append(["4. 填好后保存文件，并告诉我，我会读取并写入台账。"])
    help_ws.append(["5. 写入成功后，「状态」列会被清空，避免下次重复标记。"])
    help_ws.column_dimensions["A"].width = 70

    out.parent.mkdir(parents=True, exist_ok=True)
    wb.save(out)
    print(f"exported {last - 1} words -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
