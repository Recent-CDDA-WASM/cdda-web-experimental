#!/bin/bash  
set -e  
  
SOURCE_DIR="cdda-source"  
OUTPUT_DIR="web-output"  
  
echo "Starting CDDA WebAssembly build (experimental) using official build scripts..."  
  
# Capture the repo checkout root BEFORE we cd into the source tree, so we can  
# reliably find vendored files (coi-serviceworker.min.js, error-overlay.js,  
# mmap_file.cpp, cata_allocator.cpp) later.  
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
  
# ============================================================  
# Step 0a: Patched mmap_file.cpp (world-gen mmap crash fix)  
# ============================================================  
if [ ! -f "$REPO_ROOT/mmap_file.cpp" ]; then  
  echo "ERROR: patched mmap_file.cpp not found at repo root ($REPO_ROOT)."  
  exit 1  
fi  
if [ ! -f "src/mmap_file.cpp" ]; then  
  echo "ERROR: src/mmap_file.cpp not found in fetched source - layout changed."  
  ls -la src/ | head -n 40  
  exit 1  
fi  
echo "Applying patched mmap_file.cpp into src/..."  
cp "$REPO_ROOT/mmap_file.cpp" "src/mmap_file.cpp"  
  
# ============================================================  
# Step 0b: Patched cata_allocator.cpp (disable snmalloc on wasm)  
# ============================================================  
if [ ! -f "$REPO_ROOT/cata_allocator.cpp" ]; then  
  echo "ERROR: patched cata_allocator.cpp not found at repo root ($REPO_ROOT)."  
  exit 1  
fi  
echo "Applying patched cata_allocator.cpp into src/..."  
cp "$REPO_ROOT/cata_allocator.cpp" "src/cata_allocator.cpp"  

# ============================================================  
# Step 0c: Ensure emscripten.h is included in game_io.cpp  
#          (EM_ASM(window...) needs the header). Grep-guarded  
#          so it is a no-op if upstream/remote already added it.  
# ============================================================  
if [ -f "src/game_io.cpp" ] && ! grep -q "emscripten.h" src/game_io.cpp; then  
  echo "Injecting #include <emscripten.h> into game_io.cpp..."  
  sed -i '1i #include <emscripten.h>' src/game_io.cpp  
fi  
  
# ============================================================  
# Step 0d: SDL2 get_shared_variant_pass() fallback for  
#          pixel_minimap.cpp. The real one is SDL3-only; on the  
#          SDL2 path (SDL3=0) provide a null-returning stub.  
#          Grep-guarded so it only injects once.  
# ============================================================  
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
  
# ============================================================  
# Step 0e: Fetch + compose the UltimateCataclysm tileset  
#          (I-am-Erk/CDDA-Tilesets, branch master, folder  
#          gfx/UltimateCataclysm). Runs AFTER source is fetched  
#          and BEFORE prepare-web.sh so the composed tileset gets  
#          packed into cataclysm-tiles.data. All paths are  
#          source-relative (we are already inside cdda-source).  
# ============================================================  
echo "Installing tileset compose deps (libvips + pyvips) + shader compiler (glslang)..."  
sudo apt-get update  
sudo apt-get install -y libvips42t64 || sudo apt-get install -y libvips42  
sudo apt-get install -y glslang-tools  
pip install pyvips  
export GLSLANG="$(command -v glslangValidator || command -v glslang)"  
echo "Using GLSLANG=$GLSLANG"
  
echo "Downloading CDDA-Tilesets tarball (no git auth needed)..."  
wget -O /tmp/CDDA-Tilesets.tar.gz "https://github.com/I-am-Erk/CDDA-Tilesets/archive/refs/heads/master.tar.gz"  
mkdir -p /tmp/CDDA-Tilesets  
tar -xzf /tmp/CDDA-Tilesets.tar.gz -C /tmp/CDDA-Tilesets --strip-components=1  
  
echo "Composing UltimateCataclysm tileset..."  
# 1) Copy the whole tileset folder (name tag included) into gfx/  
cp -R /tmp/CDDA-Tilesets/gfx/UltimateCataclysm gfx/UltimateCataclysm  
  
