#!/usr/bin/env bash
# Positive control for the golden image build gate.
#
# Breaks a scored control on purpose, rebuilds, and FAILS if the gate does not
# notice. The gate is the thing under test here, not the image.
#
# This exists because the gate passed three times while proving nothing:
#
#   1. The hardening script moved the score by +0 and the gate happily
#      certified a baseline that was entirely the stock base image.
#   2. The first deliberate break weakened pwquality and faillock, which are
#      notapplicable in a container, so nothing the gate watches could move.
#   3. The second break disabled one branch of an if/elif and the elif
#      configured the control anyway.
#
# Hence the verify step below. A break that did not land in the artifact is
# not a test, and it looks exactly like a passing one.
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE=rhel9-hardened-golden
SSG=/usr/share/xml/scap/ssg/content/ssg-almalinux9-ds.xml
PROFILE=xccdf_org.ssgproject.content_profile_stig
ORIG=$(mktemp)
mkdir -p reports

cleanup() { cp "$ORIG" image/harden.sh; rm -f "$ORIG"; }
trap cleanup EXIT

cp image/harden.sh "$ORIG"

echo "=== 1. baseline image must pass the gate ==="
docker build -q -t "$IMAGE:control-good" -f image/Containerfile image/ >/dev/null
docker run --rm --user root -v "$PWD/reports":/out "$IMAGE:control-good" \
  bash -c "oscap xccdf eval --profile $PROFILE --results /out/control-good.xml $SSG >/dev/null 2>&1; true"
python3 scripts/image-gate.py reports/control-good.xml --baseline image/baseline.json \
  || { echo "FAIL: the unmodified image does not pass its own gate. Fix that first."; exit 1; }

echo
echo "=== 2. break a SCORED control: use_pam_wheel_for_su ==="
# Remove the whole section. Disabling one branch is not enough; the elif
# fallback re-adds the line, which is how attempt 2 fooled itself.
python3 - <<'PY'
import io
p = "image/harden.sh"
s = io.open(p, encoding="utf-8", newline="").read()
start = s.index('echo "[scored] pam_wheel for su"')
end = s.index("# SSG: rootfiles_configured")
io.open(p, "w", encoding="utf-8", newline="").write(
    s[:start] + 'echo "[scored] pam_wheel for su  (REMOVED BY POSITIVE CONTROL)"\n\n' + s[end:]
)
PY
docker build -q -t "$IMAGE:control-bad" -f image/Containerfile image/ >/dev/null

echo
echo "=== 3. verify the break actually landed in the artifact ==="
if docker run --rm --user root "$IMAGE:control-bad" \
     grep -qE '^auth[[:space:]]+required[[:space:]]+pam_wheel\.so' /etc/pam.d/su; then
  echo "FAIL: pam_wheel is still active in the broken image. The break did not"
  echo "      land, so anything the gate says next is meaningless."
  exit 1
fi
echo "  confirmed: pam_wheel is not active in the broken image"

echo
echo "=== 4. the gate must now FAIL ==="
docker run --rm --user root -v "$PWD/reports":/out "$IMAGE:control-bad" \
  bash -c "oscap xccdf eval --profile $PROFILE --results /out/control-bad.xml $SSG >/dev/null 2>&1; true"

if python3 scripts/image-gate.py reports/control-bad.xml --baseline image/baseline.json; then
  echo
  echo "FAIL: the gate passed an image with a removed control. The gate is not"
  echo "      protecting what it claims to protect."
  exit 1
fi

echo
echo "positive control passed: the gate caught a removed control and blocked the build."
