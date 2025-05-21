#!/usr/bin/env python3
"""Gate a golden image build on its SCAP score.

WHY THIS EXISTS

Building a hardened image and publishing it is only half a control. Nothing in
that pipeline notices when a control stops working. A base image changes, a
package moves a config file, someone comments out a line to unblock a build,
and the image still builds, still publishes, still gets deployed. The score
drops and no one is told, because nothing was watching the score.

So this compares a fresh scan against a committed baseline and FAILS THE BUILD
on regression. The baseline lives in the repo, which means raising it is a
reviewable diff and lowering it is one somebody has to justify in a PR.

TWO WAYS TO FAIL, and they are different problems:

  1. The overall pass rate dropped below the floor. Broad erosion.
  2. A specific control that used to pass now fails. This one matters even if
     the aggregate still clears the floor, because "we hardened more things
     and quietly broke SSH" nets out fine on a percentage and is not fine.

Reuses the parser in scap-delta.py rather than reimplementing it, so both the
VM path and the image path score identically. Two scorers that disagree is a
worse problem than either being slightly wrong.
"""

import argparse
import importlib.util
import json
import os
import sys

# scap-delta.py has a hyphen in the name, so it cannot be imported normally.
# Renaming it would break the Makefile and every reference in the README, and
# a copy of the parser would be worse: two scorers that drift apart is a
# harder problem than an awkward import.
_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "scap_delta", os.path.join(_HERE, "scap-delta.py")
)
scap_delta = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(scap_delta)

parse = scap_delta.parse
summarize = scap_delta.summarize
scored = scap_delta.scored
PASS = scap_delta.PASS
FAIL = scap_delta.FAIL


def evaluate(results, baseline, tolerance):
    """Compare a scan against the committed baseline.

    Returned as data rather than printed, so the tests can assert on it
    without parsing stdout. Same reason compute_delta is shaped this way.
    """
    passed, total, pct = scored(summarize(results))

    floor = baseline["min_pass_pct"] - tolerance
    known_pass = set(baseline.get("passing_rules", []))

    # A rule the baseline recorded as passing that now reports a failure.
    # Absent from this scan is NOT counted as a regression: content updates
    # rename and retire rules, and treating that as a break would make the
    # gate cry wolf every time the SSG package moves.
    regressed = sorted(
        r for r in known_pass
        if r in results and results[r] in FAIL
    )

    newly_passing = sorted(
        r for r, v in results.items()
        if v in PASS and r not in known_pass
    )

    return {
        "pass_count": passed,
        "total_scored": total,
        "pass_pct": pct,
        "floor": floor,
        "below_floor": pct < floor,
        "regressed": regressed,
        "newly_passing": newly_passing,
        "ok": pct >= floor and not regressed,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("results", help="XCCDF results XML from the image scan")
    ap.add_argument("--baseline", default="image/baseline.json")
    ap.add_argument("--tolerance", type=float, default=0.5,
                    help="percentage points of slack, for scanner content drift")
    ap.add_argument("--update-baseline", action="store_true",
                    help="rewrite the baseline from this scan. Intentional, reviewable, "
                         "and never something CI does on its own.")
    args = ap.parse_args()

    results = parse(args.results)
    if not results:
        # An empty parse is the failure mode this whole portfolio keeps
        # tripping over: a scanner that read nothing looks exactly like a
        # system with no findings. Refuse rather than report a clean gate.
        sys.exit("FAIL: parsed 0 rule-results. The scan did not run, or the "
                 "results file is not XCCDF. Refusing to report a passing gate "
                 "on an empty scan.")

    if args.update_baseline:
        passed, total, pct = scored(summarize(results))
        new = {
            "min_pass_pct": round(pct, 1),
            "scored_rules": total,
            "passing_rules": sorted(r for r, v in results.items() if v in PASS),
            "note": "Container-applicable subset only. Not comparable to a VM scan.",
        }
        with open(args.baseline, "w", encoding="utf-8") as fh:
            json.dump(new, fh, indent=2)
            fh.write("\n")
        print(f"baseline written: {passed}/{total} ({pct:.1f}%) -> {args.baseline}")
        return 0

    with open(args.baseline, encoding="utf-8") as fh:
        baseline = json.load(fh)

    v = evaluate(results, baseline, args.tolerance)

    print(f"scanned  : {v['pass_count']}/{v['total_scored']} passed ({v['pass_pct']:.1f}%)")
    print(f"floor    : {v['floor']:.1f}%  (baseline {baseline['min_pass_pct']:.1f}% "
          f"minus {args.tolerance} pp tolerance)")

    if v["newly_passing"]:
        print(f"improved : {len(v['newly_passing'])} controls now passing that did not before")

    if v["below_floor"]:
        print(f"\nFAIL: pass rate {v['pass_pct']:.1f}% is below the floor of {v['floor']:.1f}%")

    if v["regressed"]:
        print(f"\nFAIL: {len(v['regressed'])} control(s) that passed in the baseline now fail:")
        for r in v["regressed"]:
            print(f"  ! {r}")

    if not v["ok"]:
        print("\nThe image built. It is not allowed to ship.")
        return 1

    print("\nPASS: no regression against the committed baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
