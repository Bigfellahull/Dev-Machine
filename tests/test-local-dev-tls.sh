#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-lib.sh
. "$SCRIPT_DIR/test-lib.sh"

test_directory=

cleanup() {
  if [ -n "$test_directory" ]; then
    rm -R "$test_directory"
  fi
}

create_fixture() {
  fixture_root=$1
  profile=$2
  fixture_mode=${3:-valid}
  ca_key="$test_directory/ca-key.pem"
  csr="$test_directory/leaf.csr"
  extensions="$test_directory/leaf-extensions.cnf"

  mkdir -m 0700 "$fixture_root"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$ca_key" \
    -out "$fixture_root/root-ca.pem" \
    -days 730 \
    -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
    -addext 'keyUsage=critical,keyCertSign' \
    -subj '/CN=dev-machine test CA' >/dev/null 2>&1
  openssl req -newkey rsa:2048 -nodes \
    -keyout "$fixture_root/localhost-key.pem" \
    -out "$csr" \
    -subj '/CN=localhost' >/dev/null 2>&1
  case "$fixture_mode" in
    valid)
      cat >"$extensions" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,DNS:dev.localhost,DNS:*.dev.localhost,IP:127.0.0.1,IP:::1
EOF
      ;;
    ca-leaf)
      cat >"$extensions" <<'EOF'
basicConstraints=CA:TRUE
keyUsage=digitalSignature,keyEncipherment,keyCertSign
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,DNS:dev.localhost,DNS:*.dev.localhost,IP:127.0.0.1,IP:::1
EOF
      ;;
    no-san)
      cat >"$extensions" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
      ;;
    near-ipv6)
      cat >"$extensions" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,DNS:dev.localhost,DNS:*.dev.localhost,IP:127.0.0.1,IP:::12
EOF
      ;;
    extra-san)
      cat >"$extensions" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,DNS:dev.localhost,DNS:*.dev.localhost,DNS:other.localhost,IP:127.0.0.1,IP:::1
EOF
      ;;
    *) test_fail "unknown TLS fixture mode: $fixture_mode" ;;
  esac
  openssl x509 -req \
    -in "$csr" \
    -CA "$fixture_root/root-ca.pem" \
    -CAkey "$ca_key" \
    -set_serial 1 \
    -out "$fixture_root/localhost.pem" \
    -days 365 \
    -extfile "$extensions" >/dev/null 2>&1
  printf '%s\n' "$profile" >"$fixture_root/profile"
  chmod 0644 \
    "$fixture_root/root-ca.pem" \
    "$fixture_root/localhost.pem" \
    "$fixture_root/profile"
  chmod 0600 "$fixture_root/localhost-key.pem"
}

