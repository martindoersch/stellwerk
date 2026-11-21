#!/usr/bin/env python3
"""Test-Client: gibt sich als Capture One aus und verbindet sich mit dem Hub
(stellwerk.swift) auf 127.0.0.1:64246. Zum Testen der Bridge ohne Capture One.

Verhält sich wie Capture One: meldet sich mit ApplicationDefinition an,
merkt sich Reglerwerte, antwortet auf ParameterChange/Reset/ValueRequest mit
ParameterValue und protokolliert Aktionen.

Start:  python3 fake_captureone.py
"""
import socket
import struct

HOST, PORT = "127.0.0.1", 64246
values = {}


def u32(n):
    return struct.pack(">I", n)


def string(s):
    b = s.encode()
    return u32(len(b)) + b


def send(sock, body):
    sock.sendall(u32(len(body)) + body)


def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("Hub hat die Verbindung geschlossen")
        buf += chunk
    return buf


def report(sock, pid):
    v = values.get(pid, 0.0)
    send(sock, u32(0x82) + u32(pid) + struct.pack(">f", v) + u32(int(v == 0.0)))


def main():
    sock = socket.create_connection((HOST, PORT))
    print("verbunden", flush=True)
    while True:
        (n,) = struct.unpack(">I", recv_exact(sock, 4))
        body = recv_exact(sock, n)
        (cmd,) = struct.unpack_from(">I", body, 0)
        if cmd == 0x01:
            rev, panels = struct.unpack_from(">II", body, 4)
            print(f"InitiateComms rev={rev} panels={panels}", flush=True)
            send(sock, u32(0x81) + string("Capture One (Fake)") + string("/sys") + string("/user"))
        elif cmd == 0x02:
            pid, delta = struct.unpack_from(">If", body, 4)
            values[pid] = values.get(pid, 0.0) + delta
            print(f"ParameterChange 0x{pid:X} {delta:+.3f} -> {values[pid]:.3f}", flush=True)
            report(sock, pid)
        elif cmd == 0x03:
            (pid,) = struct.unpack_from(">I", body, 4)
            values[pid] = 0.0
            print(f"Reset 0x{pid:X}", flush=True)
            report(sock, pid)
        elif cmd == 0x04:
            (pid,) = struct.unpack_from(">I", body, 4)
            report(sock, pid)
        elif cmd in (0x08, 0x0B):
            (aid,) = struct.unpack_from(">I", body, 4)
            print(f"{'ActionOn ' if cmd == 0x08 else 'ActionOff'} 0x{aid:X}", flush=True)
        else:
            print(f"Befehl 0x{cmd:X}: {body[4:].hex()}", flush=True)


if __name__ == "__main__":
    main()
