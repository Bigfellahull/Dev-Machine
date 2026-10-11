"""Exercise temporary-storage mount commands in an isolated Linux namespace."""

import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class TemporaryStorageTests(unittest.TestCase):
    """Check the installed service's mount behaviour without changing the host."""

    def test_noexec_backing_supports_executable_build_files(self):
        """Clear inherited noexec while retaining nosuid and nodev on the target."""
        if sys.platform != "linux" or not all(
                shutil.which(tool) for tool in ("unshare", "mount", "findmnt", "bash")):
            self.skipTest("Linux mount namespace tools are unavailable")
        namespace = ["unshare", "--user", "--map-root-user", "--mount",
                     "--propagation", "private"]
        probe = subprocess.run([*namespace, "true"], capture_output=True, text=True)
        if probe.returncode:
            self.skipTest("Unprivileged mount namespaces are unavailable")

        with tempfile.TemporaryDirectory(prefix="dev-machine-tmp-test-") as directory:
            backing = Path(directory) / "backing"
            target = Path(directory) / "target"
            backing.mkdir()
            target.mkdir()
            replacements = {"/var/lib/dev-machine/tmp": str(backing), "/tmp": str(target)}
            commands = []
            for line in (ROOT / "config/systemd/dev-machine-tmp.service").read_text().splitlines():
                if line.startswith("ExecStart="):
                    arguments = shlex.split(line.removeprefix("ExecStart="))
                    commands.append(shlex.join([replacements.get(arg, arg) for arg in arguments]))
            self.assertEqual(len(commands), 2)
            script = '\n'.join([
                "set -eu",
                shlex.join(["mount", "-t", "tmpfs", "-o", "noexec", "tmpfs", str(backing)]),
                shlex.join(["source", str(ROOT / "bootstrap/verify-lib.sh")]),
                *commands,
                shlex.join(["temporary_storage_mount_options_valid", str(target)]),
                'printf "#!/bin/sh\\nexit 0\\n" > "$1/build-check"',
                'chmod 700 "$1/build-check"',
                '"$1/build-check"',
                shlex.join(["findmnt", "-n", "-o", "VFS-OPTIONS", "--target", str(backing)]),
            ])
            result = subprocess.run([*namespace, "bash", "-c", script, "test", str(target)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("noexec", result.stdout.strip().split(","))


if __name__ == "__main__":
    unittest.main()
