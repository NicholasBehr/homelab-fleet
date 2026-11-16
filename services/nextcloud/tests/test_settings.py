import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("settings", Path(__file__).resolve().parents[1] / "verify-settings.py")
settings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(settings)


class Settings(unittest.TestCase):
    def value(self):
        return {"trusted_domains": ["localhost", "127.0.0.1", "fixture.example.ts.net"],
                "overwrite.cli.url": "https://fixture.example.ts.net"}

    def test_tailnet_domain(self):
        self.assertTrue(settings.valid(self.value()))

    def test_no_storage_or_auth_overrides(self):
        for key in ("datadirectory", "dbpassword", "maintenance", "overwritehost"):
            value = self.value()
            value[key] = "unexpected"
            self.assertFalse(settings.valid(value))

    def test_reject_untrusted_endpoints(self):
        for endpoint in ("http://fixture.example.ts.net", "https://example.com", "https://user@fixture.example.ts.net",
                         "https://fixture.example.ts.net:8443", "https://fixture.example.ts.net/path", "https://fixture.example.ts.net?q=x"):
            value = self.value()
            value["overwrite.cli.url"] = endpoint
            self.assertFalse(settings.valid(value))

    def test_reject_extra_domains(self):
        value = self.value()
        value["trusted_domains"].append("*")
        self.assertFalse(settings.valid(value))
