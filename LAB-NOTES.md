# Lab Notes — RHEL 9 Hardened Lab

> Running log, newest first.

---

## Known traps (pre-seeded — confirm or replace)

### SSH hardening can lock you out of Vagrant

`ssh_hardening` tightens `sshd_config` — ciphers, MACs, `AllowUsers`, and possibly
`PermitRootLogin`. Vagrant's SSH can break mid-play. If `vagrant ssh` stops working
after `make harden`, that is the lab working as intended. Recover via the provider
console (`virtualbox` GUI or `virsh console`), and record exactly which directive
did it. This is the single most instructive failure in the lab.

### The datastream filename is distro-specific

`ssg-almalinux9-ds.xml` for Alma, `ssg-rhel9-ds.xml` for subscribed RHEL,
`ssg-rl9-ds.xml` for Rocky. Wrong filename → `oscap` exits with a file-not-found
that does not obviously say "wrong distro." List what is actually installed:
`ls /usr/share/xml/scap/ssg/content/`.

### oscap exits non-zero when controls fail

`oscap xccdf eval` returns exit code 2 when any rule fails — which is normal, not
an error. The Makefile uses `|| true` so the scan still writes its report. Do not
add error handling that treats a failing baseline as a broken run.

### Some STIG findings are false positives on a minimal box

A bare Vagrant image legitimately fails controls about audit daemons, GUI screen
locks, or FIPS mode that do not apply. Note these rather than "fixing" them — being
able to distinguish an inapplicable control from a real gap is a senior skill.

---

## YYYY-MM-DD — <first real entry>

**Goal:**

**What happened:**

```
```

**Why:**

**Fix:**

**Time lost:**

---

## Open questions

- [ ] Which controls needed manual remediation beyond the dev-sec roles?
- [ ] Did any hardening break sudo or SSH? How was it recovered?
- [ ] How does the Alma 9 score compare to genuine RHEL 9, if you ran both?

## What I would do differently

_End._
