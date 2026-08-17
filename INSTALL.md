# DShMenu installation and usage guide

This guide covers the `macos-source-installer.zip` attached to GitHub Releases. The archive contains source code: DShMenu is compiled and ad-hoc signed locally on your Mac. It is not an unnotarized prebuilt `.pkg`.

## 1. Prerequisites

You need macOS 12 or later, Node.js, DeepSeek Harness, and the Xcode Command Line Tools:

```bash
xcode-select --install
npm install -g @deepseek-ai/dsh
node --version
dsh --version
```

The installer does not request administrator privileges and does not silently install or upgrade the global dsh package.

## 2. Download and verify

Download both matching files from the [latest release](https://github.com/zjrjohnny/dsh-menubar-macos/releases/latest):

- `DShMenu-vX.Y.Z-macos-source-installer.zip`
- `DShMenu-vX.Y.Z-macos-source-installer.sha256`

Verify them in Terminal before extracting the archive:

```bash
cd "$HOME/Downloads"
shasum -a 256 -c DShMenu-v*-macos-source-installer.sha256
```

Continue only after the command reports `OK`. Redownload the files from the Release page if verification fails.

## 3. Install

Extract the ZIP, enter the extracted directory, and run:

```bash
./Install.command
```

The wrapper asks for the Web workspace directory and defaults to `~/Documents`. Choose only a directory that you are comfortable allowing the dsh Web UI to browse.

To choose it non-interactively:

```bash
DSH_WORKDIR="$HOME/Documents/deepseek" ./Install.command
```

If Finder blocks a double-clicked `.command`, use the Terminal command above. Do not disable macOS security controls.

The installer builds and verifies the app locally, renders three per-user LaunchAgents, and installs:

- `~/Applications/DShMenu.app`
- `~/Library/LaunchAgents/com.zjr.dsh-*.plist`
- `~/.dsh/DShMenu.config.plist`
- `~/.dsh/logs/`

## 4. Use DShMenu

- Left-click the menu-bar icon to open the Web UI.
- Right-click it to start, stop, restart, view logs, toggle login start, or quit.
- Green means healthy; yellow means starting/unhealthy; orange or red indicates an outside service or port conflict; gray means stopped.
- “Quit Menu Bar” leaves Web running. Use “Stop Service and Quit” to stop both.

On macOS Tahoe, move the pointer a few pixels below the top edge if a right-click is not delivered.

## 5. Port, upgrades, and removal

The default port is 3080. Change it and rerun the installer:

```bash
/usr/libexec/PlistBuddy -c 'Set :Port 3090' ~/.dsh/DShMenu.config.plist
./Install.command
```

For an upgrade, verify and extract the new release, then run its `Install.command`. Existing port, login-start preference, and running/stopped state are preserved. Rerun it after upgrading Node.js or dsh as well.

Run a non-mutating preflight with:

```bash
DSHMENU_NO_PAUSE=1 ./Install.command --check
```

Remove DShMenu with `./Uninstall.command`. The app, LaunchAgents, managed runtime links, and service logs are removed; dsh sessions, storages, port configuration, and the global dsh package are preserved.

## Data-safety notes

- The Web service should listen only on `127.0.0.1`; do not forward it to the public Internet.
- Avoid concurrent Web/CLI writers using the same `DSH_HOME`.
- Redact logs before posting them publicly. Use the private process in [SECURITY.md](SECURITY.md) for security reports.
