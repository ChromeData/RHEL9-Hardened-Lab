# Lab 03 — Self-Building Hardened RHEL 9 Lab

**A Vagrant + Ansible environment that provisions a RHEL 9 host, measures its
CIS/STIG compliance, applies remediation as code, and measures again — so the
hardening is proven by a before/after score, not asserted.**

| | |
|---|---|
| **Domains** | Linux (RHEL 9 · RHCSA/RHCE-adjacent) · security |
| **Built on** | [ComplianceAsCode/content](https://github.com/ComplianceAsCode/content) (BSD-3) · [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening) (Apache-2.0) · [OpenSCAP](https://github.com/OpenSCAP/openscap) |
| **Runtime** | ~3 hours · $0 (runs locally in a VM) |
| **Status** | 🟡 In progress |

---

## Why this lab exists

Almost every RHCSA repo on GitHub is a folder of notes. Notes do not prove you can
harden a box. A lab that stands up a real RHEL 9 host, scans it against the DISA
STIG with OpenSCAP, shows a failing baseline score, applies remediation with
Ansible, and re-scans to show the improved score — that proves it, and it produces
an artifact (the score delta) you can point at.

This also sits one level above cert prep: it's the compliance-as-code workflow real
platform teams run, using the actual upstream content Red Hat's own STIG roles are
generated from.

## What I built

- A **Vagrantfile** that boots a RHEL 9 (or Rocky/Alma 9) box reproducibly.
- An **Ansible playbook** that: installs OpenSCAP + the SCAP Security Guide, runs a
  baseline scan, applies the dev-sec hardening collection, and re-scans.
- A **scan wrapper** that captures both HTML and machine-readable results and
  computes the pass-rate delta.
- A **reports/** convention for committing the before/after so the improvement is
  visible in the repo history.

## What I did not build

OpenSCAP, the SCAP Security Guide content (ComplianceAsCode), and the dev-sec
hardening roles are all upstream. My work is the environment, the orchestration,
the measurement harness, and the analysis of which controls remediated cleanly and
which needed manual intervention.

---

## Running it

### Prerequisites

```bash
vagrant   >= 2.4
virtualbox or libvirt
ansible   >= 2.16
```

A RHEL 9 box needs a Red Hat Developer subscription; the playbook also works
against `generic/rocky9` or `almalinux/9` with no subscription, which is the
recommended default for a public lab.

### Setup and run

```bash
make up          # vagrant up + install collections
make scan-before # OpenSCAP baseline scan -> reports/before.html + .xml
make harden      # apply dev-sec hardening + selected STIG remediations
make scan-after  # re-scan -> reports/after.html + .xml
make delta       # compute and print the pass-rate improvement
```

### Teardown

```bash
make destroy     # vagrant destroy -f
```

---

## The measurement

`make delta` parses both ARF/XML results and prints something like:

```
STIG baseline : 143 / 312 passed (45.8%)
After hardening: 271 / 312 passed (86.9%)
Delta         : +128 controls (+41.1 pp)
```

Commit `reports/before.html` and `reports/after.html`. That delta, visible in the
repo, is the whole point — it is evidence in a form a reviewer can open.

## Findings

Worth documenting:

| Control area | Baseline | After | Notes |
|--------------|----------|-------|-------|
| SSH hardening | | | |
| Password / PAM policy | | | |
| Audit (auditd) rules | | | |
| Filesystem mount options | | | |
| SELinux enforcement | | | |

The analysis interviewers care about:
- Which controls did **not** remediate automatically, and why?
- Did any remediation break functionality (e.g. SSH lockout, sudo)? How did you
  recover? (This is where LAB-NOTES earns its keep.)
- Which STIG findings are false positives against a minimal Vagrant box?

## What broke

See [LAB-NOTES.md](./LAB-NOTES.md).

## What I would do differently

_End._
