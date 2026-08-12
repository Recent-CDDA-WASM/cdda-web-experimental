#!/bin/bash
set -e

RELEASE_TAG="${1:-latest}"
CDDA_REPO="CleverRaven/cataclysm-dda"
SOURCE_DIR="cdda-source"

echo "Fetching CDDA release: $RELEASE_TAG"

# Extract base tag from iteration tags (e.g., 0.I-build2 -> 0.I)
BASE_TAG=$(echo "$RELEASE_TAG" | sed 's/-build.*$//')
echo "Base CDDA release tag: $BASE_TAG"

# Clean up previous source
if [ -d "$SOURCE_DIR" ]; then
  echo "Removing previous source directory..."
  rm -rf "$SOURCE_DIR"
fi

# Create source directory
mkdir -p "$SOURCE_DIR"
cd "$SOURCE_DIR"

if [ "$BASE_TAG" = "latest" ]; then
  echo "Fetching latest stable Ito release..."
  # Get the latest stable Ito tag (simple format like 0.I)
  LATEST_TAG=$(git ls-remote --tags https://github.com/${CDDA_REPO}.git | grep -E 'refs/tags/0\.[A-Z]$' | sort -V | tail -n1 | sed 's/.*\///')
  echo "Latest stable Ito tag: $LATEST_TAG"
  BASE_TAG="$LATEST_TAG"
fi

# Download the release tarball using the base tag
echo "Downloading $BASE_TAG from GitHub..."
wget -O "cataclysm-dda-${BASE_TAG}.tar.gz" "https://github.com/${CDDA_REPO}/archive/refs/tags/${BASE_TAG}.tar.gz"

# Extract the tarball
echo "Extracting tarball..."
tar -xzf "cataclysm-dda-${BASE_TAG}.tar.gz"

# Find the extracted directory (handle different naming conventions)
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "Cataclysm-DDA-*" | head -n1)
if [ -z "$EXTRACTED_DIR" ]; then
  # Try alternative naming pattern
  EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "cataclysm-dda-*" | head -n1)
fi

if [ -z "$EXTRACTED_DIR" ]; then
  echo "Error: Could not find extracted directory"
  ls -la
  exit 1
fi

echo "Found extracted directory: $EXTRACTED_DIR"
mv "$EXTRACTED_DIR"/* .
rm -rf "$EXTRACTED_DIR"
rm "cataclysm-dda-${BASE_TAG}.tar.gz"

echo "Source fetched successfully to: $SOURCE_DIR"
echo "Base release tag: $BASE_TAG"
echo "Build iteration tag: $RELEASE_TAG"
