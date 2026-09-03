#!/usr/bin/env bash

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TEST_ROOT
test_count=0

test_fail() {
  printf 'not ok %d - %s\n' "$test_count" "$*" >&2
  exit 1
}

assert_contains() {
  haystack=$1
  needle=$2
  test_count=$((test_count + 1))
  case "$haystack" in
    *"$needle"*) printf 'ok %d - contains %s\n' "$test_count" "$needle" ;;
    *) test_fail "expected output to contain: $needle" ;;
  esac
}

assert_not_contains() {
  haystack=$1
  needle=$2
  test_count=$((test_count + 1))
  case "$haystack" in
    *"$needle"*) test_fail "expected output not to contain: $needle" ;;
    *) printf 'ok %d - excludes %s\n' "$test_count" "$needle" ;;
  esac
}

assert_fails() {
  test_count=$((test_count + 1))
  if "$@" >/dev/null 2>&1; then
    test_fail "command should have failed: $*"
  fi
  printf 'ok %d - rejects unsafe/invalid input\n' "$test_count"
}
