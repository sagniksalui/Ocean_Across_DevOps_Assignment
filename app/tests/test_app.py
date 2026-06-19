import os
import sys
import unittest
from http import HTTPStatus
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from app import build_response  # noqa: E402


class BuildResponseTests(unittest.TestCase):
    def test_health_endpoint_reports_ok(self) -> None:
        status, payload = build_response("/health")

        self.assertEqual(status, HTTPStatus.OK)
        self.assertEqual(payload, {"status": "ok"})

    def test_portal_endpoint_reads_environment(self) -> None:
        with patch.dict(os.environ, {"PORTAL_TYPE": "companies"}, clear=False):
            status, payload = build_response("/portal")

        self.assertEqual(status, HTTPStatus.OK)
        self.assertEqual(payload, {"portal_type": "companies"})

    def test_portal_endpoint_uses_safe_default_for_blank_value(self) -> None:
        with patch.dict(os.environ, {"PORTAL_TYPE": "  "}, clear=False):
            status, payload = build_response("/portal?source=test")

        self.assertEqual(status, HTTPStatus.OK)
        self.assertEqual(payload, {"portal_type": "unknown"})

    def test_unknown_endpoint_returns_not_found(self) -> None:
        status, payload = build_response("/payroll")

        self.assertEqual(status, HTTPStatus.NOT_FOUND)
        self.assertEqual(payload, {"error": "not_found"})


if __name__ == "__main__":
    unittest.main()
