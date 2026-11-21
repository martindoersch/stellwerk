#!/usr/bin/env python3
"""Test-Hub: gibt sich als Tangent Hub aus, damit Capture One sich verbindet.

Protokoll (TIPC, aus Hammerspoon hs.tangent abgeleitet):
  TCP 127.0.0.1:64246, alles Big Endian.
  Nachricht = uint32 Länge + Body; Body beginnt mit uint32 Befehlscode.
  Strings   = uint32 Länge + Bytes.

Start:  python3 fake_tangent_hub.py
Dann Capture One starten (Tangent-Unterstützung in den Einstellungen an).
Eingaben im Terminal:
  e+  / e-     Belichtung +0,1 / -0,1
  p <id> <d>   beliebigen Parameter ändern, z. B. "p 0x26 0.5"
  r <id>       Parameter zurücksetzen
  a <id>       Aktion auslösen (ActionOn + ActionOff)
  q            beenden
"""
import socket
import struct
import sys
import threading

HOST, PORT = "127.0.0.1", 64246

# Hub -> App
INITIATE_COMMS, PARAM_CHANGE, PARAM_RESET, PARAM_VALUE_REQ = 0x01, 0x02, 0x03, 0x04
ACTION_ON, MODE_CHANGE, ACTION_OFF = 0x08, 0x09, 0x0B
# App -> Hub
APP_NAMES = {
    0x81: "ApplicationDefinition", 0x82: "ParameterValue", 0x83: "MenuString",
    0x84: "AllChange", 0x85: "ModeValue", 0x86: "DisplayText",
}

EXPOSURE = 0x26


def u32(n):
    return struct.pack(">I", n)


def send(conn, *parts):
    body = b"".join(parts)
    conn.sendall(u32(len(body)) + body)


def recv_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("Verbindung geschlossen")
        buf += chunk
    return buf


def read_string(body, off):
    (n,) = struct.unpack_from(">I", body, off)
    off += 4
    return body[off:off + n].decode("utf-8", "replace"), off + n


def describe(body):
    (cmd,) = struct.unpack_from(">I", body, 0)
    name = APP_NAMES.get(cmd, f"0x{cmd:02X}")
    try:
        if cmd == 0x81:
            app, off = read_string(body, 4)
            sysdir, off = read_string(body, off)
            userdir, off = read_string(body, off)
            return f"{name}: app={app!r} system={sysdir!r} user={userdir!r}"
        if cmd == 0x82:
            pid, val, at_default = struct.unpack_from(">IfI", body, 4)
            return f"{name}: id=0x{pid:X} wert={val:.3f} default={bool(at_default)}"
        if cmd == 0x85:
            (mode,) = struct.unpack_from(">I", body, 4)
            return f"{name}: mode=0x{mode:X}"
    except struct.error:
        pass
    return f"{name}: {body[4:].hex()}"


def reader(conn):
    try:
        while True:
            (n,) = struct.unpack(">I", recv_exact(conn, 4))
            print("<-", describe(recv_exact(conn, n)), flush=True)
    except (ConnectionError, OSError) as e:
        print("Verbindung beendet:", e, flush=True)


def handle(conn):
    # protocolRev 5, keine Panels – wir steuern Capture One direkt
    send(conn, u32(INITIATE_COMMS), u32(5), u32(0))
    threading.Thread(target=reader, args=(conn,), daemon=True).start()
    send(conn, u32(PARAM_VALUE_REQ), u32(EXPOSURE))

    for line in sys.stdin:
        cmd = line.split()
        if not cmd:
            continue
        try:
            if cmd[0] == "q":
                break
            elif cmd[0] in ("e+", "e-"):
                send(conn, u32(PARAM_CHANGE), u32(EXPOSURE),
                     struct.pack(">f", 0.1 if cmd[0] == "e+" else -0.1))
            elif cmd[0] == "p":
                send(conn, u32(PARAM_CHANGE), u32(int(cmd[1], 0)),
                     struct.pack(">f", float(cmd[2])))
            elif cmd[0] == "r":
                send(conn, u32(PARAM_RESET), u32(int(cmd[1], 0)))
            elif cmd[0] == "a":
                aid = int(cmd[1], 0)
                send(conn, u32(ACTION_ON), u32(aid))
                send(conn, u32(ACTION_OFF), u32(aid))
            else:
                print("? unbekannt")
        except (IndexError, ValueError):
            print("? Syntax prüfen")


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(1)
    print(f"Test-Hub wartet auf {HOST}:{PORT} …", flush=True)
    conn, addr = srv.accept()
    print("Verbunden:", addr, flush=True)
    handle(conn)
    conn.close()


if __name__ == "__main__":
    main()
