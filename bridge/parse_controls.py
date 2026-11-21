#!/usr/bin/env python3
"""Liest Capture Ones Tangent-Regler-Liste (controls.xml) und erzeugt:

  - docs/capture-one-controls.md          Tabelle zum Nachschlagen
  - bridge/mappings/capture-one-controls.json  Maschinenlesbar für die Bridge

Zusätzlich wird markiert, welche IDs Tangent in seinen Standard-Belegungen
(element-*.xml, wave-map.xml, ripple-map.xml) verwendet: Das sind gute
Kandidaten für die Belegung des Loupedeck+.

Aufruf:  python3 bridge/parse_controls.py [Pfad/zu/TangentSettings]
Nur Python-Standardbibliothek.
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

DEFAULT_DIR = Path("/Applications/Capture One.app/Contents/Resources/TangentSettings")
ROOT = Path(__file__).resolve().parent.parent


def default_map_usage(settings_dir: Path) -> dict[int, set[str]]:
    """ID -> Menge der Standard-Belegungen, in denen sie vorkommt."""
    usage: dict[int, set[str]] = {}
    for f in sorted(settings_dir.glob("*map*.xml")):
        name = f.stem.replace("-map", "")
        for m in re.finditer(r"<Key>(0x[0-9A-Fa-f]+)</Key>", f.read_text(encoding="utf-8")):
            key = int(m.group(1), 16)
            if key < 0x80000000:  # 0x8000xxxx sind Hub-interne Funktionen
                usage.setdefault(key, set()).add(name)
    return usage


def parse(settings_dir: Path) -> dict:
    tree = ET.parse(settings_dir / "controls.xml")
    root = tree.getroot()
    usage = default_map_usage(settings_dir)

    modes = [
        {"id": m.get("id"), "name": m.findtext("Name")}
        for m in root.iter("Mode")
    ]
    groups = []
    for g in root.find("Controls").findall("Group"):
        items = []
        for el in g:
            id_hex = el.get("id")
            item = {
                "kind": "parameter" if el.tag == "Parameter" else "action",
                "id": id_hex,
                "name": el.findtext("Name"),
                "short": el.findtext("Name9"),
                "inDefaultMaps": sorted(usage.get(int(id_hex, 16), [])),
            }
            if el.tag == "Parameter":
                item["min"] = float(el.findtext("MinValue"))
                item["max"] = float(el.findtext("MaxValue"))
                item["step"] = float(el.findtext("StepSize"))
            items.append(item)
        groups.append({"name": g.get("name"), "items": items})
    return {"source": str(settings_dir / "controls.xml"), "modes": modes, "groups": groups}


def fmt(x: float) -> str:
    return f"{x:g}".replace(".", ",")


def to_markdown(data: dict) -> str:
    all_items = [i for g in data["groups"] for i in g["items"]]
    n_par = sum(i["kind"] == "parameter" for i in all_items)
    n_act = len(all_items) - n_par
    out = [
        "# Capture One: Tangent-Regler und -Aktionen",
        "",
        "Automatisch erzeugt von `bridge/parse_controls.py` aus `controls.xml`. Nicht von Hand bearbeiten,",
        "nach Capture-One-Updates neu erzeugen und per `git diff` auf geänderte IDs prüfen.",
        "",
        f"**{n_par} Regler (Parameter), {n_act} Aktionen, {len(data['groups'])} Gruppen.** "
        "Modi: " + ", ".join("%s (`%s`)" % (m["name"], m["id"]) for m in data["modes"]) + ".",
        "",
        "- **Regler** werden mit `ParameterChange` (ID + Delta) verstellt, `Reset` setzt zurück, `ValueRequest` fragt den Wert ab.",
        "- **Aktionen** werden mit `ActionOn` (und `ActionOff`) ausgelöst. Sie entsprechen den Menüpunkten/Tastenkürzeln.",
        "- **Std.-Map**: ID kommt in einer Tangent-Standardbelegung vor (bt/kb/mf/tk = Element-Panels, wave, ripple). Gute Kandidaten für die Loupedeck-Belegung.",
        "",
        "## Übersicht",
        "",
        "| Gruppe | Regler | Aktionen |",
        "|---|---:|---:|",
    ]
    for g in data["groups"]:
        p = sum(i["kind"] == "parameter" for i in g["items"])
        out.append(f"| [{g['name']}](#{anchor(g['name'])}) | {p or ''} | {(len(g['items']) - p) or ''} |")

    out += ["", "## Alle Regler", "", "| ID | Name | Gruppe | Min | Max | Schritt | Std.-Map |", "|---|---|---|---:|---:|---:|---|"]
    for g in data["groups"]:
        for i in g["items"]:
            if i["kind"] == "parameter":
                out.append(
                    f"| `{i['id']}` | {i['name']} | {g['name']} | {fmt(i['min'])} | {fmt(i['max'])} | {fmt(i['step'])} | {', '.join(i['inDefaultMaps'])} |"
                )

    out += ["", "## Alle Aktionen nach Gruppe"]
    for g in data["groups"]:
        acts = [i for i in g["items"] if i["kind"] == "action"]
        out += ["", f"### {g['name']}", ""]
        if not acts:
            out.append("_Nur Regler, siehe oben._")
            continue
        out += ["| ID | Name | Std.-Map |", "|---|---|---|"]
        for i in acts:
            name = i["name"].replace("|", "\\|")
            out.append(f"| `{i['id']}` | {name} | {', '.join(i['inDefaultMaps'])} |")
    return "\n".join(out) + "\n"


def anchor(s: str) -> str:
    return re.sub(r"[^a-z0-9 -]", "", s.lower()).replace(" ", "-")


def main() -> None:
    settings_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DIR
    data = parse(settings_dir)
    (ROOT / "docs").mkdir(exist_ok=True)
    (ROOT / "bridge/mappings").mkdir(parents=True, exist_ok=True)
    md_path = ROOT / "docs/capture-one-controls.md"
    json_path = ROOT / "bridge/mappings/capture-one-controls.json"
    md_path.write_text(to_markdown(data), encoding="utf-8")
    json_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"geschrieben: {md_path.relative_to(ROOT)}, {json_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
