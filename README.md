# Lab 03: Self Building Hardened RHEL 9 Lab

[![tests](https://github.com/ChromeData/RHEL9-Hardened-Lab/actions/workflows/tests.yml/badge.svg)](https://github.com/ChromeData/RHEL9-Hardened-Lab/actions/workflows/tests.yml)

**A VM that hardens itself and proves it worked. Boot a RHEL 9 box, scan it against the DISA STIG, apply fixes as code, scan again. The result is a before and after number, not a claim.**

| | |
|---|---|
| **Domains** | Linux (RHEL 9, RHCSA/RHCE adjacent), security |
| **Built on** | [ComplianceAsCode/content](https://github.com/ComplianceAsCode/content), [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening), OpenSCAP |
| **Cost** | $0 (local VM). **Runtime** ~3 hours |
| **Status** | Built, validated, not yet run |

## Situation

Almost every RHCSA repo on GitHub is a folder of notes. Notes do not prove you can harden a box.

## Task

Run the full loop that does prove it, and produce evidence at the end.

## Action

Five steps: stand up an unhardened RHEL 9 host with Vagrant, scan it against the STIG with OpenSCAP for a failing baseline, harden it with Ansible, scan again, and diff the two.

The diff is the point. "I hardened Linux" is a sentence anyone can write. "I moved it from 41% to 89% STIG compliant and here are the four controls that broke and why" is evidence.

The scorer that produces the number ([scripts/scap-delta.py](./scripts/scap-delta.py)) has 8 offline tests on fake SCAP files, so the headline number is trustworthy before I ever boot a VM. It handles skips correctly, counts a remediated rule as a pass, reads both SCAP formats, and surfaces regressions.

## Result

8 tests pass, plus an Ansible syntax check in CI. Regressions get a marker, because hardening is not one directional. Turning on one control can break another, and a diff that only counts wins is lying to you.

## What I did not build

The hardening roles are dev-sec's and the SCAP content is ComplianceAsCode's. The measurable workflow, the scorer, and the tests are mine.

## Run it

```bash
make up            # provision the RHEL 9 VM
make scan-before   # baseline scan
make harden        # apply the roles
make scan-after    # second scan
make delta         # the number
make destroy
```

Needs Vagrant with a libvirt or VirtualBox provider, and Python 3 on the host.

## Findings

`reports/` and the printed delta are the output. [LAB-NOTES.md](./LAB-NOTES.md) is the log.

## License

Lab code: MIT ([LICENSE](./LICENSE)). Upstream content keeps its licenses, credited above.
