#!/bin/bash

set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path-to-extracted-citrix-folder>"
    exit 1
fi

TARGET_DIR=$(realpath "$1")

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR does not exist."
    exit 1
fi

if [ ! -d "$TARGET_DIR/linuxx64/linuxx64.cor" ]; then
    echo "Error: Directory $TARGET_DIR does not look like a valid Citrix Workspace extracted folder."
    echo "Could not find linuxx64/linuxx64.cor inside it."
    exit 1
fi

# Download appimagetool if not present
APPIMAGETOOL_BIN="./appimagetool-x86_64.AppImage"
if ! command -v appimagetool &> /dev/null; then
    if [ ! -f "$APPIMAGETOOL_BIN" ]; then
        echo "appimagetool not found. Downloading..."
        curl -L -o "$APPIMAGETOOL_BIN" "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
        chmod +x "$APPIMAGETOOL_BIN"
    fi
    APPIMAGETOOL="$APPIMAGETOOL_BIN --appimage-extract-and-run"
else
    APPIMAGETOOL="appimagetool"
fi

# Create AppDir structure
APPDIR="CitrixWorkspace.AppDir"
echo "Creating AppDir structure in $APPDIR..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/opt/Citrix/ICAClient"
mkdir -p "$APPDIR/usr/lib"

# Compile WebKit hook to redirect hardcoded paths
echo "Compiling WebKit hook..."
cat << 'EOF' > "$APPDIR/webkit_hook.c"
#define _GNU_SOURCE
#include <dlfcn.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <spawn.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

static const char* redirect(const char* pathname, char* buf, size_t buf_len) {
    if (pathname && strncmp(pathname, "/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0/", 41) == 0) {
        const char *icaroot = getenv("ICAROOT");
        if (icaroot) {
            snprintf(buf, buf_len, "%s/webkit%s", icaroot, pathname);
            return buf;
        }
    }
    return pathname;
}

int execve(const char *pathname, char *const argv[], char *const envp[]) {
    static int (*orig)(const char *, char *const[], char *const[]) = NULL;
    if (!orig) orig = dlsym(RTLD_NEXT, "execve");
    char buf[1024];
    return orig(redirect(pathname, buf, sizeof(buf)), argv, envp);
}

int posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *file_actions, const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    static int (*orig)(pid_t *, const char *, const posix_spawn_file_actions_t *, const posix_spawnattr_t *, char *const [], char *const []) = NULL;
    if (!orig) orig = dlsym(RTLD_NEXT, "posix_spawn");
    char buf[1024];
    return orig(pid, redirect(path, buf, sizeof(buf)), file_actions, attrp, argv, envp);
}

int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *file_actions, const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    static int (*orig)(pid_t *, const char *, const posix_spawn_file_actions_t *, const posix_spawnattr_t *, char *const [], char *const []) = NULL;
    if (!orig) orig = dlsym(RTLD_NEXT, "posix_spawnp");
    char buf[1024];
    return orig(pid, redirect(file, buf, sizeof(buf)), file_actions, attrp, argv, envp);
}

int open(const char *pathname, int flags, ...) {
    static int (*orig)(const char *, int, ...) = NULL;
    if (!orig) orig = dlsym(RTLD_NEXT, "open");
    char buf[1024];
    const char *new_path = redirect(pathname, buf, sizeof(buf));
    if (flags & 0100) { // O_CREAT
        va_list args; va_start(args, flags); mode_t mode = va_arg(args, mode_t); va_end(args);
        return orig(new_path, flags, mode);
    }
    return orig(new_path, flags);
}

void* dlopen(const char* filename, int flags) {
    static void* (*orig)(const char*, int) = NULL;
    if (!orig) orig = dlsym(RTLD_NEXT, "dlopen");
    char buf[1024];
    return orig(redirect(filename, buf, sizeof(buf)), flags);
}
EOF
gcc -shared -fPIC -o "$APPDIR/webkit_hook.so" "$APPDIR/webkit_hook.c" -ldl
rm "$APPDIR/webkit_hook.c"

# Copy Citrix files
echo "Copying Citrix files..."
cp -r "$TARGET_DIR/linuxx64/linuxx64.cor/"* "$APPDIR/opt/Citrix/ICAClient/"

# Try to find a suitable icon
ICON_PATH=""
if [ -f "$TARGET_DIR/linuxx64/linuxx64.cor/icons/workspace.png" ]; then
    ICON_PATH="$TARGET_DIR/linuxx64/linuxx64.cor/icons/workspace.png"
