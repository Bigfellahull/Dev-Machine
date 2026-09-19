"""Check Windows commissioning without touching a real host or toolchain."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class WindowsBuildTests(unittest.TestCase):
    """Keep work-only provisioning explicit and verification read-only."""

    def test_profile_and_install_boundary(self):
        """Provision installs the pinned target; verify never invokes an installer."""
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            config = fixture / ".config/dev-machine"
            runtime = fixture / ".local/share/dev-machine"
            config.mkdir(parents=True)
            runtime.mkdir(parents=True)
            (runtime / "rust-toolchain").write_text("1.98.0\n")
            (config / "profile").write_text("work\n")
            log = fixture / "calls"
            mock = fixture / "mac"
            mock.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_WINDOWS_CALLS"\n')
            mock.chmod(0o755)
            env = dict(os.environ, HOME=str(fixture), PATH=f"{fixture}:{os.environ['PATH']}", TEST_WINDOWS_CALLS=str(log))
            command = ["bash", str(root / "bin/orbstack-windows-build")]
            result = subprocess.run([*command, "provision", "Build VM"], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("--target x86_64-pc-windows-msvc", log.read_text())
            self.assertIn("--current-user", log.read_text())
            log.write_text("")
            result = subprocess.run([*command, "verify"], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("toolchain install", log.read_text())
            (config / "profile").write_text("personal\n")
            log.write_text("")
            result = subprocess.run([*command, "provision"], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(log.read_text(), "")


if __name__ == "__main__":
    unittest.main()
