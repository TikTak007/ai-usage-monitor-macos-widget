from pathlib import Path
import shutil, subprocess, sys, tempfile
root = Path(__file__).resolve().parent.parent
products = root / ".build/debug"
if not products.is_dir():
    raise SystemExit("Run swift build or swift test before the native layout regression")
with tempfile.TemporaryDirectory(prefix="menu-layout-") as directory:
    work = Path(directory)
    panel = (root / "Sources/CodexUsageMonitorApp/UsagePanel.swift").read_text()
    # Isolate preferences; the fixture has no account/notification implementation.
    panel = panel.replace('@AppStorage("appearanceMode")', '@State')
    (work / "UsagePanel.swift").write_text(panel)
    app = work / "NativeLayout.app"
    executable = app / "Contents/MacOS/NativeLayout"
    executable.parent.mkdir(parents=True)
    resources = app / "Contents/Resources"
    resources.mkdir()
    for image in (root / "Sources/CodexUsageShared/Resources").glob("*.png"):
        shutil.copy2(image, resources / image.name)
    for bundle in products.glob("*_CodexUsageShared.bundle"):
        shutil.copytree(bundle, resources / bundle.name)
    (app / "Contents/Info.plist").write_text('<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleExecutable</key><string>NativeLayout</string><key>CFBundleIdentifier</key><string>local.synthetic.menu-layout</string></dict></plist>')
    command = ["swiftc", "-parse-as-library", "-I", str(products),
        str(root / "tests/MenuPanelLayoutChecks.swift"), str(work / "UsagePanel.swift"),
        str(root / "Sources/CodexUsageMonitorApp/CreditsBalanceCard.swift"),
        str(root / "Sources/CodexUsageMonitorApp/WeeklyUsageChart.swift"),
        str(products / "CodexUsageCore.o"), str(products / "CodexUsageShared.o"),
        "-o", str(executable)]
    subprocess.run(command, check=True)
    subprocess.run([str(executable), *sys.argv[1:]], check=True, timeout=60)
