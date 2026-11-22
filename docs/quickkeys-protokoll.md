# Xencelabs Quick Keys – HID-Protokoll

Stand: 2026-11-22, am echten Gerät über den Funk-Dongle bestätigt (`bridge/quickkeys_monitor.swift`).
Quelle: [Julusian/node-xencelabs-quick-keys](https://github.com/Julusian/node-xencelabs-quick-keys) (`packages/core/src/device.ts`, `wireless-device.ts`).

## Gerät

- Hersteller `0x28BD`, Produkt `0x5202` = Kabel, `0x5203` = Funk-Dongle (der Dongle bedient auch das Xencelabs-Tablett, bis zu 2 Quick Keys)
- Dongle-Schnittstellen: `0x0001/0x0002` Maus, **`0xFF0A/0x0001` Herstellerkanal (Quick Keys)**, `0x000D/0x0002` Stift
- Reports: 32 Byte, Report-ID `0x02`. macOS liefert die Report-ID als Byte 0 mit; die Offsets unten zählen sie mit (in node um 1 kleiner)
- Kein Treiber nötig. Der Xencelabs-Treiber liest parallel mit (nicht exklusiv)

## Anmelden

| Schritt | Report (Byte 1, 2, …) |
|---|---|
| Dongle: Geräte melden | `B8 01` → Antwort `F8` |
| Antwort `F8` | Byte 2 = Status (`2` verbunden, `3` schon verbunden, `4` Verbindung verloren), Byte 10–15 = Geräte-ID |
| Ereignisse abonnieren | `B0 04` |
| Akku abonnieren | `B4 10` → `F2 01 <Prozent>` |

Beim Dongle steht in **jedem gesendeten Report** die Geräte-ID in Byte 10–15; in Ereignissen steht sie in Byte 12–17.

## Ereignisse (`F0`)

- Byte 7 ≠ 0: Rad, `01` = rechts, `02` = links, eine Meldung pro Raste (~10 pro Sekunde beim zügigen Drehen, keine Beschleunigung)
- sonst Tasten als Bitmaske, Byte 2 = Tasten 0–7 (mit Display), Byte 3 Bit 0 = **Taste unten (8)**, Bit 1 = **Knopf im Rad (9)**

## Ausgabe

| Was | Report |
|---|---|
| Text neben Taste 0–7 | `B1`, Byte 3 = Taste + 1, Byte 5 = Länge × 2, UTF-16LE ab Byte 16 (max. 8 Zeichen) |
| Einblendung (max. 32 Zeichen) | Blöcke zu 8 Zeichen: erster `B1 05`, weitere `B1 06`; Byte 3 = Sekunden, Byte 5 = Länge × 2, Byte 6 = es folgt noch ein Block (beim ersten immer 0), Text ab Byte 16. **Immer mindestens einen `06`-Block schicken**, sonst erscheint nichts |
| Ringfarbe | `B4 01 01`, Byte 6–8 = R, G, B |
| Helligkeit | `B1 0A 01`, Byte 4 = Stufe |
| Ausrichtung | `B1`, Byte 2 = Ausrichtung |
| Radgeschwindigkeit | `B4 04 01 01`, Byte 5 = Stufe |
| Ruhezustand | `B4 08 01`, Byte 4 = Minuten |

Über Funk dauert ein gesendeter Report ~16 ms → Stellwerk sendet auf eigener Warteschlange und bündelt Display-Updates (60 ms).

**Schrift:** Das Display kennt kein ß („Weiß“ erscheint als „Wei“), Stellwerk schreibt „ss“. Umlaute noch ungetestet.
