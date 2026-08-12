#!/usr/bin/env python3
"""Compute the pass-rate delta between two OpenSCAP XCCDF result files.

Parses the <rule-result> entries from before.xml and after.xml and reports how
many controls moved from fail to pass. The number this prints is the lab's
headline result — put it in the README.
"""

import sys
import xml.etree.ElementTree as ET
from collections import Counter

NS = {"x": "http://checklists.nist.gov/xccdf/1.2"}
# Older content uses the 1.1 namespace; try both.
NS_ALT = {"x": "http://checklists.nist.gov/xccdf/1.1"}

PASS = {"pass", "fixed"}
FAIL = {"fail", "error"}
SKIP = {"notapplicable", "notchecked", "notselected", "informational", "unknown"}


def parse(path):
    tree = ET.parse(path)
    root = tree.getroot()
    ns = NS if root.findall(".//x:rule-result", NS) else NS_ALT
    results = {}
    for rr in root.findall(".//x:rule-result", ns):
        rid = rr.get("idref", "?")
        res = rr.find("x:result", ns)
        results[rid] = res.text if res is not None else "unknown"
    return results


def summarize(results):
    c = Counter()
    for r in results.values():
        if r in PASS:
            c["pass"] += 1
        elif r in FAIL:
            c["fail"] += 1
        else:
            c["skip"] += 1
    return c


def scored(c):
    total = c["pass"] + c["fail"]  # skips don't count toward the score
    return c["pass"], total, (100 * c["pass"] / total if total else 0)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: scap-delta.py before.xml after.xml")

    before, after = parse(sys.argv[1]), parse(sys.argv[2])
    bc, ac = summarize(before), summarize(after)
    bp, bt, bpct = scored(bc)
    ap, at, apct = scored(ac)

    print(f"Baseline : {bp:3} / {bt} passed ({bpct:.1f}%)")
    print(f"Hardened : {ap:3} / {at} passed ({apct:.1f}%)")
    print(f"Delta    : {ap - bp:+d} controls ({apct - bpct:+.1f} pp)")

    # Controls that flipped fail -> pass, and any that regressed pass -> fail.
    fixed = [r for r in before if before[r] in FAIL and after.get(r) in PASS]
    regressed = [r for r in before if before[r] in PASS and after.get(r) in FAIL]
    print(f"\nFixed    : {len(fixed)} controls")
    print(f"Regressed: {len(regressed)} controls  <- investigate every one of these")
    for r in regressed:
        print(f"  ! {r}")


if __name__ == "__main__":
    main()
