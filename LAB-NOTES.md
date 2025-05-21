# Lab Notes, 03 RHEL 9 Hardened Lab

Running log. Errors, dead ends, fixes, surprises. Dated, newest at the bottom.

---

## Format

```
### YYYY-MM-DD, what I was trying to do

**Expected:**
**Got:**
**Cause:**
**Fix:**
```

---

## Design decisions

### The delta counts scored controls only

`notapplicable` / `notchecked` rules are excluded from the denominator. Including
them makes the percentage meaningless, a box with 300 N/A rules would show a
fake-high score. Pinned by a test.

### Regressions are first-class output

Hardening is not monotonic. `scap-delta.py` prints every `pass -> fail` flip.
A delta that only reports wins hides the controls the hardening broke, which are
exactly the ones worth understanding.

### `fixed` counts as pass

OpenSCAP reports a rule it remediated in-run as `fixed`. Treating that as
anything but a pass understates the result.

---

## Known traps (confirm on first run)

- **Datastream path is distro-specific.** `site.yml` points at
  `ssg-almalinux9-ds.xml`. On genuine RHEL 9 it's `ssg-rhel9-ds.xml`; on Rocky,
  `ssg-rocky9-ds.xml`. Wrong path = zero rules scanned, which looks like a clean
  pass. List profiles first:
  `oscap info /usr/share/xml/scap/ssg/content/ssg-*-ds.xml`
- **The STIG profile is aggressive.** It can lock SSH down enough to drop your
  Vagrant connection. Confirm the ssh_hardening role keeps the vagrant user able
  to reconnect, or the second scan can't run.
- **First scan must run BEFORE the roles.** The Makefile orders `scan-before`
  ahead of `harden` for a reason, run them out of order and the baseline is
  already hardened, so the delta is near zero and the lab looks pointless.

---

## Open questions

- [ ] Actual baseline and hardened percentages on RHEL 9? (The headline numbers.)
- [ ] Which controls regress under the dev-sec roles + STIG profile together?
- [ ] Does the SSH hardening break the Vagrant connection on the default box?
- [ ] How long does a full STIG scan take on a t3.micro-equivalent VM?

---

## Log

### 2026-08-12, testing the scorer before trusting the number

The delta script is the whole deliverable: the before/after percentage is what I'd
quote in an interview. So I wrote tests against synthetic XCCDF before running a
single scan, and two of them changed the implementation:

**Skips must not count.** A box with 300 `notapplicable` rules would score fake-high
if they land in the denominator. Only pass + fail are scored.

**`fixed` is a pass.** OpenSCAP reports a rule it remediated in-run as `fixed`, not
`pass`. Treating that literally would undercount every remediation the scan itself
performed, which is most of them.

Also split `compute_delta()` out as a pure function so the tests exercise the exact
aggregation the report prints, not a parallel reimplementation of it.

Final run: **8 passed** (`findings/test-run.txt`).

---

### 2026-08-12, first real scan, in a container rather than a VM

No hypervisor available on this machine, so I ran the loop against a
`rockylinux/rockylinux:9` container instead of the Vagrant VM: install
openscap-scanner and scap-security-guide, scan, `oscap --remediate`, rescan,
then diff with `scripts/scap-delta.py`.

**It works end to end.** The scorer parsed real OpenSCAP output on the first
try:

```
Baseline :  62 / 71 passed (87.3%)
Hardened :  68 / 71 passed (95.8%)
Delta    : +6 controls (+8.5 pp)
Fixed    : 6
Regressed: 0
```

**And then the number turned out to be nearly meaningless, which is the
finding.**

Full accounting across the 1532 rules in the profile:

```
                    before   after
  pass                  62      68
  fail                   9       3
  notapplicable        412     412
  notselected         1048    1048
  notchecked             1       1
```

Only **71 rules are actually scored**. 412 come back `notapplicable` because a
container has no kernel of its own, no bootloader, no GRUB config, no
partitioning, no auditd, no physical console. Every rule about those has
nothing to evaluate.

