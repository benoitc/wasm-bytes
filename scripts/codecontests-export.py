"""Exports the CodeContests problems that could fit a simple integer function.

    python codecontests-export.py OUT.jsonl SPLIT=FILE.parquet [SPLIT=FILE.parquet ...]

Reads the given parquet files of the deepmind/code_contests dataset and writes
one JSON object per line for every problem whose tests all take one or two
integers as input and print one integer. `bin/wasm-bytes prepare codecontests`
reads that file, checks that every value fits in 32 bits, and builds the
cases. Nothing here decides what a right answer is: the tests come out as the
dataset has them.

Needs pyarrow.
"""
import json
import os
import re
import sys

import pyarrow.parquet as pq

INTEGER = re.compile(r"^[+-]?[0-9]+$")
COLUMNS = ["name", "description", "source", "difficulty", "cf_contest_id", "cf_index",
           "public_tests", "private_tests", "generated_tests"]


def tokens(text):
    return text.split()


def fits(tests):
    """The number of integers every input holds, when every input is one or
    two integers, always the same count, and every output is one integer;
    otherwise why not."""
    counts = set()
    for given, printed in zip(tests["input"], tests["output"]):
        inp, out = tokens(given), tokens(printed)
        if not 1 <= len(inp) <= 2 or not all(INTEGER.match(t) for t in inp):
            return None, "an input is not one or two integers"
        if len(out) != 1 or not INTEGER.match(out[0]):
            return None, "an output is not one integer"
        counts.add(len(inp))
    if len(counts) != 1:
        return None, "the inputs do not all hold the same number of integers"
    return counts.pop(), None


def main(out_path, sources):
    examined, written, skipped = 0, 0, {}
    with open(out_path, "w", encoding="utf-8") as out:
        for source in sources:
            split, path = source.split("=", 1)
            table = pq.read_table(path, columns=COLUMNS)
            for row, problem in enumerate(table.to_pylist()):
                examined += 1
                every = {"input": [], "output": []}
                for key in ("public_tests", "private_tests", "generated_tests"):
                    every["input"] += problem[key]["input"]
                    every["output"] += problem[key]["output"]
                if not every["input"]:
                    why = "it has no tests"
                    skipped[why] = skipped.get(why, 0) + 1
                    continue
                arity, why = fits(every)
                if arity is None:
                    skipped[why] = skipped.get(why, 0) + 1
                    continue
                problem.update({"split": split, "row": row, "arity": arity})
                out.write(json.dumps(problem, ensure_ascii=False) + "\n")
                written += 1
        # The last line counts every problem read, for the selection report.
        out.write(json.dumps({"_summary": {"examined": examined, "candidates": written,
                                           "skipped": skipped,
                                           "files": [os.path.basename(s.split("=", 1)[1])
                                                     for s in sources]}}) + "\n")
    print(examined, "problems examined,", written, "candidates")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