# 2) Compose IN PLACE (one path) so tiles.png + tile_config.json land  
#    right next to the tileset.txt name tag that came with it  
python3 tools/gfx_tools/compose.py gfx/UltimateCataclysm || true
  
# ============================================================  
# Step 1: Compile with Emscripten (SDL2 path, clang warnings,  
#         and CC=emcc so C files build as wasm)  
# ============================================================  
if [ ! -f "build-scripts/build-emscripten.sh" ]; then  
  echo "ERROR: build-scripts/build-emscripten.sh not found in this source tree."  
  ls -la build-scripts/  
  exit 1  
fi  

export CLANG=1  
export EMCC_CFLAGS="-Wno-experimental"
  
echo "Forcing CC=emcc so C files (zstd, cata_allocator_c) build as wasm..."  
sed -i 's/NATIVE=emscripten/CC=emcc NATIVE=emscripten/' build-scripts/build-emscripten.sh  
  
echo "Patching hardcoded emsdk version in build-scripts/build-emscripten.sh (3.1.51 -> 6.0.6)..."  
sed -i 's/3\.1\.51/6.0.6/g' build-scripts/build-emscripten.sh  
  
echo "Here is the patched build-emscripten.sh for verification:"  
cat build-scripts/build-emscripten.sh  
  
echo "Compiling cataclysm-tiles.js via build-scripts/build-emscripten.sh..."  

# --- SDL3 port wiring for Emscripten (experimental) ---  
echo "Patching Makefile to bypass SDL3 version check for emscripten..."  
# Turn the fatal version check into a no-op for the NATIVE=emscripten path.  
sed -i 's/^\(\s*\)\$(error SDL3 >= 3.4.0 required.*)/\1$(info SDL3 version check skipped for emscripten)/' Makefile  
  
echo "Forcing SDL3 ports into the emscripten compile/link..."  
export EMCC_CFLAGS="--use-port=sdl3 --use-port=sdl3_ttf"  
export LDFLAGS="$LDFLAGS --use-port=sdl3 --use-port=sdl3_ttf /tmp/sdl3_image_prefix/lib/libSDL3_image.a -sDEFAULT_TO_CXX -O0 -g0 -sASYNCIFY_STACK_SIZE=1048576 -sSTACK_SIZE=5MB -sASSERTIONS=2"

sed -i 's/ifeq (\$(SDL3_DO_VERSION_CHECK),1)/ifeq ($(SDL3_DO_VERSION_CHECK),SKIP)/' Makefile

echo "Patching build-emscripten.sh to allow the experimental SDL3 port..."  
sed -i 's#^\(\s*\)make #\1EMCC_CFLAGS="--use-port=sdl3 --use-port=sdl3_ttf -Wno-experimental -Wno-error -g0 -I/tmp/sdl3_image_prefix/include -DUSE_SDL3" make PCH=0 #' build-scripts/build-emscripten.sh

# ---- Option A: build SDL3_image from source to a wasm static lib ----  
SDL_PREFIX="/tmp/sdl3_image_prefix"  
echo "Building SDL3_image (+ throwaway SDL3 for CMake config) from source..."  
mkdir -p /tmp/sdlsrc && pushd /tmp/sdlsrc  
  
# 1) SDL3 from source, installed ONLY so SDL_image's find_package(SDL3) works.  
#    Match the port version (3.4.2) so headers line up.  
git clone --depth 1 --branch release-3.4.2 https://github.com/libsdl-org/SDL  
  emcmake cmake -S SDL -B SDL/build -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
cmake --build SDL/build -j"$(nproc)"  
cmake --install SDL/build --prefix "$SDL_PREFIX"  
  
