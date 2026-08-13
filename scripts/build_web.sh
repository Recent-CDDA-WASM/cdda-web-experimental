#!/bin/bash  
set -e  
  
SOURCE_DIR="cdda-source"  
OUTPUT_DIR="web-output"  
  
echo "Starting CDDA WebAssembly build (experimental) using official build scripts..."  
  
# Capture the repo checkout root BEFORE we cd into the source tree, so we can  
# reliably find vendored files (coi-serviceworker.min.js, error-overlay.js,  
# and the patched mmap_file.cpp / cata_allocator.cpp) later.  
REPO_ROOT="$(pwd)"  
  
SOURCE_ABS_PATH="$(pwd)/$SOURCE_DIR"  
OUTPUT_ABS_PATH="$(pwd)/$OUTPUT_DIR"  
echo "Source directory: $SOURCE_ABS_PATH"  
echo "Output directory: $OUTPUT_ABS_PATH"  
  
if [ ! -d "$SOURCE_ABS_PATH" ]; then  
  echo "Error: Source directory not found at $SOURCE_ABS_PATH"  
  exit 1  
fi  
  
mkdir -p "$OUTPUT_ABS_PATH"  
cd "$SOURCE_ABS_PATH"  
  
# --- Step 0a: Apply patched mmap_file.cpp into the fetched source ---  
if [ ! -f "$REPO_ROOT/mmap_file.cpp" ]; then  
  echo "ERROR: patched mmap_file.cpp not found at repo root ($REPO_ROOT)."  
  exit 1  
fi  
if [ ! -f "src/mmap_file.cpp" ]; then  
  echo "ERROR: src/mmap_file.cpp not found in fetched source - layout changed."  
  echo "Listing src/ for reference:"  
  ls -la src/ | head -n 40  
  exit 1  
fi  
echo "Applying patched mmap_file.cpp into src/..."  
cp "$REPO_ROOT/mmap_file.cpp" "src/mmap_file.cpp"  
  
# --- Step 0b: Apply patched cata_allocator.cpp into the fetched source ---  
# The experimental engine defaults to the bundled snmalloc allocator, which has  
# no WebAssembly (wasm32) AAL backend. Our patched copy adds  
# "&& !defined(__EMSCRIPTEN__)" to the CATA_USE_SNMALLOC guard so snmalloc is  
# skipped on the web build.  
if [ ! -f "$REPO_ROOT/cata_allocator.cpp" ]; then  
  echo "ERROR: patched cata_allocator.cpp not found at repo root ($REPO_ROOT)."  
  exit 1  
fi  
if [ ! -f "src/cata_allocator.cpp" ]; then  
  echo "ERROR: src/cata_allocator.cpp not found in fetched source - layout changed."  
  exit 1  
fi  
echo "Applying patched cata_allocator.cpp into src/..."  
cp "$REPO_ROOT/cata_allocator.cpp" "src/cata_allocator.cpp"  
  
# --- Step 0c: Inject <emscripten.h> into game_io.cpp for EM_ASM ---  
# The experimental game_io.cpp uses EM_ASM( window.game_unsaved = ... ) without  
# including <emscripten.h>, so the macro isn't defined. Add the include once.  
if [ -f "src/game_io.cpp" ] && ! grep -q "#include <emscripten.h>" src/game_io.cpp; then  
  echo "Injecting <emscripten.h> include into game_io.cpp..."  
  awk '  
    { print }  
    /^#include/ && !done {  
      print "#include <emscripten.h>"  
      done=1  
    }  
  ' src/game_io.cpp > src/game_io.cpp.tmp && mv src/game_io.cpp.tmp src/game_io.cpp  
fi  
  
# --- Step 0d: Inject SDL2 get_shared_variant_pass() fallback into pixel_minimap.cpp ---  
# get_shared_variant_pass() is declared only under the SDL3 (SDL_MAJOR_VERSION >= 3)  
# path. Because we force SDL2 (SDL3=0), the call sites in pixel_minimap.cpp would  
# reference an undeclared identifier. Provide a null-returning SDL2 fallback.  
if [ -f "src/pixel_minimap.cpp" ] && ! grep -q "SDL2 variant_pass fallback" src/pixel_minimap.cpp; then  
  echo "Injecting SDL2 get_shared_variant_pass fallback into pixel_minimap.cpp..."  
  awk '  
    { print }  
    /#include "vpart_position.h"/ && !done {  
      print ""  
      print "// SDL2 variant_pass fallback (Emscripten build)."  
      print "#if SDL_MAJOR_VERSION < 3"  
      print "static cata_shader::variant_pass *get_shared_variant_pass()"  
      print "{"  
      print "    return nullptr;"  
      print "}"  
      print "#endif"  
      done=1  
    }  
  ' src/pixel_minimap.cpp > src/pixel_minimap.cpp.tmp && mv src/pixel_minimap.cpp.tmp src/pixel_minimap.cpp  
fi  
  
