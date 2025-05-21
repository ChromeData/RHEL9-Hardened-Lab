#!/bin/bash
# Container-applicable subset of the STIG profile.
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE ADDING A CONTROL
#
# The first version of this script had nine sections: password quality,
# faillock, password aging, sudo policy, cron permissions, setuid trimming.
# It looked thorough. Measured against the scanner it moved the score by
# exactly zero:
#
#     Baseline :  63 / 71 passed (88.7%)      <- stock almalinux:9
#     Hardened :  63 / 71 passed (88.7%)      <- after all nine sections
#     Delta    : +0 controls (+0.0 pp)
#
# Every one of those controls is real, and not one of them is EVALUATED in a
# container. Of 1532 rules in the STIG profile, 1048 are notselected and 412
# are notapplicable here. The 71 that actually get scored are file
# permissions, ownership, package presence and GPG checking. pam_pwquality,
# faillock, login.defs and sudoers are not among them, because there is no
# PAM stack being exercised and no systemd to evaluate against.
#
# So the whole 88.7% was what AlmaLinux already shipped. The script was
# decoration, and a gate wrapped around it would have been decoration too.
#
# The rule now: a control belongs in this file if the scanner scores it, or if
# it is listed in the UNSCORED section at the bottom with a note saying so.
# Nothing goes in silently claiming credit it cannot demonstrate.
# ---------------------------------------------------------------------------
set -euo pipefail

echo "=== hardening: container-applicable STIG subset ==="

# ===========================================================================
# SCORED. Each of these maps to a rule in the 71 the scanner evaluates, and
# each one was failing on the stock image.
# ===========================================================================

# SSG: accounts_umask_etc_bashrc, accounts_umask_etc_profile
# 077 means new files are not readable by group or other. The stock image
# ships 022, which makes every file world-readable by default.
#
# First attempt appended `umask 077` and left line 69 of /etc/bashrc intact:
#     [ `umask` -eq 0 ] && umask 022
# That line does not start with "umask", so the grep missed it, the append
# ran, and the scanner still found 022 in the file. /etc/profile passed and
# /etc/bashrc did not, from the same block of code. Replace the value in
# place rather than adding a second, later assignment.
echo "[scored] umask in shell init"
for f in /etc/bashrc /etc/profile; do
  sed -i -E 's/umask[[:space:]]+0[0-7]{2}/umask 077/g' "$f"
  grep -qE 'umask[[:space:]]+077' "$f" || echo "umask 077" >> "$f"
done

# SSG: file_permission_user_init_files_root
# /etc/skel ships 0644, so every user created later inherits world-readable
# init files. Fixing skel before useradd runs is the only way this holds for
# accounts the image creates.
echo "[scored] /etc/skel init file permissions"
find /etc/skel -maxdepth 1 -type f -name '.*' -exec chmod 0640 {} \;

# SSG: ensure_gpgcheck_local_packages
# gpgcheck covers repo packages; localpkg_gpgcheck covers a package handed to
# dnf directly, which is exactly how someone sideloads something unsigned.
echo "[scored] dnf localpkg_gpgcheck"
if grep -q '^localpkg_gpgcheck' /etc/dnf/dnf.conf; then
  sed -i 's/^localpkg_gpgcheck.*/localpkg_gpgcheck=1/' /etc/dnf/dnf.conf
else
  echo "localpkg_gpgcheck=1" >> /etc/dnf/dnf.conf
fi

# SSG: use_pam_wheel_for_su
# Without this, any user who knows the root password can su. With it, they
# must also be in the wheel group, which makes su an explicit grant.
echo "[scored] pam_wheel for su"
if grep -qE '^#\s*auth\s+required\s+pam_wheel\.so' /etc/pam.d/su; then
  sed -i -E 's/^#\s*(auth\s+required\s+pam_wheel\.so.*)/\1/' /etc/pam.d/su
elif ! grep -qE '^auth\s+required\s+pam_wheel\.so' /etc/pam.d/su; then
  sed -i '/^auth\s*sufficient\s*pam_rootok.so/a auth\t\trequired\tpam_wheel.so use_uid' /etc/pam.d/su
fi

