"""
Packs the openfootball JSON files in data/source_json into one landing file,
data/raw/api_landing.jsonl, with one JSON document per line.

Each line is an envelope: where the data came from plus the untouched
payload. This is the same shape an API extract job would write, and it lets
SQL Server load every file with a single BULK INSERT.

    python tools/build_landing_file.py
"""
import json
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
src = root / "data" / "source_json"
out = root / "data" / "raw" / "api_landing.jsonl"

with out.open("w", encoding="utf-8", newline="\n") as fh:
    for path in sorted(src.glob("*.json")):
        league, season = path.stem.split("_")
        envelope = {
            "source_file": path.name,
            "source_url": f"https://github.com/openfootball/football.json/blob/master/{season}/{league}.json",
            "league_code": league,
            "season": season,
            "payload": json.loads(path.read_text(encoding="utf-8")),
        }
        fh.write(json.dumps(envelope, ensure_ascii=False, separators=(",", ":")) + "\n")

print(f"wrote {out}")
