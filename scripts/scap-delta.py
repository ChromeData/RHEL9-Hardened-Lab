#!/usr/bin/env python3
"""Compute the pass-rate delta between two OpenSCAP XCCDF result files.

Parses the <rule-result> entries from before.xml and after.xml and reports how
many controls moved from fail to pass. The number this prints is the lab's
headline result, put it in the README.
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


def parse_root(root):
    """Extract {rule_id: result} from an XCCDF root element. Split out from
    parse() so tests can feed synthetic XML without writing temp files, and so
    the 1.1/1.2 namespace fallback is exercised directly."""
    ns = NS if root.findall(".//x:rule-result", NS) else NS_ALT
    results = {}
    for rr in root.findall(".//x:rule-result", ns):
        rid = rr.get("idref", "?")
        res = rr.find("x:result", ns)
        results[rid] = res.text if res is not None else "unknown"
    return results


def parse(path):
    return parse_root(ET.parse(path).getroot())


def compute_delta(before, after):
    """The scored comparison, as data rather than printed text. This is the
    function the headline number comes from, so it is the function under test."""
    bp, bt, bpct = scored(summarize(before))
    ap, at, apct = scored(summarize(after))
    fixed = [r for r in before if before[r] in FAIL and after.get(r) in PASS]
    regressed = [r for r in before if before[r] in PASS and after.get(r) in FAIL]
    return {
        "baseline_pass": bp, "baseline_total": bt, "baseline_pct": bpct,
        "hardened_pass": ap, "hardened_total": at, "hardened_pct": apct,
        "delta_controls": ap - bp, "delta_pp": apct - bpct,
        "fixed": fixed, "regressed": regressed,
    }


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
    d = compute_delta(before, after)

    print(f"Baseline : {d['baseline_pass']:3} / {d['baseline_total']} passed ({d['baseline_pct']:.1f}%)")
    print(f"Hardened : {d['hardened_pass']:3} / {d['hardened_total']} passed ({d['hardened_pct']:.1f}%)")
    print(f"Delta    : {d['delta_controls']:+d} controls ({d['delta_pp']:+.1f} pp)")

    print(f"\nFixed    : {len(d['fixed'])} controls")
    print(f"Regressed: {len(d['regressed'])} controls  <- investigate every one of these")
    for r in d["regressed"]:
        print(f"  ! {r}")


if __name__ == "__main__":
    main()
