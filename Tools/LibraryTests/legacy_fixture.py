#!/usr/bin/env python3
"""Seed/verify a legacy fixture only in a newly created MiNote migration simulator."""
import argparse
import json
import pathlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("device")
parser.add_argument("--verify", action="store_true")
args = parser.parse_args()

def simctl(*items):
    return subprocess.check_output(["xcrun", "simctl", *items], text=True).strip()

devices = json.loads(simctl("list", "devices", "available", "-j"))["devices"]
device = next(d for group in devices.values() for d in group if d["udid"] == args.device)
if not device["name"].startswith(("MiNote M1-A Migration ", "MiNote M1-B Migration ")):
    raise SystemExit("Refusing to seed a general-purpose simulator.")
container = pathlib.Path(simctl("get_app_container", args.device, "com.minote.foundation", "data"))
root = container / "Documents" / "MiNote"
fixture = pathlib.Path(__file__).resolve().parents[2] / "Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk"
raw = (fixture / "source.json").read_bytes()
document = json.loads(raw)
asset = document["pdfAsset"]
asset_path = "assets/" + asset["id"].upper() + ".pdf"
pdf = (fixture / "source.pdf").read_bytes()
if args.verify:
    assert (root / "document.json").read_bytes() == raw
    assert (root / "document.backup.json").read_bytes() == raw
    assert (root / asset_path).read_bytes() == pdf
    catalog = json.loads((root / "library.json").read_bytes())
    assert [note["id"].lower() for note in catalog["notes"]] == [document["id"].lower()]
    migrated = root / "notes" / document["id"]
    actual = json.loads((migrated / "document.json").read_bytes())
    expected_pages = json.loads(json.dumps(document["pages"]))
    for page in expected_pages:
        page["paper"] = "blank"; page["isBookmarked"] = False
        if page.get("pdfSource"): page["pdfSource"]["assetID"] = asset["id"]
    assert actual["schemaVersion"] == 3
    assert actual["id"] == document["id"] and actual["pages"] == expected_pages
    assert actual["pdfAssets"] == [asset] and actual["deletedPages"] == []
    assert actual["revision"] > document["revision"]
    assert (migrated / asset_path).read_bytes() == pdf
    assert (migrated / "document.backup.json").exists()
    print("Migration UI fixture: original JSON/backup/PDF unchanged, migrated IDs/ink/PDF preserved")
else:
    if root.exists():
        raise SystemExit("Refusing to replace existing MiNote data. Create a fresh migration simulator.")
    (root / "assets").mkdir(parents=True)
    (root / "document.json").write_bytes(raw)
    (root / "document.backup.json").write_bytes(raw)
    (root / asset_path).write_bytes(pdf)
    print("Seeded isolated legacy fixture:", args.device)
