# TourBox Elite Plus – USB-Protokoll (getestet 2026-11-21)

Per Kabel meldet sich die TourBox als serielles Gerät (USB-CDC), z. B. `/dev/cu.usbmodem000000011`.
USB-Kennung: Hersteller `0xC251` (TourBoxTech), Produkt `0x2005` („TourBox Elite Plus").
Mitschreiber: `bridge/tourbox_monitor.swift <gerät> elite`. TourBox Console vorher beenden.

## Verbindung

- 115200 Baud, 8N1, Roh-Modus
- Ohne Start-Sequenz sendet die Elite Plus **nichts**
- Unlock: `55 00 07 88 94 00 1A FE`, dann 300 ms warten
- Konfiguration (94 Bytes, Haptik aus) – Vorlage aus tuxbox `haptic.py`:
  `B5 00 5D 04 00 05 00 06 00 07 00 08 00 09 00 0B 00 0C 00 0D 00 0E 00 0F 00 26 00 27 00 28 00 29 00 3B 00 3C 00 3D 00 3E 00 3F 00 40 00 41 00 42 00 43 00 44 00 45 00 46 00 47 00 48 00 49 00 4A 00 4B 00 4C 00 4D 00 4E 00 4F 00 50 00 51 00 52 00 53 00 54 00 A8 00 A9 00 AA 00 AB 00 FE`
  (Haptik-Stärke steht an den Stellen 4 = Knob, 14 = Scroll, 24 = Dial)
- Antwort auf Unlock/Konfiguration: ein Block von 26 Bytes → kein Tastenereignis, verwerfen (tuxbox: alles ab 20 Bytes am Stück)

## Ereignisse: ein Byte pro Druck/Raste

- Bit 7 (`0x80`) = losgelassen; Drehregler senden kein Loslassen
- Bit 6 (`0x40`) = Drehrichtung
- Rasten kommen bei schnellem Drehen alle ~20 ms

Von Martin bestätigt (Reihenfolge der Aufnahme):

| Code | Bedienelement | Lage |
|---|---|---|
| `01` | Side | links |
| `02` | Top | oben |
| `22` `23` | C1, C2 | |
| `03` | Short | rechts |
| `00` | Tall | links neben Short |
| `2A` | Tour | mittig |
| `10` `11` `12` `13` | Steuerkreuz oben, unten, links, rechts | im Uhrzeigersinn gedrückt (12 10 13 11), passt zur Neo |
| `37` | Knob drücken | großer Drehknopf |
| `38` | Dial drücken | flacher Drehregler |
| `0A` | Scroll drücken | Scrollrad |
| `44` / `04` | Knob rechts / links | |
| `4F` / `0F` | Dial rechts / links | |
| `49` / `09` | Scroll rauf / runter | |

Bit `0x40` = rechts bzw. rauf. Beim Klicken des Dials kann eine einzelne Raste mitkommen (Regler bewegt sich leicht).

Quellen: github.com/AndyCappDev/tuxbox (`device_usb.py`, `haptic.py`), github.com/jasonrohrer/tourBoxEliteLinuxDriver
