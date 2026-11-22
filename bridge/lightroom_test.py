#!/usr/bin/env python3
"""Test-Client für das Stellwerk-Plug-in in Lightroom Classic (lightroom/Stellwerk.lrplugin).

Liest die Ports aus ~/Library/Application Support/Stellwerk/lightroom-ports, verbindet sich
mit beiden und zeigt alles, was Lightroom meldet. Befehle werden zeilenweise eingetippt, z. B.
    watch Exposure2012,Contrast2012
    change Exposure2012 0.1
    reset Exposure2012
    do next
Siehe Kopf von Init.lua für alle Befehle. Ohne Eingabe: Strg-D beendet.

Start:  python3 bridge/lightroom_test.py          (interaktiv)
        python3 bridge/lightroom_test.py --demo   (Belichtung +0,1 ×5, dann zurück)
"""
import os
import socket
import sys
import threading
import time

PORT_FILE = os.path.expanduser("~/Library/Application Support/Stellwerk/lightroom-ports")


def read_ports():
    try:
        with open(PORT_FILE) as f:
            receive, send = f.read().strip().split("|")[:2]   # dahinter: Startzeit der Plug-in-Fassung
        return int(receive), int(send)
    except (OSError, ValueError):
        sys.exit(f"Keine Portdatei ({PORT_FILE}) – läuft Lightroom mit dem Stellwerk-Plug-in?")


def listen(sock):
    buf = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            print("\n[Lightroom hat die Verbindung geschlossen]")
            os._exit(0)
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            print(f"  ← {line.decode(errors='replace')}")


def main():
    to_lr, from_lr = read_ports()
    out = socket.create_connection(("127.0.0.1", to_lr))
    inp = socket.create_connection(("127.0.0.1", from_lr))
    print(f"Verbunden (Befehle → {to_lr}, Meldungen ← {from_lr})")
    threading.Thread(target=listen, args=(inp,), daemon=True).start()

    def send(line):
        print(f"  → {line}")
        out.sendall((line + "\n").encode())

    if "--demo" in sys.argv:
        send("watch Exposure2012")
        time.sleep(0.5)
        for _ in range(5):
            send("change Exposure2012 0.1")
            time.sleep(0.3)
        time.sleep(1)
        send("reset Exposure2012")
        time.sleep(1)
        return

    for line in sys.stdin:
        if line.strip():
            send(line.strip())
    time.sleep(0.5)


if __name__ == "__main__":
    main()
