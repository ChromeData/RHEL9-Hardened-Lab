"""Offline tests for the SCAP delta scorer.

No RHEL box, no OpenSCAP. Synthetic XCCDF strings exercise the exact logic that
produces the lab's headline number, so the "before/after score" claim is one you
can trust before you ever boot a VM.

Run:  python -m pytest tests/ -v
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import importlib.util

spec = importlib.util.spec_from_file_location(
    "scap_delta",
    Path(__file__).resolve().parent.parent / "scripts" / "scap-delta.py",
)
scap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scap)


def xccdf(results, ns="http://checklists.nist.gov/xccdf/1.2"):
    """Build a minimal XCCDF result document. `results` is {rule_id: result}."""
    rows = "\n".join(
        f'<rule-result idref="{rid}"><result>{res}</result></rule-result>'
        for rid, res in results.items()
    )
    return ET.fromstring(f'<TestResult xmlns="{ns}">{rows}</TestResult>')


class TestParse:
    def test_reads_rule_results(self):
        r = scap.parse_root(xccdf({"r1": "pass", "r2": "fail"}))
        assert r == {"r1": "pass", "r2": "fail"}

    def test_falls_back_to_1_1_namespace(self):
        # Older SCAP content ships the 1.1 namespace; must not silently read zero.
        r = scap.parse_root(
            xccdf({"r1": "pass"}, ns="http://checklists.nist.gov/xccdf/1.1")
        )
        assert r == {"r1": "pass"}


class TestScoring:
    def test_skips_do_not_count_toward_the_score(self):
        # notapplicable rules must not drag the percentage down.
        c = scap.summarize({"a": "pass", "b": "fail", "c": "notapplicable"})
        passed, total, pct = scap.scored(c)
        assert (passed, total) == (1, 2)
        assert pct == 50.0

    def test_fixed_is_treated_as_pass(self):
        # OpenSCAP reports a remediated rule as "fixed", not "pass".
        c = scap.summarize({"a": "fixed"})
        passed, total, _ = scap.scored(c)
        assert (passed, total) == (1, 1)


class TestDelta:
    def test_counts_controls_that_flipped_to_pass(self):
        before = {"r1": "fail", "r2": "fail", "r3": "pass"}
        after = {"r1": "pass", "r2": "pass", "r3": "pass"}
        d = scap.compute_delta(before, after)
        assert d["delta_controls"] == 2
        assert len(d["fixed"]) == 2

    def test_flags_regressions(self):
        # Hardening that breaks a previously-passing control is the thing you
        # most need surfaced, not buried.
        before = {"r1": "pass"}
        after = {"r1": "fail"}
        d = scap.compute_delta(before, after)
        assert d["regressed"] == ["r1"]
        assert d["delta_controls"] == -1

    def test_percentage_improvement(self):
        before = {"r1": "fail", "r2": "fail"}
        after = {"r1": "pass", "r2": "fail"}
        d = scap.compute_delta(before, after)
        assert d["baseline_pct"] == 0.0
        assert d["hardened_pct"] == 50.0
        assert d["delta_pp"] == 50.0

    def test_clean_run_has_no_regressions(self):
        before = {"r1": "fail", "r2": "fail"}
        after = {"r1": "pass", "r2": "pass"}
        d = scap.compute_delta(before, after)
        assert d["regressed"] == []
