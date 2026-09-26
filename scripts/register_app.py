#!/usr/bin/env python3
"""Register this build and restart only its app and embedded widget processes."""
from pathlib import Path
import os
import plistlib
import signal
import subprocess
import time

root = Path(__file__).resolve().parent.parent
with (root / "macos/Info.plist").open("rb") as source:
    info = plistlib.load(source)
app = root / "dist" / (info["CFBundleName"] + ".app")
extension = app / "Contents/PlugIns/CodexUsageWidget.appex"
for bundle in (extension, app):
    subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)
with (extension / "Contents/Info.plist").open("rb") as source:
    widget_info = plistlib.load(source)
executables = {
    str(app / "Contents/MacOS" / info["CFBundleExecutable"]),
    str(extension / "Contents/MacOS" / widget_info["CFBundleExecutable"]),
}
rows = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True).splitlines()
pids = []
for row in rows:
    fields = row.strip().split(None, 1)
    if len(fields) == 2 and fields[1] in executables:
        pids.append(int(fields[0]))
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
# The old widget executable can stay suspended across an in-place rebuild.
# Re-registration must not leave that process serving the previous WidgetBundle.
deadline = time.monotonic() + 5
while pids and time.monotonic() < deadline:
    alive = []
    for pid in pids:
        try:
            os.kill(pid, 0)
            alive.append(pid)
        except ProcessLookupError:
            pass
    pids = alive
    if pids:
        time.sleep(0.1)
if pids:
    raise SystemExit("対象アプリの終了を確認できません。登録は変更していません。")
lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
registered = subprocess.check_output(
    ["pluginkit", "-m", "-A", "-D", "-v", "-i", widget_info["CFBundleIdentifier"]],
    text=True,
)
if any(line.endswith("\t" + str(extension)) for line in registered.splitlines()):
    subprocess.run(["pluginkit", "-r", str(extension)], check=True)
subprocess.run([lsregister, "-f", str(app)], check=True)
subprocess.run(["pluginkit", "-a", str(extension)], check=True)
subprocess.run(["open", str(app)], check=True)
print("アプリとウィジェットの登録を更新しました。ウィジェット編集画面を開き直してください。")
