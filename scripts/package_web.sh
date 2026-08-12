#!/bin/bash
set -e

OUTPUT_DIR="web-output"

echo "Packaging web build for GitHub Pages deployment..."

# Verify web output directory exists
if [ ! -d "$OUTPUT_DIR" ]; then
  echo "Error: web-output directory not found!"
  exit 1
fi

# NOTE: We deliberately do NOT copy a custom index.html here anymore.  
# build-scripts/prepare-web.sh (run in build_web.sh) already copies CDDA's  
# own official build-data/web/index.html into the output. That page loads  
# cataclysm-tiles.data.js BEFORE cataclysm-tiles.js in the correct order -  
# a custom page that skips loading .data.js will hang forever on load.

# Create a nojekyll file to prevent GitHub Pages from processing
touch "$OUTPUT_DIR/.nojekyll"

# Create a simple README for the deployment
cat > "$OUTPUT_DIR/README.md" << 'EOF'
# CDDA WebAssembly Build

This is the WebAssembly build of Cataclysm: Dark Days Ahead, deployed via GitHub Actions.

## How to Play

Simply open index.html in a modern web browser that supports WebAssembly.

## Controls

The game supports keyboard and mouse controls similar to the desktop version.

## Build Information

Built automatically via GitHub Actions from the CleverRaven/cataclysm-dda repository.
EOF

# Generate build info file
if [ -f "BUILD_VERSION" ]; then
  cp BUILD_VERSION "$OUTPUT_DIR/"
fi

# Create a manifest file with build information
cat > "$OUTPUT_DIR/BUILD_INFO.json" << EOF
{
  "build_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "build_type": "${BUILD_TYPE:-Release}",
  "tiles": "${BUILD_TILES:-true}",
  "sound": "${BUILD_SOUND:-true}",
  "localization": "${BUILD_LOCALIZATION:-false}",
  "emscripten_version": "${EMSCRIPTEN_VERSION:-3.1.51}"
}
EOF

# Verify critical files exist
echo "Verifying critical files..."
CRITICAL_FILES=("cataclysm-tiles.js" "cataclysm-tiles.wasm" "cataclysm-tiles.data" "cataclysm-tiles.data.js" "index.html")
for file in "${CRITICAL_FILES[@]}"; do
  if [ ! -f "$OUTPUT_DIR/$file" ]; then
    echo "Warning: Critical file $file not found in web output directory"
  fi
done

# Display directory structure
echo "Web output directory structure:"
ls -la "$OUTPUT_DIR/"

echo "Packaging completed successfully!"
echo "Web output directory: $OUTPUT_DIR"
echo "Files ready for GitHub Pages deployment"
