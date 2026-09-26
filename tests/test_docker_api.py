"""Exercise tunnel commissioning and isolation without SSH or Docker services."""

import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin/orbstack-docker-api"


class DockerApiTests(unittest.TestCase):
    """Check credential, forwarding and profile boundaries using isolated homes."""

    def setUp(self):
        """Create private fixture state and mock only platform/transport commands."""
        self.temp = tempfile.TemporaryDirectory(prefix="dev-machine-api-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.parent = self.home / ".config/dev-machine"
        self.parent.mkdir(parents=True)
        (self.parent / "profile").write_text("work\n")
        (self.parent / "docker-api-bridge").write_text("enabled\n")
        (self.parent / "docker-api-bridge").chmod(0o600)
        self.state = self.parent / "docker-api"
        self.runtime = self.root / "run"
        self.runtime.mkdir(mode=0o700)
        self.mocks = self.root / "mocks"
        self.mocks.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), XDG_RUNTIME_DIR=str(self.runtime),
                        PATH=f"{self.mocks}:{os.environ['PATH']}", MOCK_HOSTNAME="work-dev",
                        SSH_LOG=str(self.root / "ssh.log"))
        self._mock("uname", '#!/bin/sh\necho Linux\n')
        self._mock("hostname", '#!/bin/sh\necho "$MOCK_HOSTNAME"\n')
        self._mock("stat", '''#!/usr/bin/env python3
import os, stat, sys
s = os.stat(sys.argv[3])
print(s.st_uid if sys.argv[2] == "%u" else oct(stat.S_IMODE(s.st_mode))[2:])
''')
        self._mock("ssh", '#!/bin/sh\nprintf "%s\\n" "$@" > "$SSH_LOG"\n')
        self._mock("curl", '#!/bin/sh\n[ "${API_DOWN:-0}" = 0 ] || exit 7\nprintf OK\n')
        self.hostkey = self.root / "host-key"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(self.hostkey)],
                       check=True, capture_output=True)
        self.known_hosts = self.root / "known_hosts"
        self.known_hosts.write_text("work-mini " + Path(str(self.hostkey) + ".pub").read_text())

    def _mock(self, name, body):
        path = self.mocks / name
        path.write_text(body)
        path.chmod(0o755)

    def _run(self, *args, ok=True):
        result = subprocess.run([str(HELPER), *args], env=self.env, text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def _init(self):
        return self._run("init", "work-mini", "operator", "/home/operator/.orbstack/run/docker.sock",
                         str(self.known_hosts))

    def _socket(self):
        path = self.runtime / "orbstack-docker.sock"
        with socket.socket(socket.AF_UNIX) as endpoint:
            endpoint.bind(str(path))
        path.chmod(0o600)
        return path

    def test_commissioning_preserves_keys_on_repeat(self):
        """Initialisation creates private state without silently rotating an existing key."""
        self._init()
        config = json.loads((self.state / "config.json").read_text())
        self.assertEqual(config["profile"], "work")
        self.assertEqual(config["machine"], "work-dev")
        key = (self.state / "id_ed25519").read_bytes()
        for name in ["config.json", "known_hosts", "id_ed25519"]:
            self.assertEqual((self.state / name).stat().st_mode & 0o777, 0o600)
        self._run("init", "work-mini", "operator", "/home/operator/.orbstack/run/docker.sock",
                  str(self.known_hosts), ok=False)
        self.assertEqual(key, (self.state / "id_ed25519").read_bytes())
        self.assertFalse(Path(self.env["SSH_LOG"]).exists())

    def test_personal_opt_in_and_profile_isolation(self):
        """Personal can commission its own key but cannot use copied work state."""
        (self.parent / "profile").write_text("personal\n")
        self.env["MOCK_HOSTNAME"] = "personal-dev"
        self._init()
        config = json.loads((self.state / "config.json").read_text())
        self.assertEqual(config["profile"], "personal")
        self.assertIn("orbstack-docker-api-personal-mini", (self.state / "id_ed25519.pub").read_text())
        (self.parent / "profile").write_text("work\n")
        self._run("serve", ok=False)
        self.assertFalse(Path(self.env["SSH_LOG"]).exists())

    def test_explicit_opt_in_required(self):
        """Both profiles fail closed without a valid private opt-in file."""
        flag = self.parent / "docker-api-bridge"
        for profile in ["work", "personal"]:
            (self.parent / "profile").write_text(profile + "\n")
            for value in ["disabled\n", "yes\n"]:
                flag.write_text(value)
                self._init_disabled()
            flag.unlink()
            self._init_disabled()
            flag.write_text("enabled\n")
            flag.chmod(0o644)
            self._init_disabled()
            flag.chmod(0o600)

    def _init_disabled(self):
        self._run("init", "work-mini", "operator", "/home/operator/.orbstack/run/docker.sock",
                  str(self.known_hosts), ok=False)
        self.assertFalse(self.state.exists())

    def test_installer_enable_disable_preserves_credentials(self):
        """Both profiles install on opt-in; disabling stops the unit without erasing keys."""
        bash_env = self.root / "module-env"
        bash_env.write_text(f'. "{ROOT}/bootstrap/lib.sh"\nrequire_target_ubuntu() {{ :; }}\n')
        self._mock("systemctl", '#!/bin/sh\nprintf "%s\n" "$*" >> "$SYSTEMCTL_LOG"\n')
        env = dict(self.env, BASH_ENV=str(bash_env), SYSTEMCTL_LOG=str(self.root / "systemctl.log"))
        installer = ROOT / "orb/docker-api.sh"
        helper = self.home / ".local/bin/orbstack-docker-api"
        unit = self.home / ".config/systemd/user/dev-machine-docker-api.service"
        flag = self.parent / "docker-api-bridge"
        for profile in ["work", "personal"]:
            env["DEV_MACHINE_PROFILE"] = profile
            flag.write_text("enabled\n")
            result = subprocess.run([str(installer)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(helper.read_bytes(), HELPER.read_bytes())
            self.assertTrue(unit.is_file())
            self.state.mkdir(exist_ok=True)
            (self.state / "keep").write_text("credential fixture")
            flag.write_text("disabled\n")
            result = subprocess.run([str(installer)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(helper.exists())
            self.assertFalse(unit.exists())
            self.assertEqual((self.state / "keep").read_text(), "credential fixture")
            self.assertIn("disable --now dev-machine-docker-api.service", (self.root / "systemctl.log").read_text())
            (self.state / "keep").unlink()
            self.state.rmdir()
            result = subprocess.run([str(installer)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_clone_cannot_reuse_credentials(self):
        """A changed VM hostname blocks inherited credentials before SSH starts."""
        self._init()
        self.env["MOCK_HOSTNAME"] = "work-exp-test"
        result = self._run("serve", ok=False)
        self.assertEqual(result.returncode, 78)
        self.assertIn("another VM", result.stderr)
        self.assertFalse(Path(self.env["SSH_LOG"]).exists())

    def test_forwarding_uses_only_the_commissioned_identity(self):
        """Forwarding suppresses user SSH config, agents and automatic host trust."""
        self._init()
        self._run("serve")
        args = Path(self.env["SSH_LOG"]).read_text().splitlines()
        for expected in ["/dev/null", "IdentitiesOnly=yes", "IdentityAgent=none", "BatchMode=yes",
                         "StrictHostKeyChecking=yes", "ExitOnForwardFailure=yes",
                         "StreamLocalBindMask=0177", "StreamLocalBindUnlink=yes"]:
            self.assertIn(expected, args)
        self.assertIn(str(self.runtime / "orbstack-docker.sock") +
                      ":/home/operator/.orbstack/run/docker.sock", args)
        self.assertEqual(args[-1], "work-mini")

    def test_api_environment_is_command_scoped(self):
        """Only the child receives the forwarded Docker endpoint."""
        self._init()
        path = self._socket()
        self.env["DOCKER_HOST"] = "original"
        result = self._run("run", "sh", "-c", 'printf "%s" "$DOCKER_HOST"')
        self.assertEqual(result.stdout, f"unix://{path}")
        self.assertEqual(self.env["DOCKER_HOST"], "original")

    def test_stale_socket_does_not_pass_verification(self):
        """An existing socket must also answer the Docker API readiness request."""
        self._init()
        self._socket()
        self.env["API_DOWN"] = "1"
        self._run("verify", ok=False)

    def test_unsafe_permissions_and_socket_types_are_rejected(self):
        """Reject readable private keys, public runtime directories and socket links."""
        self._init()
        key = self.state / "id_ed25519"
        key.chmod(0o644)
        self._run("serve", ok=False)
        key.chmod(0o600)
        self.runtime.chmod(0o755)
        self._run("serve", ok=False)
        self.runtime.chmod(0o700)
        path = self.runtime / "orbstack-docker.sock"
        path.write_text("unrelated")
        self._run("serve", ok=False)
        self.assertEqual(path.read_text(), "unrelated")
        path.unlink()
        path.symlink_to(key)
        self._run("serve", ok=False)

    def test_destination_validation_and_host_key_match(self):
        """Host and socket arguments cannot inject SSH options or forwarding syntax."""
        for host, user, path in [("-oProxyCommand=bad", "operator", "/home/u/.orbstack/run/docker.sock"),
                                 ("work-mini", "-root", "/home/u/.orbstack/run/docker.sock"),
                                 ("work-mini", "operator", "/tmp/socket:other"),
                                 ("unknown-mini", "operator", "/home/u/.orbstack/run/docker.sock")]:
            self._run("init", host, user, path, str(self.known_hosts), ok=False)
        self.assertFalse(self.state.exists())


if __name__ == "__main__":
    unittest.main()