main() {
  command -v openssl >/dev/null 2>&1 || {
    printf 'skip: OpenSSL is unavailable\n'
    return
  }

  test_directory="$(mktemp -d "${TMPDIR:-/tmp}/dev-machine-tls-test.XXXXXX")"
  fixture="$test_directory/handoff"
  create_fixture "$fixture" work

  # shellcheck source=bin/local-dev-tls
  . "$TEST_ROOT/bin/local-dev-tls"

  validate_material_directory "$fixture" work \
    || test_fail "valid TLS handoff was rejected"
  test_count=$((test_count + 1))
  printf 'ok %d - accepts valid TLS handoff\n' "$test_count"

  create_fixture "$test_directory/traditional-key" work
  openssl pkey -in "$test_directory/traditional-key/localhost-key.pem" \
    -traditional -out "$test_directory/traditional-key.pem" 2>/dev/null
  install -m 0600 "$test_directory/traditional-key.pem" \
    "$test_directory/traditional-key/localhost-key.pem"
  validate_material_directory "$test_directory/traditional-key" work \
    || test_fail "Mac-compatible PKCS#1 TLS handoff was rejected"
  test_count=$((test_count + 1))
  printf 'ok %d - accepts Mac-compatible PKCS#1 TLS handoff\n' "$test_count"

  openssl rsa -in "$test_directory/traditional-key.pem" -traditional -outform DER \
    >"$test_directory/combined-traditional-key.der" 2>/dev/null
  openssl x509 -in "$test_directory/traditional-key/localhost.pem" -outform DER \
    >>"$test_directory/combined-traditional-key.der"
  {
    printf '%s%s\n' '-----BEGIN RSA PRIVATE ' 'KEY-----'
    openssl base64 -in "$test_directory/combined-traditional-key.der"
    printf '%s%s\n' '-----END RSA PRIVATE ' 'KEY-----'
  } >"$test_directory/traditional-key/localhost-key.pem"
  assert_fails validate_material_directory "$test_directory/traditional-key" work

  assert_fails validate_material_directory "$fixture" personal

  touch "$fixture/rootCA-key.pem"
  assert_fails validate_material_directory "$fixture" work
  rm "$fixture/rootCA-key.pem"

  cat "$test_directory/ca-key.pem" >>"$fixture/root-ca.pem"
  assert_fails validate_material_directory "$fixture" work
  create_fixture "$test_directory/duplicate-certificate" work
  cat "$test_directory/duplicate-certificate/root-ca.pem" \
    >>"$test_directory/duplicate-certificate/localhost.pem"
  assert_fails validate_material_directory "$test_directory/duplicate-certificate" work

  create_fixture "$test_directory/der-tail-certificate" work
  openssl x509 -in "$test_directory/der-tail-certificate/root-ca.pem" \
    -outform DER >"$test_directory/combined-certificate.der"
  openssl pkey -in "$test_directory/ca-key.pem" -outform DER \
    >>"$test_directory/combined-certificate.der" 2>/dev/null
  {
    printf '%s\n' '-----BEGIN CERTIFICATE-----'
    openssl base64 -in "$test_directory/combined-certificate.der"
    printf '%s\n' '-----END CERTIFICATE-----'
  } >"$test_directory/der-tail-certificate/root-ca.pem"
  chmod 0644 "$test_directory/der-tail-certificate/root-ca.pem"
  assert_fails validate_material_directory "$test_directory/der-tail-certificate" work

  create_fixture "$test_directory/der-tail-key" work
  openssl pkcs8 -topk8 -nocrypt \
    -in "$test_directory/der-tail-key/localhost-key.pem" -outform DER \
    >"$test_directory/combined-key.der" 2>/dev/null
  openssl x509 -in "$test_directory/der-tail-key/localhost.pem" -outform DER \
    >>"$test_directory/combined-key.der"
  {
    printf '%s%s\n' '-----BEGIN PRIVATE ' 'KEY-----'
    openssl base64 -in "$test_directory/combined-key.der"
    printf '%s%s\n' '-----END PRIVATE ' 'KEY-----'
  } >"$test_directory/der-tail-key/localhost-key.pem"
  chmod 0600 "$test_directory/der-tail-key/localhost-key.pem"
  assert_fails validate_material_directory "$test_directory/der-tail-key" work

  cp "$test_directory/ca-key.pem" "$fixture/unexpected-private-key.pem"
  chmod 0600 "$fixture/unexpected-private-key.pem"
  assert_fails validate_material_directory "$fixture" work
  rm "$fixture/unexpected-private-key.pem"

  cp "$test_directory/ca-key.pem" "$fixture/localhost-key.pem"
  chmod 0600 "$fixture/localhost-key.pem"
  assert_fails validate_material_directory "$fixture" work

  create_fixture "$test_directory/ca-leaf" work ca-leaf
  assert_fails validate_material_directory "$test_directory/ca-leaf" work
  create_fixture "$test_directory/no-san" work no-san
  assert_fails validate_material_directory "$test_directory/no-san" work
  create_fixture "$test_directory/near-ipv6" work near-ipv6
  assert_fails validate_material_directory "$test_directory/near-ipv6" work
  create_fixture "$test_directory/extra-san" work extra-san
  assert_fails validate_material_directory "$test_directory/extra-san" work

  create_fixture "$test_directory/runtime-source" work
  tls_directory="$test_directory/no-existing-runtime"
  create_pfx "$test_directory/runtime-source"
  validate_runtime_directory "$test_directory/runtime-source" work \
    || test_fail "valid generated PFX was rejected"
  test_count=$((test_count + 1))
  printf 'ok %d - validates generated PFX\n' "$test_count"

  tls_directory="$HOME/.config/local-dev-tls"
  paths_output=$(print_paths)
  assert_contains "$paths_output" '.config/local-dev-tls/root-ca.pem'
  assert_contains "$paths_output" '.config/local-dev-tls/localhost.pfx-password'

  system_ca_directory="$test_directory/system-ca"
  mkdir "$system_ca_directory"
  tls_directory="$test_directory/transaction-runtime"
  backup_directory="$test_directory/transaction-runtime.previous"
  mkdir "$tls_directory" "$backup_directory"
  printf 'new runtime\n' >"$tls_directory/state"
  printf 'old runtime\n' >"$backup_directory/state"
  system_ca_target="$system_ca_directory/dev-machine-local-dev-work.crt"
  system_ca_backup="$test_directory/system-ca.previous"
  printf 'new root\n' >"$system_ca_target"
  printf 'old root\n' >"$system_ca_backup"
  system_ca_existed=1
  system_ca_changed=1
  runtime_replacement_started=1
  sudo() { "$@"; }
  # shellcheck disable=SC2032
  update-ca-certificates() { return 0; }
  rollback_tls_transaction
  assert_contains "$(<"$tls_directory/state")" 'old runtime'
  assert_contains "$(<"$system_ca_target")" 'old root'

  tls_directory="$test_directory/new-transaction-runtime"
  backup_directory=
  mkdir "$tls_directory"
  printf 'new runtime\n' >"$tls_directory/state"
  system_ca_target="$system_ca_directory/dev-machine-local-dev-personal.crt"
  system_ca_backup=
  printf 'new root\n' >"$system_ca_target"
  system_ca_existed=0
  system_ca_changed=1
  runtime_replacement_started=1
  rollback_tls_transaction
  if [ -e "$tls_directory" ] || [ -e "$system_ca_target" ]; then
    test_fail 'rollback retained TLS state that had no predecessor'
  fi
  test_count=$((test_count + 1))
  printf 'ok %d - removes failed first-time TLS installation\n' "$test_count"

  system_ca_target="$system_ca_directory/dev-machine-local-dev-work.crt"
  system_ca_backup="$test_directory/system-ca.failed-restore"
  printf 'new root\n' >"$system_ca_target"
  printf 'old root\n' >"$system_ca_backup"
  system_ca_existed=1
  system_ca_changed=1
  runtime_replacement_started=0
  sudo() {
    if [ "$1" = install ]; then
      return 7
    fi
    "$@"
  }
  if rollback_tls_transaction; then
    test_fail 'rollback hid a system CA restore failure'
  fi
  assert_contains "$(<"$system_ca_target")" 'new root'
  [ -f "$system_ca_backup" ] || test_fail 'failed rollback lost its recovery copy'
  test_count=$((test_count + 1))
  printf 'ok %d - retains recovery copy after failed system CA restore\n' "$test_count"

  system_ca_target="$system_ca_directory/dev-machine-local-dev-personal.crt"
  system_ca_backup=
  printf 'new root\n' >"$system_ca_target"
  system_ca_existed=0
  sudo() {
    if [ "$1" = rm ]; then
      return 8
    fi
    "$@"
  }
  if rollback_tls_transaction; then
    test_fail 'rollback hid a system CA removal failure'
  fi
  [ -f "$system_ca_target" ] || test_fail 'removal failure fixture unexpectedly vanished'
  test_count=$((test_count + 1))
  printf 'ok %d - reports failed first-install system CA removal\n' "$test_count"
  transaction_active=0
  runtime_replacement_started=0
  system_ca_changed=0

  printf 'local development TLS tests passed (%d assertions)\n' "$test_count"
}

trap cleanup EXIT
main "$@"