elif [ -f "$TARGET_DIR/linuxx64/linuxx64.cor/icons/receiver.png" ]; then
    ICON_PATH="$TARGET_DIR/linuxx64/linuxx64.cor/icons/receiver.png"
fi

if [ -n "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$APPDIR/citrix-workspace.png"
else
    echo "Warning: Could not find an icon. Using a generic name."
    touch "$APPDIR/citrix-workspace.png"
fi

# Download libjpeg8 for distros like Fedora that don't have it, since Citrix's WebKit requires it
echo "Downloading libjpeg8 compatibility library..."
curl -s -L -o libjpeg8.deb "http://archive.ubuntu.com/ubuntu/pool/main/libj/libjpeg-turbo/libjpeg-turbo8_2.0.3-0ubuntu1_amd64.deb"
ar x libjpeg8.deb 2>/dev/null || true
tar -xf data.tar.xz 2>/dev/null || true
if [ -d "usr/lib/x86_64-linux-gnu" ]; then
    cp usr/lib/x86_64-linux-gnu/libjpeg.so.8* "$APPDIR/usr/lib/" 2>/dev/null || true
fi
rm -rf libjpeg8.deb control.tar.xz data.tar.xz debian-binary usr etc

# Initialize Citrix configuration files so it doesn't crash on startup
echo "Initializing Citrix config files..."
mkdir -p "$APPDIR/opt/Citrix/ICAClient/config"
# Copy all ini files from the extraction's config directory if it exists
if [ -d "$TARGET_DIR/linuxx64/linuxx64.cor/config" ]; then
    cp "$TARGET_DIR/linuxx64/linuxx64.cor/config/"*.ini "$APPDIR/opt/Citrix/ICAClient/config/" 2>/dev/null || true
fi
# Also copy from nls directories which often contain templates
cp "$APPDIR/opt/Citrix/ICAClient/nls/en/"*.ini "$APPDIR/opt/Citrix/ICAClient/config/" 2>/dev/null || true
cp "$APPDIR/opt/Citrix/ICAClient/nls/en/appsrv.template" "$APPDIR/opt/Citrix/ICAClient/config/appsrv.ini" 2>/dev/null || true
cp "$APPDIR/opt/Citrix/ICAClient/nls/en/wfclient.template" "$APPDIR/opt/Citrix/ICAClient/config/wfclient.ini" 2>/dev/null || true

# Ensure eula.txt is in ICAROOT
if [ -f "$TARGET_DIR/linuxx64/linuxx64.cor/eula.txt" ]; then
    cp "$TARGET_DIR/linuxx64/linuxx64.cor/eula.txt" "$APPDIR/opt/Citrix/ICAClient/eula.txt"
elif [ -f "$APPDIR/opt/Citrix/ICAClient/nls/en.UTF-8/eula.txt" ]; then
    cp "$APPDIR/opt/Citrix/ICAClient/nls/en.UTF-8/eula.txt" "$APPDIR/opt/Citrix/ICAClient/eula.txt"
elif [ -f "$APPDIR/opt/Citrix/ICAClient/nls/en/eula.txt" ]; then
    cp "$APPDIR/opt/Citrix/ICAClient/nls/en/eula.txt" "$APPDIR/opt/Citrix/ICAClient/eula.txt"
fi

# Final configuration adjustments
echo "BrowserAuth=True" >> "$APPDIR/opt/Citrix/ICAClient/config/All_Regions.ini"

# Extract bundled WebKit and other potential dependencies
echo "Extracting bundled WebKit..."
mkdir -p "$APPDIR/opt/Citrix/ICAClient/webkit"
tar -xf "$TARGET_DIR/linuxx64/linuxx64.cor/Webkit2gtk4.0/webkit2gtk-4.0.tar.gz" -C "$APPDIR/opt/Citrix/ICAClient/webkit" --strip-components=1 2>/dev/null || true

# Gather dependencies
echo "Gathering system dependencies..."
curl -L -s -o excludelist https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/master/excludelist

# Remove blank lines and comments from excludelist to make grep faster
grep -v '^#' excludelist | grep -v '^$' > excludelist.clean

# Explicitly add core libraries to excludelist to prevent bundling them
# Bundling these often breaks libsecret, GStreamer, or other host integrations
cat >> excludelist.clean <<EOF
libglib-2.0.so.0
libgobject-2.0.so.0
libgio-2.0.so.0
libgmodule-2.0.so.0
libgthread-2.0.so.0
libdbus-1.so.3
libselinux.so.1
libmount.so.1
libblkid.so.1
libstdc++.so.6
libgcc_s.so.1
libpcre2-8.so.0
libgstreamer-1.0.so.0
libgst*.so.1.0
libcrypto.so.3
libssl.so.3
libz.so.1
libsystemd.so.0
EOF

# List of explicit libraries to include for authentication and hardware acceleration
EXPLICIT_LIBS=(
    "libva.so.2"
    "libva-drm.so.2"
    "libva-x11.so.2"
    "libcanberra-gtk.so.0"
    "libcanberra-gtk3.so.0"
    "libsoup-2.4.so.1"
    "libidn.so.12"
    "libpcsclite.so.1"
    "libsm.so.6"
    "libice.so.6"
    "libxmu.so.6"
    "libxpm.so.4"
    "libspeexdsp.so.1"
    "libnotify.so.4"
    "libopenjp2.so.7"
)

# Function to find and copy a library and its dependencies
copy_lib_and_deps() {
    local lib_name=$1
    local lib_path=$(ldconfig -p | grep "$lib_name" | head -n 1 | awk '{print $4}')
    if [ -n "$lib_path" ] && [ -f "$lib_path" ]; then
        echo "Including explicit dependency: $lib_path"
        cp -L "$lib_path" "$APPDIR/usr/lib/" 2>/dev/null || true
        # Also scan its dependencies
        for dep in $(ldd "$lib_path" | grep "=> /" | awk '{print $3}'); do
            local dep_name=$(basename "$dep")
            if ! grep -q "^$dep_name$" excludelist.clean; then
                cp -L "$dep" "$APPDIR/usr/lib/" 2>/dev/null || true
            fi
        done
    fi
}

for elib in "${EXPLICIT_LIBS[@]}"; do
    copy_lib_and_deps "$elib"
done

ABS_APPDIR=$(realpath "$APPDIR")
# Set temporary LD_LIBRARY_PATH for scanning
export LD_LIBRARY_PATH="$ABS_APPDIR/opt/Citrix/ICAClient:$ABS_APPDIR/opt/Citrix/ICAClient/webkit/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

echo "Scanning for all required libraries..."
# Find all libraries needed by Citrix and its bundled WebKit
find "$APPDIR/opt/Citrix/ICAClient" -type f \( -executable -o -name "*.so*" -o -name "*.DLL" \) -exec ldd {} 2>/dev/null \; | grep "=> /" | awk '{print $3}' | sort -u > all_deps.txt

while read -r dep; do
    # Skip if it's already inside APPDIR
    if [[ "$dep" == "$ABS_APPDIR"* ]]; then
        continue
    fi

    dep_name=$(basename "$dep")
    
    # Check against excludelist patterns
    exclude=false
    while read -r pattern; do
        if [[ "$dep_name" == $pattern ]]; then
            exclude=true
            break
        fi
    done < excludelist.clean
    
    if [ "$exclude" = false ]; then
        if [ ! -f "$APPDIR/usr/lib/$dep_name" ]; then
            cp -L "$dep" "$APPDIR/usr/lib/" 2>/dev/null || true
        fi
    fi
done < all_deps.txt

# Final safeguard: Remove core libraries that should never be bundled
rm -f "$APPDIR/usr/lib/libglib-2.0.so.0"*
rm -f "$APPDIR/usr/lib/libgobject-2.0.so.0"*
rm -f "$APPDIR/usr/lib/libgio-2.0.so.0"*
rm -f "$APPDIR/usr/lib/libgmodule-2.0.so.0"*
rm -f "$APPDIR/usr/lib/libgthread-2.0.so.0"*
rm -f "$APPDIR/usr/lib/libdbus-1.so.3"*
rm -f "$APPDIR/usr/lib/libstdc++.so.6"*
rm -f "$APPDIR/usr/lib/libgcc_s.so.1"*
rm -f "$APPDIR/usr/lib/libpcre2-8.so.0"*
rm -f "$APPDIR/usr/lib/libgst"*.so*
rm -f "$APPDIR/usr/lib/libgstreamer"*.so*

rm -f "$APPDIR/usr/lib/libcrypto.so.3"*
rm -f "$APPDIR/usr/lib/libssl.so.3"*
rm -f "$APPDIR/usr/lib/libz.so.1"*
rm -f "$APPDIR/usr/lib/libsystemd.so.0"*

rm all_deps.txt excludelist excludelist.clean

# Create .desktop file
cat << 'EOF' > "$APPDIR/citrix-workspace.desktop"
[Desktop Entry]
Name=Citrix Workspace
Comment=Access your applications and desktops
Exec=AppRun %U
Icon=citrix-workspace
Terminal=false
Type=Application
Categories=Network;
MimeType=application/x-ica;
EOF

# Create AppRun script
cat << 'EOF' > "$APPDIR/AppRun"
#!/bin/bash

# Determine the absolute path of the AppDir
APPDIR="$(dirname "$(readlink -f "${0}")")"

# Set ICAROOT for Citrix Workspace
export ICAROOT="$APPDIR/opt/Citrix/ICAClient"

# Prepend our gathered libs and the bundled Webkit libs
export LD_LIBRARY_PATH="$APPDIR/usr/lib:$APPDIR/opt/Citrix/ICAClient/webkit/usr/lib/x86_64-linux-gnu:$ICAROOT:$ICAROOT/lib:$LD_LIBRARY_PATH"
export LD_PRELOAD="$APPDIR/webkit_hook.so:$LD_PRELOAD"

# Set WebKit execution path so it can find its helper processes like WebKitNetworkProcess
export WEBKIT_EXEC_PATH="$APPDIR/opt/Citrix/ICAClient/webkit/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0"
export WEBKIT_EXEC_DIR="$APPDIR/opt/Citrix/ICAClient/webkit/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0"
export WEBKIT_INJECTED_BUNDLE_PATH="$APPDIR/opt/Citrix/ICAClient/webkit/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0/injected-bundle"

# Set XDG_DATA_DIRS if necessary for WebKit
export XDG_DATA_DIRS="$APPDIR/usr/share:$XDG_DATA_DIRS"

# Force X11 backend as Citrix has issues with Wayland in some AppImage environments
export GDK_BACKEND=x11

# WebKit tweaks for better compatibility with SAML flows and hardware
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_FORCE_COMPOSITING_MODE=0
export WEBKIT_WEB_PROCESS_SANDBOX_DISABLE=1
export WEBKIT_USE_SINGLE_WEB_PROCESS=1

# Help GTK find modules on the host to avoid "Failed to load module" errors
export GTK_PATH="/usr/lib/x86_64-linux-gnu/gtk-3.0:/usr/lib/x86_64-linux-gnu/gtk-2.0:/usr/lib/gtk-3.0:/usr/lib/gtk-2.0"

# GStreamer tweaks to prevent registry issues and potential crashes
export GST_REGISTRY_REUSE=1
export GST_PLUGIN_SYSTEM_PATH_1_0="/usr/lib/x86_64-linux-gnu/gstreamer-1.0:/usr/lib/gstreamer-1.0"

# Disable accessibility bridge to prevent crashes
export NO_AT_BRIDGE=1

# Initialize user configuration directory if missing
if [ ! -d "$HOME/.ICAClient" ]; then
    echo "Initializing ~/.ICAClient..."
    mkdir -p "$HOME/.ICAClient"
fi

# Auto-accept EULA to prevent crash
touch "$HOME/.ICAClient/.eula_accepted"

# Copy default config files to ~/.ICAClient if they are missing
for cfg in All_Regions.ini All_REGIONS.ini appsrv.ini wfclient.ini module.ini; do
    if [ ! -f "$HOME/.ICAClient/$cfg" ] && [ -f "$ICAROOT/config/$cfg" ]; then
        cp "$ICAROOT/config/$cfg" "$HOME/.ICAClient/$cfg"
    fi
done

# Run wfica if passed an .ica file, else run selfservice
if [ "$#" -ge 1 ] && [[ "$1" == *.ica ]]; then
    exec "$ICAROOT/wfica" "$@"
else
    exec "$ICAROOT/selfservice" "$@"
fi
EOF

chmod +x "$APPDIR/AppRun"

# Build the AppImage
echo "Building AppImage..."
ARCH=x86_64 $APPIMAGETOOL "$APPDIR" CitrixWorkspace-x86_64.AppImage

echo "Done! The AppImage has been created: CitrixWorkspace-x86_64.AppImage"
echo "You can make it executable and run it:"
echo "  chmod +x CitrixWorkspace-x86_64.AppImage"
echo "  ./CitrixWorkspace-x86_64.AppImage"
