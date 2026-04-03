#!/bin/bash

# Generate dSYM for WebRTC framework
# This script generates the dSYM from the WebRTC framework binary and places it in the dSYM folder

WEBRTC_FRAMEWORK_PATH="${PODS_XCFRAMEWORKS_BUILD_DIR}/SignalRingRTC/WebRTC/WebRTC.framework"
DSYM_OUTPUT_PATH="${DWARF_DSYM_FOLDER_PATH}/WebRTC.framework.dSYM"

if [ ! -d "${WEBRTC_FRAMEWORK_PATH}" ]; then
    echo "Warning: WebRTC framework not found at ${WEBRTC_FRAMEWORK_PATH}"
    exit 0
fi

# Check if dSYM already exists
if [ -d "${DSYM_OUTPUT_PATH}" ]; then
    echo "dSYM already exists at ${DSYM_OUTPUT_PATH}"
    exit 0
fi

# Get the binary name from the framework
BINARY_NAME=$(basename "${WEBRTC_FRAMEWORK_PATH}" .framework)
BINARY_PATH="${WEBRTC_FRAMEWORK_PATH}/${BINARY_NAME}"

if [ ! -f "${BINARY_PATH}" ]; then
    echo "Warning: WebRTC binary not found at ${BINARY_PATH}"
    exit 0
fi

# Generate dSYM using dsymutil
echo "Generating dSYM for WebRTC framework..."
if dsymutil "${BINARY_PATH}" -o "${DSYM_OUTPUT_PATH}" 2>&1; then
    echo "Successfully generated dSYM at ${DSYM_OUTPUT_PATH}"
else
    echo "Warning: Failed to generate dSYM for WebRTC (this may be expected if dsymutil is not available)"
    exit 0
fi

