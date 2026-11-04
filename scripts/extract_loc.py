#!/usr/bin/env python3
"""Collects the localized string keys the Swift compiler found (-emit-localized-strings, which
writes one .stringsdata file per source) into a sorted key list.

  extract_loc.py DIR OUT [COMMITTED]

Reads every *.stringsdata under DIR, keeps table Localizable, drops sources under a Tests
directory and fails on any other table. Writes OUT as {"keys": [{"key", "comment"}]}. With
COMMITTED, prints the keys added and removed against that list as Markdown and exits 1 when
they differ.
"""
import json
import sys
from pathlib import Path


def collect(root):
    keys = {}
    for path in sorted(Path(root).rglob("*.stringsdata")):
        data = json.loads(path.read_text(encoding="utf-8"))
        source = data.get("source", "").replace("\\", "/")
        if "/Tests/" in source:
            continue
        for table, entries in data.get("tables", {}).items():
            if table != "Localizable":
                sys.exit("%s: unexpected table %s" % (source, table))
            for entry in entries:
                if entry["key"] not in keys or not keys[entry["key"]]:
                    keys[entry["key"]] = entry.get("comment") or ""
    return keys


def write(keys, out):
    lines = [json.dumps({"key": k, "comment": keys[k]}, ensure_ascii=False) for k in sorted(keys)]
    Path(out).write_text('{"keys": [\n ' + ",\n ".join(lines) + "\n]}\n", encoding="utf-8")


def main(args):
    if len(args) not in (2, 3):
        sys.exit(__doc__)
    keys = collect(args[0])
    write(keys, args[1])
    print("%d keys" % len(keys), file=sys.stderr)
    if len(args) == 2:
        return 0
    old = {e["key"] for e in json.loads(Path(args[2]).read_text(encoding="utf-8"))["keys"]}
    added, removed = sorted(set(keys) - old), sorted(old - set(keys))
    if not added and not removed:
        print("The key list matches %s." % args[2])
        return 0
    print("Key list differs from %s: %d added, %d removed." % (args[2], len(added), len(removed)))
    for label, items in (("Added", added), ("Removed", removed)):
        if items:
            print("\n%s\n" % label)
            for item in items:
                print("- `%s`" % item.replace("`", "'"))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