So 87.3% to 95.8% is a real measurement of a real scan of the userspace
subset. It is *not* a STIG compliance figure, and quoting it as "my RHEL 9 box
went from 87% to 96% STIG compliant" would be misleading. On a VM the
denominator is several hundred rules and the baseline percentage is far lower,
because the kernel and boot rules are where most of the genuine hardening work
lives.

This is exactly why the skip-handling test exists. If `notapplicable` counted
toward the denominator, this run would have reported roughly 4% and looked
catastrophic instead of narrow.

**Also confirmed a trap I had only predicted:** the datastream on Rocky is
`ssg-rl9-ds.xml`. `ansible/site.yml` assumed `ssg-almalinux9-ds.xml`, which
does not exist on this image. Wrong path means zero rules scanned, which
presents as a clean pass.

**Zero regressions**, but that is not reassuring here. The rules capable of
breaking a running system are mostly the notapplicable ones. Regressions are a
VM-run phenomenon.

Full output in `findings/stig-scan-container-run.txt`.

---

### 2026-08-12, decided regressions get their own output line

Hardening isn't monotonic. Tightening SSH ciphers can break a control that expected
the old set. A delta that only counts wins reads great and hides the damage.

`scap-delta.py` prints every `pass -> fail` flip with a `!` marker and a test asserts
it. If the hardening breaks four controls, I want that on screen, because those four
are the interesting half of the write-up.

**Still to confirm on the VM:** whether the STIG profile plus the dev-sec ssh role
locks SSH down hard enough to drop the Vagrant connection. If it does, the second scan
can't run and the whole loop stalls.

## Session: golden image, and a score that was entirely fake

Remediating a booted host measures the fix, and leaves every machine
unhardened until provisioning reaches it. So the controls now bake into an
image at build time, with the build gated on the resulting SCAP score.

Three failures getting there, and all three were the same mistake wearing
different clothes: testing the thing I wrote instead of the thing being
measured.

**The hardening did nothing and scored 88.7%.** Nine sections of real
controls, and the score was identical to the untouched base image. +0. Of
1532 rules in the profile, 1048 are notselected and 412 notapplicable; the 71
that score are file permissions, ownership, packages and GPG. No PAM stack is
exercised in a container, so pwquality, faillock, login.defs and sudoers
contribute nothing. The whole 88.7% was AlmaLinux's, not mine.

Only caught it by scanning the unmodified base image to compare against. Had I
skipped that, the gate would have shipped protecting a number that could not
move.

Rewrote against scored rules, split the script into SCORED and UNSCORED
sections. 88.7% to 97.2%, +6 controls. Three of six fixes missed on the first
attempt, each a wrong assumption rather than a typo, all written up in
`findings/golden-image-gate.txt`. The best one: `rootfiles_configured` does
not mean "root's init files exist", it wants a tmpfiles.d entry so
systemd-tmpfiles restores them from the rootfiles package, which makes a
hand-edit revert instead of persist.

**Then the positive control passed twice without testing anything.** First
break weakened pwquality and faillock, which are unscored here, so the gate
correctly could not see it. Second break disabled one branch of an if/elif and
the elif re-added the control. Three passes in a row, zero evidence.

Added a verification step that confirms the break landed in the built artifact
before scanning it. That is the step that should have been there from the
start, and it is the same lesson as lab 13's chaos test killing an
already-dead instance.

Working gate: 95.8% against a 96.7% floor, and it names
`use_pam_wheel_for_su` specifically. Both detectors matter, because adding
three controls while breaking one nets out fine on a percentage.

Two rules stay failing on purpose. The profile wants `FIPS:STIG` and
AlmaLinux does not ship `STIG.pmod` (RHEL-only), and the container runtime
overwrites `/etc/resolv.conf`. Real FIPS also needs `fips=1` at boot, which a
container cannot provide, so passing that rule would not have meant a
FIPS-validated image anyway.

---
