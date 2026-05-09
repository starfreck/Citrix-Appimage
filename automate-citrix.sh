#!/bin/bash
set -e

# Citrix Workspace AppImage Automation Script
# This script fetches the latest version from Citrix RSS and builds an AppImage.

RSS_URL="https://www.citrix.com/content/citrix/en_us/downloads/workspace-app.rss"
PACK_SCRIPT="./pack-citrix-appimage.sh"

echo "Checking for latest Citrix Workspace version..."
# Fetch RSS and find the latest Linux page link
PAGE_URL=$(curl -s "$RSS_URL" | grep -oP 'http://www.citrix.com/downloads/workspace-app/linux/workspace-app-for-linux-latest.html' | head -n 1)

if [ -z "$PAGE_URL" ]; then
    echo "Error: Could not find the latest Linux download page in RSS."
    exit 1
fi

echo "Found latest page: $PAGE_URL"
echo "Searching for direct download link..."

# Fetch the page and extract the rel attribute containing the tar.gz link
# We look for the one that has 'linuxx64' and '.tar.gz'
DOWNLOAD_PATH=$(curl -sL "$PAGE_URL" | grep -oP 'rel="\K//downloads\.citrix\.com/[^"]*linuxx64[^"]*\.tar\.gz[^"]*' | head -n 1)

if [ -z "$DOWNLOAD_PATH" ]; then
    echo "Error: Could not find the direct download link in the page source."
    exit 1
fi

DOWNLOAD_URL="https:$DOWNLOAD_PATH"
FILENAME=$(basename "${DOWNLOAD_URL%%\?*}")
VERSION_DIR="${FILENAME%.tar.gz}"

echo "Latest version found: $FILENAME"
echo "Download URL: $DOWNLOAD_URL"

# Download the tarball
if [ ! -f "$FILENAME" ]; then
    echo "Downloading $FILENAME..."
    curl -L -o "$FILENAME" "$DOWNLOAD_URL"
else
    echo "$FILENAME already exists, skipping download."
fi

# Extract the tarball
echo "Extracting $FILENAME..."
rm -rf "$VERSION_DIR"
mkdir -p "$VERSION_DIR"
tar -xf "$FILENAME" -C "$VERSION_DIR" --strip-components=1

# Run the packaging script
echo "Running packaging script..."
chmod +x "$PACK_SCRIPT"
"$PACK_SCRIPT" "$(realpath "$VERSION_DIR")"

echo "Automation complete!"
echo "Your latest AppImage is ready: CitrixWorkspace-x86_64.AppImage"