# --- Step 0e: Compose the Ultica graphical tileset into gfx/ ---  
# The experimental source tarball ships only the base gfx/ content; the full  
# graphical tilesets live in CleverRaven/CDDA-Tilesets. Fetch that repo as a  
# tarball (no git auth needed) and compose Ultica into gfx/ so prepare-web.sh's  
# blanket "cp -R gfx" picks it up.  
# --- Fetch + compose UltimateCataclysm tileset (I-am-Erk/CDDA-Tilesets, master) ---  
echo "Installing tileset compose deps (libvips + pyvips)..."  
sudo apt-get update  
sudo apt-get install -y libvips42t64 || sudo apt-get install -y libvips42  
pip install pyvips  
  
echo "Downloading CDDA-Tilesets tarball (no git auth needed)..."  
wget -O /tmp/CDDA-Tilesets.tar.gz "https://github.com/I-am-Erk/CDDA-Tilesets/archive/refs/heads/master.tar.gz"  
  
mkdir -p /tmp/CDDA-Tilesets  
tar -xzf /tmp/CDDA-Tilesets.tar.gz -C /tmp/CDDA-Tilesets --strip-components=1  
  
echo "Composing UltimateCataclysm tileset..."  
python3 cdda-source/tools/gfx_tools/compose.py \  
  /tmp/CDDA-Tilesets/gfx/UltimateCataclysm \  
  cdda-source/gfx/UltimateCataclysm
  
# --- Step 1: Compile with Emscripten ---  
if [ ! -f "build-scripts/build-emscripten.sh" ]; then  
  echo "ERROR: build-scripts/build-emscripten.sh not found in this source tree."  
  echo "The build layout has changed again - listing build-scripts/ for reference:"  
  ls -la build-scripts/  
  exit 1  
fi  
  
# Experimental build toolchain flags:  
#  - SDL3=0 : Emscripten has no SDL3 >= 3.4.0 port; force the SDL2 path.  
#  - CLANG=1: emcc is clang under the hood; use clang-style warning flags.  
export SDL3=0  
export CLANG=1  
  
# Force CC=emcc so C files (zstd, cata_allocator_c) build as wasm objects  
# instead of native ELF (otherwise wasm-ld errors with "unknown file type").  
echo "Forcing CC=emcc so C files build as wasm..."  
sed -i 's/NATIVE=emscripten/CC=emcc NATIVE=emscripten/' build-scripts/build-emscripten.sh  
  
echo "Compiling cataclysm-tiles.js via build-scripts/build-emscripten.sh..."  
bash build-scripts/build-emscripten.sh  
  
# --- Step 2: Package data + assemble the real web bundle ---  
if [ ! -f "build-scripts/prepare-web.sh" ]; then  
  echo "ERROR: build-scripts/prepare-web.sh not found in this source tree."  
  exit 1  
fi  
  
echo "Packaging data and assembling web bundle via build-scripts/prepare-web.sh..."  
bash build-scripts/prepare-web.sh  
  
# --- Step 3: Copy the official build/ output straight to OUTPUT_DIR ---  
if [ ! -d "build" ]; then  
  echo "ERROR: prepare-web.sh did not produce a build/ directory as expected."  
  exit 1  
fi  
  
echo "Copying official web bundle to output..."  
cp -r build/. "$OUTPUT_ABS_PATH/"  
  
# --- Sanity check ---  
for f in cataclysm-tiles.js cataclysm-tiles.wasm cataclysm-tiles.data cataclysm-tiles.data.js index.html; do  
  if [ ! -f "$OUTPUT_ABS_PATH/$f" ]; then  
    echo "WARNING: expected file missing from output: $f"  
  fi  
done  
  
# --- Post-processing on the official generated index.html ---  
echo "Post-processing index.html..."  
if [ -f "$OUTPUT_ABS_PATH/index.html" ]; then  
  
  # 1) Cross-origin isolation for SharedArrayBuffer/pthreads (world gen).  
  if [ ! -f "$REPO_ROOT/coi-serviceworker.min.js" ]; then  
    echo "ERROR: coi-serviceworker.min.js not found at repo root ($REPO_ROOT)."  
    exit 1  
  fi  
  cp "$REPO_ROOT/coi-serviceworker.min.js" "$OUTPUT_ABS_PATH/"  
  sed -i 's#<head>#<head><script src="coi-serviceworker.min.js"></script>#' "$OUTPUT_ABS_PATH/index.html"  
  
  # 2) Visible error console (no DevTools).  
  if [ ! -f "$REPO_ROOT/error-overlay.js" ]; then  
    echo "ERROR: error-overlay.js not found at repo root ($REPO_ROOT)."  
    exit 1  
  fi  
  cp "$REPO_ROOT/error-overlay.js" "$OUTPUT_ABS_PATH/"  
  sed -i 's#<head>#<head><script src="error-overlay.js"></script>#' "$OUTPUT_ABS_PATH/index.html"  
  
  echo "index.html post-processed (coi + error overlay)"  
else  
  echo "Warning: index.html not found in output"  
fi  
  
echo "Build completed successfully!"  
echo "Web output prepared in: $OUTPUT_ABS_PATH"
