"""Checks that every platform's version is the one in VERSION."""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
version = (root / "VERSION").read_text().strip()

places = [
    ("ios/project.yml", r'MARKETING_VERSION:\s*"([^"]+)"'),
    ("mac/project.yml", r'MARKETING_VERSION:\s*"([^"]+)"'),
    ("scripts/make_app.sh", r"CFBundleShortVersionString</key><string>([^<]+)<"),
]
failed = False
for path, pattern in places:
    match = re.search(pattern, (root / path).read_text())
    found = match.group(1) if match else None
    if found != version:
        print(f"{path} has version {found}, VERSION says {version}")
        failed = True
sys.exit(1 if failed else 0)