# SSG: rootfiles_configured
#
# Not "the files exist" — I assumed that and the rule kept failing. It wants a
# tmpfiles.d entry so systemd-tmpfiles RESTORES root's init files to mode 600
# from the rootfiles package, which means a hand-edit gets reverted instead of
# persisting. That is a meaningfully stronger control than a one-time chmod.
#
# The rootfiles package supplies the source files under /usr/share/rootfiles
# and is not in the base image. Writing the conf without it would point at
# files that do not exist: the scanner would pass and the mechanism would do
# nothing, which is the failure mode this repo exists to catch.
echo "[scored] root init files via tmpfiles.d"
dnf -y install --setopt=install_weak_deps=False rootfiles >/dev/null 2>&1 || true
if [ -d /usr/share/rootfiles ]; then
  mkdir -p /etc/tmpfiles.d
  cat > /etc/tmpfiles.d/rootfiles.conf <<'EOF'
C /root/.bash_logout  600 root root - /usr/share/rootfiles/.bash_logout
C /root/.bash_profile 600 root root - /usr/share/rootfiles/.bash_profile
C /root/.bashrc       600 root root - /usr/share/rootfiles/.bashrc
C /root/.cshrc        600 root root - /usr/share/rootfiles/.cshrc
C /root/.tcshrc       600 root root - /usr/share/rootfiles/.tcshrc
EOF
else
  echo "  rootfiles package unavailable, skipping conf rather than writing a dangling one"
fi

# SSG: file_permission_user_init_files_root  — 0740 or less permissive
echo "[scored] root init file permissions"
find /root -maxdepth 1 -type f -name '.*' -exec chmod 0600 {} \;

# SSG: configure_crypto_policy
#
# The STIG profile sets var_system_crypto_policy to FIPS:STIG, not DEFAULT.
# I set DEFAULT first, the back-end symlinks all pointed at DEFAULT correctly,
# and the rule still failed — because it compares against the profile's
# expected value, not against "is a policy configured".
#
# FIPS:STIG applies the policy files. Actual FIPS kernel mode needs fips=1 at
# boot, which a container does not have, so this satisfies the policy rule
# without making the image FIPS-validated. Those are different claims.
echo "[scored] system crypto policy"
update-crypto-policies --set FIPS:STIG 2>/dev/null \
  || update-crypto-policies --set FIPS 2>/dev/null \
  || echo "  crypto policy could not be set in this environment"

# ===========================================================================
# UNSCORED IN A CONTAINER, kept deliberately.
#
# The scanner reports these notapplicable here, so they contribute nothing to
# the number above and the gate cannot protect them. They stay because this
# image is a base for hosts where they DO apply, and shipping a base that
# quietly omits them pushes the problem downstream.
#
# What they must not do is be mistaken for the score. That is the mistake this
# file already made once.
# ===========================================================================

echo "[unscored] password quality"
cat > /etc/security/pwquality.conf <<'EOF'
minlen = 15
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
difok = 8
maxrepeat = 3
EOF

echo "[unscored] faillock"
cat > /etc/security/faillock.conf <<'EOF'
deny = 3
unlock_time = 0
fail_interval = 900
silent
audit
even_deny_root
EOF

echo "[unscored] password aging and hashing"
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t60/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t1/'  /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE\t7/'  /etc/login.defs
grep -q '^ENCRYPT_METHOD' /etc/login.defs \
  && sed -i 's/^ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/' /etc/login.defs \
  || echo "ENCRYPT_METHOD SHA512" >> /etc/login.defs

echo "[unscored] sudo policy"
cat > /etc/sudoers.d/10-hardening <<'EOF'
Defaults use_pty
Defaults logfile="/var/log/sudo.log"
Defaults !targetpw
Defaults !rootpw
Defaults !runaspw
Defaults timestamp_timeout=5
EOF
chmod 0440 /etc/sudoers.d/10-hardening
visudo -c -q

echo "[unscored] system account shells"
awk -F: '($3 < 1000) && ($1 != "root") && ($7 !~ /(nologin|false)$/) {print $1}' /etc/passwd \
  | while read -r u; do usermod -s /sbin/nologin "$u" 2>/dev/null || true; done

# ===========================================================================
# NOT FIXABLE HERE, recorded so nobody spends an afternoon on it.
#
# network_configure_name_resolution wants two or more nameservers in
# /etc/resolv.conf. The container runtime overwrites that file at start, so
# anything baked in is discarded. It fails in the image and would pass on a
# host. Left failing rather than papered over.
# ===========================================================================

echo "=== hardening complete ==="
