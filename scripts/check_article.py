#!/usr/bin/env python3
"""Validate today's article against plan.json.

Layout expected in article.md:
  # Title
  **Series:** ...
  <story paragraphs>            <- STORY
  ---
  ## Today's words                <- VOCAB LIST (may bold target words)
  1. **word** - ...
  **Word count:** N / 650

Checks:
  1. Every target word appears in the STORY (whole word, singular or plural).
  2. Every target word is bolded at least once in the STORY.
  3. The STORY contains no bold text other than target words.
  4. Nothing outside STORY is bold except the VOCAB LIST entries and the
     "Series" / "Word count" lines.
  5. STORY word count <= limit.

Exit 0 = PASS, 1 = FAIL. Prints every problem.

Usage:
  python check_article.py <day_folder> [--max-words 650]
"""
import argparse
import json
import re
import sys
from pathlib import Path

VOCAB_HEADING = "## Today's words"


def load_targets(plan_path: Path):
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    return [w["word"] for w in plan["words"]]


def split_sections(text: str):
    """Return (story, rest, header). Header is the title and the Series line."""
    lines = text.splitlines()
    story_lines, rest_lines, header_lines = [], [], []
    stage = "header"
    for ln in lines:
        if stage == "header":
            # Header = the title line and the metadata line, nothing else.
            if ln.startswith("# ") or ln.startswith("**Series:**") or not ln.strip():
                header_lines.append(ln)
                continue
            stage = "story"
        if stage == "story":
            if ln.strip() == "---":
                stage = "rest"
                continue
            story_lines.append(ln)
        else:
            rest_lines.append(ln)
    return "\n".join(story_lines), "\n".join(rest_lines), "\n".join(header_lines)



def word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)?", text))


def bold_spans(text: str):
    return [m.group(1).strip() for m in re.finditer(r"\*\*([^*]+)\*\*", text)]


def hits(word: str, text: str) -> bool:
    return re.search(r"\b" + re.escape(word) + r"s?\b", text, re.IGNORECASE) is not None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("day_folder")
    ap.add_argument("--max-words", type=int, default=650)
    args = ap.parse_args()

    folder = Path(args.day_folder)
    targets = load_targets(folder / "plan.json")
    text = (folder / "article.md").read_text(encoding="utf-8")
    story, rest, _header = split_sections(text)

    problems = []

    # 1 + 2: targets appear and are bolded in the story.
    for w in targets:
        if not hits(w, story):
            problems.append(f"目标词未出现在正文: {w}")
            continue
        if not any(hits(w, s) for s in bold_spans(story)):
            problems.append(f"目标词未加粗: {w}")

    # 3: no bold non-target spans in the story.
    for span in bold_spans(story):
        if not any(hits(w, span) for w in targets):
            problems.append(f"正文中非目标词被加粗: {span}")

    # 4: outside the story, only the vocab list and the footer may be bold.
    for ln in rest.splitlines():
        if not ln.strip():
            continue
        if ln.strip().startswith("## "):
            continue
        spans = bold_spans(ln)
        if not spans:
            continue
        if ln.lstrip().startswith("**Word count:**"):
            continue
        for span in spans:
            if not any(hits(w, span) for w in targets):
                problems.append(f"词表区域出现非目标词加粗: {span}")

    # 5: story length.
    wc = word_count(story)
    if wc > args.max_words:
        problems.append(f"正文 {wc} 词，超过上限 {args.max_words}")

    print(f"targets={len(targets)} story_words={wc}")
    if problems:
        print("FAIL")
        for p in problems:
            print("  - " + p)
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
