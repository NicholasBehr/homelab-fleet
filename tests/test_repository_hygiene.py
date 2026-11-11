"""Keep every registered service expansion-ready and public documentation private."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RepositoryHygiene(unittest.TestCase):
    def test_every_service_has_a_deployment_contract_and_checks(self):
        services = {path.name for path in (ROOT / "services").iterdir() if path.is_dir()}
        deployments = {
            path.stem
            for path in (ROOT / "deployments").glob("*.nix")
            if not path.name.endswith("-contract.nix")
        }
        contracts = {
            path.name.removesuffix("-contract.nix")
            for path in (ROOT / "deployments").glob("*-contract.nix")
        }
        self.assertEqual(services, deployments)
        self.assertEqual(services, contracts)
        for service in services:
            self.assertTrue((ROOT / "services" / service / "default.nix").is_file())
            self.assertTrue((ROOT / "services" / service / "tests" / "checks.nix").is_file())
            self.assertTrue((ROOT / "docs" / f"{service}.md").is_file())

    def test_no_source_secret_shim(self):
        self.assertFalse((ROOT / "secrets").exists())

    def test_docs_contain_no_private_ipv4_addresses(self):
        private = re.compile(
            r"\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b"
        )
        for path in (ROOT / "docs").glob("*.md"):
            self.assertIsNone(private.search(path.read_text()), path)


if __name__ == "__main__":
    unittest.main()
