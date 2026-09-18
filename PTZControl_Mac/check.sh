#!/bin/bash
set -eu
cd "$(dirname "$0")"
# Compile a stable snapshot away from cloud-backed project metadata changes.
task_build_dir=$(mktemp -d /private/tmp/ptz-check.XXXXXX)
mkdir -p .build "$task_build_dir/Tests" "$task_build_dir/Diagnostics"
cp PTZControl_Mac/USBBridge.c PTZControl_Mac/USBBridge.h PTZControl_Mac/UVCDescriptors.swift PTZControl_Mac/ImageControls.swift PTZControl_Mac/ZoomState.swift PTZControl_Mac/PTZCameraController.swift PTZControl_Mac/USBTransport.swift PTZControl_Mac/USBCameraControl.swift "$task_build_dir/"
cp Tests/main.swift "$task_build_dir/Tests/"
cp Diagnostics/main.swift "$task_build_dir/Diagnostics/"
xcrun clang -arch arm64 -mmacosx-version-min=14.0 -c "$task_build_dir/USBBridge.c" -o "$task_build_dir/USBBridge.o"
sources=("$task_build_dir/ImageControls.swift" "$task_build_dir/ZoomState.swift" "$task_build_dir/UVCDescriptors.swift" "$task_build_dir/PTZCameraController.swift" "$task_build_dir/USBTransport.swift" "$task_build_dir/USBCameraControl.swift")
for target in Tests Diagnostics; do
    xcrun swiftc -target arm64-apple-macos14.0 -module-cache-path "$task_build_dir/ModuleCache" -import-objc-header "$task_build_dir/USBBridge.h" "${sources[@]}" "$task_build_dir/$target/main.swift" "$task_build_dir/USBBridge.o" -framework IOKit -framework CoreFoundation -o "$task_build_dir/$target/run"
    cp "$task_build_dir/$target/run" ".build/$target"
done
"$task_build_dir/Tests/run"
