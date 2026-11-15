#!/usr/bin/env python3
"""Pick an available iPhone simulator and write an xcodebuild destination."""

import json
import os
import re
import subprocess
import sys

raw = subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"],
    text=True,
)
devices_by_runtime = json.loads(raw).get("devices", {})

best = None
for runtime, devices in devices_by_runtime.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        if not device.get("isAvailable"):
            continue
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        # Prefer the plain iPhone 17 on the newest runtime. Names drift between images.
        rank = (version, 1 if name == "iPhone 17" else 0, name)
        if best is None or rank > best[0]:
            best = (rank, name, device["udid"])

if best is None:
    sys.stderr.write("No available iPhone simulator.\n")
    sys.exit(1)

_, name, udid = best
destination = f"platform=iOS Simulator,id={udid}"
print(f"Using {name} ({udid})")

output = os.environ.get("GITHUB_OUTPUT")
if output:
    with open(output, "a", encoding="utf-8") as handle:
        handle.write(f"destination={destination}\n")
else:
    print(destination)
