#!/usr/bin/env python3
"""Small HTTP/HTTPS forward proxy for WSL."""

from __future__ import annotations

import argparse
import select
import socket
import socketserver
from urllib.parse import urlsplit


BUFFER_SIZE = 65536


class ProxyHandler(socketserver.BaseRequestHandler):
    timeout = 30

    def handle(self) -> None:
        self.request.settimeout(self.timeout)
        first = self._read_headers()
        if not first:
            return

        try:
            header_text = first.decode("iso-8859-1")
            request_line, rest = header_text.split("\r\n", 1)
            method, target, version = request_line.split(" ", 2)
        except ValueError:
            self._send_error(400, "Bad Request")
            return

        if method.upper() == "CONNECT":
            self._handle_connect(target)
            return

        self._handle_http(method, target, version, rest, first)

    def _read_headers(self) -> bytes:
        data = b""
        while b"\r\n\r\n" not in data and len(data) < 1024 * 1024:
            chunk = self.request.recv(BUFFER_SIZE)
            if not chunk:
                break
            data += chunk
        return data

    def _handle_connect(self, target: str) -> None:
        host, port = self._split_host_port(target, 443)
        try:
            with socket.create_connection((host, port), timeout=self.timeout) as upstream:
                self.request.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                self._tunnel(self.request, upstream)
        except OSError:
            self._send_error(502, "Bad Gateway")

    def _handle_http(
        self,
        method: str,
        target: str,
        version: str,
        header_rest: str,
        raw_headers: bytes,
    ) -> None:
        parsed = urlsplit(target)
        if not parsed.hostname:
            self._send_error(400, "Expected absolute proxy URL")
            return

        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query

        rebuilt = self._rewrite_request(method, path, version, header_rest)
        body = raw_headers.split(b"\r\n\r\n", 1)[1]

        try:
            with socket.create_connection((parsed.hostname, port), timeout=self.timeout) as upstream:
                upstream.sendall(rebuilt + body)
                self._tunnel(self.request, upstream)
        except OSError:
            self._send_error(502, "Bad Gateway")

    def _rewrite_request(self, method: str, path: str, version: str, header_rest: str) -> bytes:
        headers = []
        for line in header_rest.split("\r\n"):
            if not line:
                continue
            name = line.split(":", 1)[0].strip().lower()
            if name in {"proxy-connection", "proxy-authorization"}:
                continue
            headers.append(line)

        request = f"{method} {path} {version}\r\n" + "\r\n".join(headers) + "\r\n\r\n"
        return request.encode("iso-8859-1")

    def _split_host_port(self, target: str, default_port: int) -> tuple[str, int]:
        if target.startswith("["):
            host, _, tail = target[1:].partition("]")
            port = int(tail[1:]) if tail.startswith(":") else default_port
            return host, port

        host, sep, port_text = target.rpartition(":")
        if sep and port_text.isdigit():
            return host, int(port_text)
        return target, default_port

    def _tunnel(self, left: socket.socket, right: socket.socket) -> None:
        sockets = [left, right]
        while True:
            readable, _, errored = select.select(sockets, [], sockets, self.timeout)
            if errored or not readable:
                return
            for sock in readable:
                data = sock.recv(BUFFER_SIZE)
                if not data:
                    return
                other = right if sock is left else left
                other.sendall(data)

    def _send_error(self, status: int, reason: str) -> None:
        body = f"{status} {reason}\n".encode("utf-8")
        response = (
            f"HTTP/1.1 {status} {reason}\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n"
            "\r\n"
        ).encode("ascii") + body
        self.request.sendall(response)


class ThreadingProxyServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a small local HTTP/HTTPS proxy.")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=18081)
    args = parser.parse_args()

    with ThreadingProxyServer((args.host, args.port), ProxyHandler) as server:
        print(f"WSL proxy listening on {args.host}:{args.port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
