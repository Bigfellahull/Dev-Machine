"""Check that global mise defaults cannot hide profile SDK requirements."""

import json
from pathlib import Path
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]


class MiseConfigTests(unittest.TestCase):
    """Keep both the work build baseline and personal SDK selection effective."""

    def test_profile_sdk_selection(self):
        """The work pin must survive the higher-precedence global configuration."""
        common = tomllib.loads((ROOT / "config/mise/config.toml").read_text())["tools"]
        sdk = json.loads((ROOT / "config/dotnet/work/global.json").read_text())["sdk"]["version"]
        for profile, expected in (("work", [sdk, "10"]), ("personal", "10")):
            with self.subTest(profile=profile):
                tools = tomllib.loads((ROOT / f"config/mise/{profile}.toml").read_text())["tools"]
                effective = {**tools, **common}
                self.assertEqual(effective["dotnet"], expected)
                self.assertFalse(
                    common.keys() & tools.keys(),
                    "Global tool declarations override profile fragments",
                )


if __name__ == "__main__":
    unittest.main()
