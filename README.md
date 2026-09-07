# DShMenu for macOS

[![CI](https://github.com/zjrjohnny/dsh-menubar-macos/actions/workflows/ci.yml/badge.svg)](https://github.com/zjrjohnny/dsh-menubar-macos/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

English | [简体中文](README.zh-CN.md) | [Installation guide](INSTALL.md)

DShMenu runs the [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
Web UI as a per-user macOS background service and provides a native AppKit
menu-bar controller. No terminal window needs to remain open.

> [!IMPORTANT]
> DShMenu is an independent community project. It is not affiliated with,
> endorsed by, or maintained by DeepSeek. DeepSeek Harness is currently a
> developer preview and may introduce breaking changes.

## Features

- **Check DSH Updates** compares the installed CLI with npm's official `latest`
  tag only. No automatic installation or selection of `alpha`/`next`.
- Opens the authenticated launch URL required by newer DSH releases.

- Starts the dsh Web UI at login through `launchd`.
- Left-click opens the Web UI; right-click opens service controls.
- Start, stop, restart, login-start toggle, log viewer, and quit actions.
- Identity-aware health check: a random HTTP service on the configured port is
  not mistaken for DeepSeek Harness.
- Preserves enabled/disabled and running/stopped state across reinstalls.
- Uses stable runtime links so nvm-managed Node.js upgrades do not leave a
  stale version path in a LaunchAgent.
- Prevents duplicate menu-bar instances with a process lock.
- Rotates Web logs over 10 MiB and retains five copies.
- Does not use Terminal automation, AppleScript, Accessibility, or root access.

## Architecture

See [the installation tutorial](INSTALL.md): install Node.js and Xcode Command
Line Tools, run `npm install -g @deepseek-ai/dsh@latest`, download and verify the
[release ZIP](https://github.com/zjrjohnny/dsh-menubar-macos/releases/latest),
extract it, then run `bash install.sh` from the extracted folder.

```text
DShMenu.app (LSUIElement, launchd-managed, single instance)
   │ left-click: open Web UI
   │ right-click: service controls
   ▼
com.zjr.dsh-web
   │ ~/.dsh/dshmenu/bin/node ~/.dsh/dshmenu/bin/dsh web --port <Port>
   ▼
DeepSeek Harness Web UI (default: http://127.0.0.1:3080)

com.zjr.dsh-logrotate
   └─ checks Web logs at load and every day at 03:15
```

The launchd labels retain the original `com.zjr.*` namespace for upgrade
compatibility with existing installations.

## Requirements

- macOS 12 or later
- Node.js supported by the installed dsh release
- DeepSeek Harness CLI available as `dsh`
- Xcode Command Line Tools (`swiftc` and `codesign`)

The initial release was verified on macOS 26.6.1, Apple Silicon, Node.js
24.18.0, and `@deepseek-ai/dsh` 0.1.0-rc.6. Because dsh is in developer
preview, other versions may require compatibility updates.

Install prerequisites first:

```bash
xcode-select --install
npm install -g @deepseek-ai/dsh
dsh --version
```

The DShMenu installer will not silently install or upgrade dsh.

## Quick install

Download the matching ZIP and `.sha256` files from the [latest release](https://github.com/zjrjohnny/dsh-menubar-macos/releases/latest), verify, extract, and run:

```bash
cd "$HOME/Downloads"
shasum -a 256 -c DShMenu-v*-macos-source-installer.sha256
cd DShMenu-v*-macos-source-installer
./Install.command
```

The Release ZIP is a source installer. It builds and ad-hoc signs DShMenu locally and contains no prebuilt application executable. See the [installation and usage guide](INSTALL.md) for workspace selection, upgrades, troubleshooting, and removal.

## Install from Git

Clone the repository, review the installer, and run it:

```bash
git clone https://github.com/zjrjohnny/dsh-menubar-macos.git
cd dsh-menubar-macos
./install.sh
```

By default, the parent directory of the repository becomes the initial Web
workspace root. Choose another existing directory with `DSH_WORKDIR`:

```bash
DSH_WORKDIR="$HOME/Documents" ./install.sh
```

The installer builds the small Swift app locally, applies an ad-hoc signature,
renders and validates the LaunchAgent files, and then switches the per-user
jobs. It never asks for administrator privileges. If a switch fails, it makes
a best-effort rollback to the previous App, plist files, and launchd state.

Build and validate everything without changing the installed app or jobs:

```bash
./install.sh --check
```

Installed files:

- App: `~/Applications/DShMenu.app`
- LaunchAgents: `~/Library/LaunchAgents/com.zjr.dsh-*.plist`
- Managed runtime links: `~/.dsh/dshmenu/bin/`
- Port configuration: `~/.dsh/DShMenu.config.plist`
- Web and controller logs: `~/.dsh/logs/`

If another process already owns the configured port, stop it before
installation. Do not run a manual `dsh web` process against the same
`DSH_HOME` while the service is active.

## Usage

| Action | Result |
|---|---|
| Left-click the status item | Open the configured Web UI |
| Right-click the status item | Open the control menu |
| View Logs | Open the built-in read-only log window |
| Toggle Start at Login | Change only the Web service preference |
| Quit Menu Bar | Leave the Web service running |
| Stop Service and Quit | Stop Web, then exit the controller |

Status colors:

- Green: launchd-managed dsh is healthy.
- Yellow: the job is running but dsh is not ready.
- Orange: a dsh instance exists outside the managed job.
- Red: another HTTP service occupies the configured port.
- Gray: stopped, unloaded, or not installed.

macOS Tahoe has an OS-level regression where a right-click at the very top
edge of the menu bar may not reach the application. Move the pointer down a
few pixels and click again. DShMenu uses the supported `NSMenu.popUp` API and
does not request global input-monitoring permission as a workaround.

## Configure the port

`~/.dsh/DShMenu.config.plist` contains a top-level integer `Port` in the range
1 through 65535. The default is 3080. Change it and reinstall so the menu bar
and LaunchAgent stay aligned:

```bash
/usr/libexec/PlistBuddy -c 'Set :Port 3090' ~/.dsh/DShMenu.config.plist
./install.sh
```

## Upgrade

After upgrading Node.js or dsh, rerun `./install.sh` to refresh the managed
links. Reinstallation preserves Web service state along two independent axes:

- enabled remains enabled; disabled remains disabled;
- running resumes running; stopped or unloaded remains stopped/unloaded.

Only a first installation defaults to enabled and running.

## Logs

- `~/.dsh/logs/dsh-web.out.log`
- `~/.dsh/logs/dsh-web.err.log`
- `~/.dsh/logs/DShMenu.log`

The daily rotation job uses copy-and-truncate so launchd can keep its open file
descriptor. A very small copy/truncate race can duplicate or omit bytes written
at that exact moment; this is not transactional archival.

## Verification and development

Run the isolated checks before opening a pull request:

```bash
./tests/check.sh
```

The optional throwaway LaunchAgent matrix changes only a dedicated test label:

```bash
RUN_LAUNCHCTL_MATRIX=1 ./tests/check.sh
```

The production matrix in `tests/production-state-matrix.md` changes the real
service state and must be reviewed before use.

## Shared `DSH_HOME` limitation

The Web service and CLI use the same `~/.dsh` by default. There is not yet
enough evidence that every upstream session/storage write is protected across
processes. Avoid concurrent writers using the same `DSH_HOME`; changing only
the port does not isolate data. See `tests/concurrency-plan.md` for the safe
future test design.

## Uninstall

```bash
./uninstall.sh
```

This removes DShMenu.app, its LaunchAgents, project-managed runtime links, and
service logs. It preserves the port configuration and dsh sessions/storages.
It does not uninstall the global dsh CLI.

## Distribution

Releases provide a checksummed source-installer archive. The app is compiled
and ad-hoc signed on the user's Mac; the archive does not contain a prebuilt
app executable. A prebuilt app or `.pkg` should not be offered until it is
signed with an Apple Developer ID and notarized.

## License

DShMenu is available under the [MIT License](LICENSE). See [Notices](NOTICE.md)
for upstream attribution and the independent-project statement.
