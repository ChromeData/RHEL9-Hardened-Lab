# Lab 03 — Self-Building Hardened RHEL 9 Lab

[![tests](https://github.com/ChromeData/RHEL9-Hardened-Lab/actions/workflows/tests.yml/badge.svg)](https://github.com/ChromeData/RHEL9-Hardened-Lab/actions/workflows/tests.yml)

**A VM that hardens itself and proves it worked. Boot a RHEL 9 box, scan it
against the DISA STIG, apply fixes as code, scan again — the result is a
before/after number, not a claim.**

| | |
|---|---|
| **Domains** | Linux (RHEL 9 · RHCSA/RHCE-adjacent) · security |
| **Built on** | [ComplianceAsCode/content](https://github.com/ComplianceAsCode/content) (BSD-3) · [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening) (Apache-2.0) · OpenSCAP |
| **Cost** | $0 (local VM) · **Runtime** ~3 hours |
| **Status** | 🟡 Built, validated, not yet run |

---

## The point

Almost every RHCSA repo on GitHub is a folder of notes. Notes don't prove you can
harden a box. This does the loop that proves it:

1. **Stand up** an unhardened RHEL 9 host (Vagrant).
2. **Scan** it against the STIG with OpenSCAP → a failing baseline score.
3. **Harden** with Ansible (dev-sec roles).
4. **Scan again** → the improved score.
5. **Diff** the two → the number that is the whole point.

The artifact is the delta. "I hardened Linux" is a sentence anyone can write.
"I moved it from 41% to 89% STIG-compliant and here are the four controls that
regressed and why" is evidence.

## The measurement is tested

[`scripts/scap-delta.py`](./scripts/scap-delta.py) parses two OpenSCAP result
files and computes the delta. That's where the headline number comes from, so it
has **8 offline unit tests** on synthetic XCCDF — no VM needed:

- skips (`notapplicable`) don't drag the percentage down
- a remediated rule reports as `fixed`, not `pass` — counted correctly
- both the 1.1 and 1.2 XCCDF namespaces parse
- **regressions are surfaced, not buried** — hardening that breaks a
  previously-passing control is the thing you most need to see

```bash
python -m pytest tests/ -v
```

CI runs the tests plus an Ansible syntax check on every push.

## Why regressions matter

Hardening isn't monotonic. Turning on a STIG control can break a different one —
tighten SSH ciphers and something that expected the old set starts failing. A
delta that only counts wins is lying to you. `scap-delta.py` prints every
`pass → fail` flip with a `!`, because those are the ones you write about.

## What I didn't build

The hardening roles are dev-sec's; the SCAP content is ComplianceAsCode's. The
measurable before/after workflow, the delta scorer, the tests, and the
orchestration are mine.

---

## Running it

```bash
make up            # provision the RHEL 9 VM
make scan-before   # baseline scan (unhardened) -> reports/before.xml
make harden        # apply the dev-sec roles
make scan-after    # second scan -> reports/after.xml
make delta         # the number
make destroy
```

Needs Vagrant + a libvirt/VirtualBox provider, and Python 3 on the host for the
delta.

## Findings

`reports/` and the printed delta are the output. [LAB-NOTES.md](./LAB-NOTES.md) is
the log.

## License

Lab code: MIT ([LICENSE](./LICENSE)). Upstream content keeps BSD-3 / Apache-2.0,
credited above.
