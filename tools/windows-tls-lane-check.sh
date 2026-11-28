#!/bin/sh
# Pass/fail check for the Windows TLS lane. Linux ELF is not PE proof.
# FAIL_BEFORE: rcx password, PersistKeySet unpassworded PKCS#12, exclusive log read.
# PASS_AFTER: r9 password, EphemeralKeySet (no PersistKeySet), Read-SharedText.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
SHA=$(git rev-parse --short=12 HEAD)
fail=0
pe="$ROOT/src/rt-tls-pe.vire"
tls="$ROOT/VireTls.cs"
auth="$ROOT/tools/post-block-auth-windows.ps1"

if grep -F -q "76, 137, 77, 216, 76, 137, 13" "$pe"; then
  echo "PASS pe_tls_listen_password_r9"
else
  echo "FAIL pe_tls_listen_password_r9 (want mov [tls_keyptr], r9 after emitPop2)"
  fail=1
fi
if grep -F -q "76, 137, 77, 216, 72, 137, 13" "$pe"; then
  echo "FAIL pe_tls_listen_password_rcx (mov [tls_keyptr], rcx drops the PFX password)"
  fail=1
else
  echo "PASS pe_tls_listen_password_not_rcx"
fi

if grep -q "PersistKeySet" "$tls"; then
  echo "FAIL host_pem_no_persistkeyset (unpassworded PKCS#12 must not persist in the user store)"
  fail=1
else
  echo "PASS host_pem_no_persistkeyset"
fi
if grep -q "EphemeralKeySet" "$tls"; then
  echo "PASS host_pem_ephemeralkeyset"
else
  echo "FAIL host_pem_ephemeralkeyset"
  fail=1
fi

if grep -q "Read-SharedText" "$auth" && grep -q 'block-auth-pe.log' "$auth"; then
  echo "PASS post_block_auth_shared_log"
else
  echo "FAIL post_block_auth_shared_log"
  fail=1
fi
if grep -n "ReadAllText(\$outLog)" "$auth" >/dev/null 2>&1; then
  echo "FAIL post_block_auth_exclusive_ReadAllText"
  fail=1
else
  echo "PASS post_block_auth_no_exclusive_ReadAllText"
fi

echo "sha $SHA fail=$fail"
echo "LINUX_ELF_IS_NOT_PE_PROOF"
if [ "$fail" -ne 0 ]; then
  echo "FAIL_BEFORE Windows TLS lane"
  exit 1
fi
echo "PASS_AFTER Windows TLS lane checks"
exit 0
