#!/bin/bash
set -eu
cd "$(dirname "$0")"
task_demo_dir=$(mktemp -d /private/tmp/ptz-demo-test.XXXXXX)
xcrun clang -arch arm64 -mmacosx-version-min=14.0 -c PTZControl_Mac/USBBridge.c -o "$task_demo_dir/USBBridge.o"
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 -module-cache-path "$task_demo_dir/ModuleCache" -import-objc-header PTZControl_Mac/USBBridge.h PTZControl_Mac/{CameraController,ImageControls,ZoomState,UVCDescriptors,PTZCameraController,USBTransport,USBCameraControl}.swift DemoTests/main.swift "$task_demo_dir/USBBridge.o" -framework IOKit -framework CoreFoundation -o "$task_demo_dir/run"
"$task_demo_dir/run"
