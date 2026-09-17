#!/usr/bin/env python3
import base64
import hashlib
import json
import os
import socket
import struct
import urllib.request


def get_ws_url(port, title_contains=None):
    with urllib.request.urlopen(f"http://localhost:{port}/json") as r:
        targets = json.loads(r.read())
    for t in targets:
        if t.get("type") == "page":
            if title_contains is None or title_contains.lower() in (t.get("title") or "").lower():
                return t["webSocketDebuggerUrl"]
    raise RuntimeError("no matching page target found")


class CDP:
    def __init__(self, ws_url):
        _, _, host_port, *path_parts = ws_url.split("/", 3)
        path = "/" + (path_parts[0] if path_parts else "")
        host, port = host_port.split(":")
        self.sock = socket.create_connection((host, int(port)))
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        )
        self.sock.sendall(req.encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            resp += self.sock.recv(4096)
        self._id = 0

    def _send_frame(self, data: bytes):
        header = bytearray([0x81])  # FIN + text frame
        length = len(data)
        mask_bit = 0x80
        if length <= 125:
            header.append(mask_bit | length)
        elif length <= 65535:
            header.append(mask_bit | 126)
            header += struct.pack(">H", length)
        else:
            header.append(mask_bit | 127)
            header += struct.pack(">Q", length)
        mask_key = os.urandom(4)
        header += mask_key
        masked = bytes(b ^ mask_key[i % 4] for i, b in enumerate(data))
        self.sock.sendall(bytes(header) + masked)

    def _recv_frame(self):
        def recv_exact(n):
            buf = b""
            while len(buf) < n:
                chunk = self.sock.recv(n - len(buf))
                if not chunk:
                    raise ConnectionError("socket closed")
                buf += chunk
            return buf

        b1, b2 = recv_exact(2)
        opcode = b1 & 0x0F
        length = b2 & 0x7F
        if length == 126:
            length = struct.unpack(">H", recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", recv_exact(8))[0]
        payload = recv_exact(length)
        return opcode, payload

    def call(self, method, params=None, timeout_frames=50):
        self._id += 1
        msg_id = self._id
        self._send_frame(json.dumps({"id": msg_id, "method": method, "params": params or {}}).encode())
        for _ in range(timeout_frames):
            opcode, payload = self._recv_frame()
            if opcode == 0x1:
                msg = json.loads(payload.decode())
                if msg.get("id") == msg_id:
                    return msg
        raise TimeoutError(f"no response for {method}")

    def evaluate(self, expression):
        result = self.call("Runtime.evaluate", {"expression": expression, "returnByValue": True})
        val = result.get("result", {}).get("result", {})
        if "value" in val:
            return val["value"]
        if result.get("result", {}).get("exceptionDetails"):
            raise RuntimeError(result["result"]["exceptionDetails"])
        return None

    def close(self):
        self.sock.close()
