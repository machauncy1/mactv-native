#!/usr/bin/env python3
"""Exercise the real helper's pipes, TCP lifecycle and pre-auth rejection."""
import json
import os
from pathlib import Path
import secrets
import selectors
import socket
import subprocess
import sys
import tempfile
import time
import uuid

binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="mactv-receiver-test-") as directory:
    process = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    buffer = bytearray()

    def event(timeout=8):
        until = time.monotonic() + timeout
        while time.monotonic() < until:
            if b"\n" in buffer:
                line, _, rest = buffer.partition(b"\n")
                buffer[:] = rest
                return json.loads(line)
            if selector.select(max(0, until - time.monotonic())):
                data = os.read(process.stdout.fileno(), 65536)
                if not data:
                    raise AssertionError("helper exited before expected event")
                buffer.extend(data)
        raise AssertionError("timed out waiting for helper event")

    try:
        config = dict(name="MacTV receiver IPC test", pin=secrets.randbelow(9000) + 1000,
                      serverId=str(uuid.uuid4()).upper(), deviceId="02:12:34:56:78:90",
                      privateKey=secrets.token_hex(32), stateDirectory=directory)
        process.stdin.write(json.dumps(config).encode() + b"\n")
        process.stdin.flush()
        ready = event()
        assert ready["type"] == "started" and ready["pairingOpen"]
        port = ready["companionPort"]
        with socket.create_connection(("127.0.0.1", port), timeout=3) as client:
            connected = event()
            assert connected == dict(type="connection", connected=True, ready=False)
            # An encrypted-control frame before pair-verify must not reach App commands.
            client.sendall(bytes([8, 0, 0, 1, 0]))
            disconnected = event()
            assert disconnected == dict(type="connection", connected=False, ready=False)
            assert client.recv(1) == b""
        children = subprocess.check_output(["pgrep", "-P", str(process.pid)], text=True).splitlines()
        process.stdin.close()  # Simulate the app exiting, including an unexpected parent exit.
        assert event()["type"] == "stopped"
        assert process.wait(timeout=8) == 0
        for pid in children:
            try:
                os.kill(int(pid), 0)
            except ProcessLookupError:
                continue
            raise AssertionError("orphan Bonjour helper remained")
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
        except OSError:
            pass
        else:
            raise AssertionError("receiver port survived parent EOF")
        print("PASS: receiver startup, TCP connect/disconnect state, pre-auth rejection, parent EOF and Bonjour cleanup")
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=8)
        selector.close()
