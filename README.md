# Citrix Workspace AppImage Packager

This script automates the creation of a portable, standalone **AppImage** for the Citrix Workspace App (ICA Client) on Linux. It is specifically designed to work on modern distributions like **Fedora**, **Ubuntu**, and **Debian** by resolving complex dependency chains and hardcoded path issues.

## Key Features

- **Standalone Portability:** Bundles all necessary libraries, including legacy dependencies like `libjpeg8`.
- **WebKit Fix:** Includes a custom `LD_PRELOAD` hook to redirect hardcoded absolute paths (e.g., `/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0/`) used by Citrix to the internal AppImage directory.
- **Keyring Support:** Bundles `libsecret`, `p11-kit`, and `gnome-keyring` modules to ensure login credentials can be saved securely.
- **Automatic Configuration:** Seeds required `.ini` configuration files (`appsrv.ini`, `wfclient.ini`) from templates during the build process.
- **Wayland/X11 Compatibility:** Configured to use the stable X11 backend for maximum compatibility with various display servers.

## Prerequisites

Before running the script, ensure you have the following installed on your system:
- `gcc` (to compile the WebKit redirection hook)
- `curl` (to download the AppImage tool and compatibility libs)
- `binutils` (for `ar` and `ldd`)
- The Citrix Workspace Linux installer (tar.gz or extracted directory)

## Automation (Fetch & Build)

You can automate the entire process—including fetching the latest version from the Citrix RSS feed, downloading the tarball, and building the AppImage—using the provided automation script:

```bash
chmod +x automate-citrix.sh
./automate-citrix.sh
```

This script will:
1. Parse the Citrix RSS feed for the latest Linux version.
2. Discover the direct download URL for the `x86_64` tarball.
3. Download and extract the installer.
4. Invoke `pack-citrix-appimage.sh` to create the final AppImage.

## GitHub Actions (Continuous Delivery)

A GitHub Actions workflow is provided in `.github/workflows/build.yml`. This workflow:
1. Runs daily to check the Citrix RSS feed for new versions.
2. Compares the latest version with your existing GitHub Releases.
3. If a new version is found, it automatically builds the AppImage on an Ubuntu runner.
4. Publishes a new GitHub Release with the `CitrixWorkspace-x86_64.AppImage` attached.

To use this:
1. Push this entire directory to a new GitHub repository.
2. Go to **Settings > Actions > General** and ensure "Read and write permissions" are enabled for the `GITHUB_TOKEN`.
3. The workflow will now track and publish new versions automatically!

## Manual Usage (Pack Only)

If you already have the Citrix installer directory extracted, you can run the packaging script directly:
   ```bash
   chmod +x pack-citrix-appimage.sh
   ./pack-citrix-appimage.sh /path/to/citrix-installer-dir
   ```

3. **Output:**
   The script will generate a file named `CitrixWorkspace-x86_64.AppImage` in the current directory.

4. **Launch the AppImage:**
   ```bash
   chmod +x CitrixWorkspace-x86_64.AppImage
   ./CitrixWorkspace-x86_64.AppImage
   ```

## Troubleshooting

- **Authentication Page Issues:** If the login screen doesn't appear, the script handles the redirection of WebKit processes automatically. Ensure `gcc` was available during the build process to compile the `webkit_hook.so`.
- **Display Errors:** The AppImage is set to use `GDK_BACKEND=x11`. If you are on Wayland and experience rendering issues, ensure your compositor supports XWayland.
- **Missing Secrets:** If the app forgets your email address, ensure the `libsecret-1.so.0` and `gnome-keyring-pkcs11.so` libraries were successfully bundled (the script logs this during execution).

## How the WebKit Hook Works
Citrix binaries have hardcoded absolute paths to `/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0/WebKitNetworkProcess`. Since an AppImage is mounted in a random location in `/tmp`, these paths fail. The included hook intercepts `posix_spawn` and `execve` calls and transparently redirects them to the `AppDir`, allowing the authentication engine to function without system-wide modifications.
