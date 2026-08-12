# Lab Notes — 03 RHEL 9 Hardened Lab

Running log. Errors, dead ends, fixes, surprises. Dated, newest at the bottom.

---

## Format

```
### YYYY-MM-DD — what I was trying to do

**Expected:**
**Got:**
**Cause:**
**Fix:**
```

---

## Design decisions

### The delta counts scored controls only

`notapplicable` / `notchecked` rules are excluded from the denominator. Including
them makes the percentage meaningless — a box with 300 N/A rules would show a
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
  ahead of `harden` for a reason — run them out of order and the baseline is
  already hardened, so the delta is near zero and the lab looks pointless.

---

## Open questions

- [ ] Actual baseline and hardened percentages on RHEL 9? (The headline numbers.)
- [ ] Which controls regress under the dev-sec roles + STIG profile together?
- [ ] Does the SSH hardening break the Vagrant connection on the default box?
- [ ] How long does a full STIG scan take on a t3.micro-equivalent VM?

---

## Log

_(first entry goes here on the first real run)_