# 2) SDL3_image from source, STB backend (PNG/JPG via bundled stb_image,  
#    no libpng/zlib), everything else off -> a single libSDL3_image.a.  
git clone --depth 1 --branch release-3.2.4 https://github.com/libsdl-org/SDL_image  
emcmake cmake -S SDL_image -B SDL_image/build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_PREFIX_PATH="$SDL_PREFIX" -DSDL3_DIR="$SDL_PREFIX/lib/cmake/SDL3" -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH -DSDLIMAGE_SAMPLES=OFF -DSDLIMAGE_DEPS_SHARED=OFF -DSDLIMAGE_VENDORED=OFF -DSDLIMAGE_BACKEND_STB=ON -DSDLIMAGE_PNG=ON -DSDLIMAGE_JPG=ON -DSDLIMAGE_AVIF=OFF -DSDLIMAGE_WEBP=OFF -DSDLIMAGE_JXL=OFF -DSDLIMAGE_TIF=OFF -DSDLIMAGE_BMP=ON -DSDLIMAGE_GIF=OFF
cmake --build SDL_image/build -j"$(nproc)"
cmake --install SDL_image/build --prefix "$SDL_PREFIX"  
  
popd  
echo "SDL3_image built. Contents of $SDL_PREFIX/lib:"  
ls -la "$SDL_PREFIX/lib" || true  
# ---- end Option A build ----

echo "----- build-emscripten.sh after patch -----"  
cat build-scripts/build-emscripten.sh  
echo "-------------------------------------------"

grep -nE 'cataclysm[^:]*:' Makefile || true
grep -nE 'cataclysm[^:[:space:]]*(\.js)?[[:space:]]*:' Makefile || true

echo "Stripping baked-in -Os/-sLZ4 from emscripten release LDFLAGS so -O0 takes effect..."  
sed -i '/LDFLAGS += -Os/d' Makefile

bash build-scripts/build-emscripten.sh
  
# ============================================================  
# Step 2: Package data + assemble the real web bundle  
# ============================================================  
if [ ! -f "build-scripts/prepare-web.sh" ]; then  
  echo "ERROR: build-scripts/prepare-web.sh not found in this source tree."  
  exit 1  
fi  
  
echo "Packaging data and assembling web bundle via build-scripts/prepare-web.sh..."  
bash build-scripts/prepare-web.sh  
  
# ============================================================  
# Step 3: Copy the official build/ output straight to OUTPUT_DIR  
# ============================================================  
if [ ! -d "build" ]; then  
  echo "ERROR: prepare-web.sh did not produce a build/ directory as expected."  
  exit 1  
fi  
  
echo "Copying official web bundle to output..."  
cp -r build/. "$OUTPUT_ABS_PATH/"  

# ============================================================  
# Step 3b: Shrink the linked wasm with wasm-opt (Plan B)  
# ============================================================  
# Locate wasm-opt from the active emsdk/binaryen install  
WASM_OPT="$(command -v wasm-opt || true)"  
if [ -z "$WASM_OPT" ]; then  
  WASM_OPT="$(dirname "$(command -v emcc)")/../bin/wasm-opt"      # emsdk/upstream/bin/wasm-opt  
  [ -x "$WASM_OPT" ] || WASM_OPT="$HOME/emsdk/upstream/bin/wasm-opt"  
fi  
  
echo "Using wasm-opt at: $WASM_OPT"  
"$WASM_OPT" --version  
  
echo "wasm size BEFORE wasm-opt:"  
ls -lh "$OUTPUT_ABS_PATH/cataclysm-tiles.wasm"  
  
"$WASM_OPT" -Oz "$OUTPUT_ABS_PATH/cataclysm-tiles.wasm" -o "$OUTPUT_ABS_PATH/cataclysm-tiles.wasm.opt"  
mv "$OUTPUT_ABS_PATH/cataclysm-tiles.wasm.opt" "$OUTPUT_ABS_PATH/cataclysm-tiles.wasm"
  
echo "wasm size AFTER wasm-opt:"  
ls -lh "$OUTPUT_ABS_PATH/cataclysm-tiles.wasm"
  
# --- Sanity check ---  
for f in cataclysm-tiles.js cataclysm-tiles.wasm cataclysm-tiles.data cataclysm-tiles.data.js index.html; do  
  if [ ! -f "$OUTPUT_ABS_PATH/$f" ]; then  
    echo "WARNING: expected file missing from output: $f"  
  fi  
done  
  
# ============================================================  
# Post-processing on the official generated index.html  
# ============================================================  
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
