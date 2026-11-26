"""Export canonical screenshot names from an Xcode result bundle."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

LANGUAGES = ("en", "zh-Hans", "zh-Hant")
SCENES = ("01-gap", "02-task", "03-short", "04-prepare", "05-milestone")
REQUIRED = {f"store-{lang}-{scene}" for lang in LANGUAGES for scene in SCENES} | {"paid-01-paywall"}
PATTERN = re.compile(r"(?<![a-zA-Z0-9-])(" + "|".join(map(re.escape, sorted(REQUIRED))) + r")(?![a-zA-Z0-9-])")


def entries(value):
    """Walk xcresulttool's test groups and yield each exported attachment record."""
    if isinstance(value, list):
        for child in value:
            yield from entries(child)
    elif isinstance(value, dict):
        if "exportedFileName" in value:
            yield value
        for child in value.values():
            yield from entries(child)


def copy_attachments(manifest, raw, output):
    for item in entries(manifest):
        exported = Path(item["exportedFileName"]).name
        attachment = raw / exported
        original = item.get("suggestedHumanReadableName", "") or item.get("name", "")
        match = PATTERN.search(original) or PATTERN.search(exported)
        if match and attachment.is_file() and attachment.suffix.lower() == ".png":
            shutil.copyfile(attachment, output / (match[1] + ".png"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output) as directory:
        raw = Path(directory)
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(args.result),
                        "--output-path", str(raw)], check=True)
        manifest = raw / "manifest.json"
        if manifest.is_file():
            copy_attachments(json.loads(manifest.read_text(encoding="utf-8")), raw, args.output)
        for path in raw.glob("*.png"):
            match = PATTERN.search(path.name)
            if match:
                shutil.copyfile(path, args.output / (match[1] + ".png"))
    missing = sorted(name for name in REQUIRED if not (args.output / (name + ".png")).is_file())
    if missing:
        parser.exit(1, "Missing screenshot attachments: " + ", ".join(missing) + "\n")
    print(f"Exported {len(REQUIRED)} named screenshots to {args.output}")


if __name__ == "__main__":
    main()
