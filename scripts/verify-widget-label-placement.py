#!/usr/bin/env python3
"""Run native macOS geometry checks against the production widget placement helper."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = (root / "Sources/CodexUsageWidget/WeeklyGraphWidget.swift").read_text()
helper = "enum GraphLabelPlacement {" + source.split("enum GraphLabelPlacement {", 1)[1]
checks = (root / "tests/WidgetLabelPlacementChecks.swift").read_text()
with tempfile.TemporaryDirectory(prefix="widget-label-check-") as folder:
    fixture = Path(folder) / "PlacementCheck.swift"
    fixture.write_text("import AppKit\n" + helper + "\n" + checks)
    subprocess.run(["swift", str(fixture)], check=True)
