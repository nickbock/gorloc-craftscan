#!/usr/bin/env python3
"""Build an installable ZIP containing only the GorlocCraftScan add-on and its license."""

from pathlib import Path
import re
import zipfile

root = Path(__file__).resolve().parents[1]
addon = root / "GorlocCraftScan"
toc = addon / "GorlocCraftScan.toc"
version = re.search(r"^## Version: (.+)$", toc.read_text(), re.MULTILINE).group(1)
files = [toc]
for line in toc.read_text().splitlines():
    if line and not line.startswith("#"):
        source = addon / line
        if not source.is_file():
            raise SystemExit(f"Missing TOC file: {source}")
        files.append(source)
# MIT requires the license text to ship with every copy.
files.append(root / "LICENSE")

destination = root / "dist" / f"GorlocCraftScan-{version}.zip"
destination.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for source in files:
        entry = zipfile.ZipInfo(f"GorlocCraftScan/{source.name}", date_time=(2026, 1, 1, 0, 0, 0))
        entry.compress_type = zipfile.ZIP_DEFLATED
        entry.external_attr = 0o100644 << 16
        archive.writestr(entry, source.read_bytes())

with zipfile.ZipFile(destination) as archive:
    assert archive.testzip() is None
    assert len(archive.namelist()) == len(files)
print(f"Built {destination.relative_to(root)} ({len(files)} files)")
