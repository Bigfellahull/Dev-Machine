#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-lib.sh
. "$SCRIPT_DIR/test-lib.sh"
cd "$TEST_ROOT"

example_env="$TEST_ROOT/docker/db.env.example"

if [ "$(uname -s)" = Darwin ]; then
  expected_docker_command='docker compose'
else
  expected_docker_command='mac docker compose'
fi

output=$(bin/db start postgres --project 'Project A' --env-file "$example_env" --dry-run 2>&1)
assert_contains "$output" "$expected_docker_command"
assert_contains "$output" "--project-name project-a-postgres"
assert_contains "$output" "postgres/compose.yaml up -d"

output=$(bin/db start mssql --project project-a --env-file "$example_env" --dry-run 2>&1)
assert_contains "$output" "unsupported by Microsoft"
assert_contains "$output" "--project-name project-a-mssql"

output=$(bin/db status --project project-a --env-file "$example_env" --dry-run)
assert_contains "$output" "project-a-postgres"
assert_contains "$output" "project-a-mssql"
assert_contains "$output" "project-a-redis"

output=$(DEV_MACHINE_DB_ENGINES=postgres bin/db status --project project-a --env-file "$example_env" --dry-run)
assert_contains "$output" "project-a-postgres"
assert_not_contains "$output" "project-a-mssql"
assert_not_contains "$output" "project-a-redis"

output=$(bin/db reset redis --project project-a --env-file "$example_env" --dry-run)
assert_contains "$output" "--project-name project-a-redis"
assert_contains "$output" "down --volumes --remove-orphans"
assert_not_contains "$output" "project-a-postgres"

output=$(bin/db connection postgres --project project-a --env-file "$example_env")
assert_contains "$output" "docker.orb.internal:5432/app"
assert_not_contains "$output" "replace-with-a-local-only-password"

assert_fails bin/db start postgres --project project-a --env-file /dev/null --dry-run
assert_fails bin/db start mysql --project project-a --env-file "$example_env" --dry-run
assert_fails env DEV_MACHINE_DB_ENGINES=postgres \
  bin/db start mssql --project project-a --env-file "$example_env" --dry-run

profile_home=$(mktemp -d)
trap 'rm -rf "$profile_home"' EXIT
mkdir -p "$profile_home/.config/dev-machine" \
  "$profile_home/.local/share/dev-machine/docker/postgres"
printf 'personal\n' >"$profile_home/.config/dev-machine/profile"
printf 'postgres\n' >"$profile_home/.local/share/dev-machine/docker/enabled-engines"
cp docker/images.env "$profile_home/.local/share/dev-machine/docker/images.env"
cp docker/postgres/compose.yaml \
  "$profile_home/.local/share/dev-machine/docker/postgres/compose.yaml"

output=$(HOME="$profile_home" bin/db status --project project-a --env-file "$example_env" --dry-run)
assert_contains "$output" "$profile_home/.local/share/dev-machine/docker/postgres/compose.yaml"
assert_not_contains "$output" "project-a-mssql"
assert_not_contains "$output" "project-a-redis"

mock_directory=$(mktemp -d)
trap 'rm -R "$profile_home" "$mock_directory"' EXIT
cat >"$mock_directory/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Linux\n'
EOF
cat >"$mock_directory/docker" <<'EOF'
#!/usr/bin/env bash
printf 'unsafe docker fallback was invoked\n' >&2
exit 99
EOF
chmod +x "$mock_directory/uname" "$mock_directory/docker"

output=$(PATH="$mock_directory:/usr/bin:/bin" bin/db status postgres \
  --project project-a --env-file "$example_env" --dry-run)
assert_contains "$output" 'mac docker compose'
assert_not_contains "$output" 'unsafe docker fallback'

if output=$(PATH="$mock_directory:/usr/bin:/bin" bin/db status postgres \
  --project project-a --env-file "$example_env" 2>&1); then
  test_fail 'Linux database administration succeeded without the mac bridge'
fi
assert_contains "$output" "OrbStack's 'mac' command bridge is required"
assert_not_contains "$output" 'unsafe docker fallback'

printf 'database helper tests passed (%d assertions)\n' "$test_count"
