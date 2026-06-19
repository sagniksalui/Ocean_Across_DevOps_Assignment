"""Dependency-free placeholder API for CI/CD and deployment demonstrations."""

import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


def build_response(request_target: str) -> tuple[HTTPStatus, dict[str, str]]:
    """Return the status and JSON payload for a request target."""
    path = urlsplit(request_target).path

    if path == "/health":
        return HTTPStatus.OK, {"status": "ok"}

    if path == "/portal":
        portal_type = os.getenv("PORTAL_TYPE", "unknown").strip() or "unknown"
        return HTTPStatus.OK, {"portal_type": portal_type}

    return HTTPStatus.NOT_FOUND, {"error": "not_found"}


class RequestHandler(BaseHTTPRequestHandler):
    """Serve the small JSON API without introducing framework dependencies."""

    server_version = "OceanAcrossPlaceholder/1.0"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        status, payload = build_response(self.path)
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    """Start the placeholder server on the configured container port."""
    port = int(os.getenv("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), RequestHandler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
