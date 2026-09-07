# Changelog

All notable changes to this project will be documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

## [0.1.2] - 2026-09-07

- Add an on-demand DSH update check using only npm's official `latest` tag,
  semantic version comparison and an optional copy-upgrade-command action.
- Open validated loopback launch-token URLs for DSH browser authentication.
- Expand Chinese and English installation and upgrade tutorials.

## [0.1.1] - 2026-08-19

### Fixed

- Rebuild and validate every LaunchAgent `ProgramArguments` array instead of
  replacing numeric array paths. On macOS Tahoe, `plutil -replace` with a path
  such as `ProgramArguments.0` inserts an element and previously left template
  placeholders and duplicate arguments in installed plists.

## [0.1.0] - 2026-08-17

### Added

- Native AppKit menu-bar controller for the DeepSeek Harness Web UI.
- Per-user LaunchAgents for the Web service, menu bar, and daily log rotation.
- Login-start preference control, identity-aware health checks, single-instance
  locking, configurable port, internal log viewer, and installer state
  preservation.
- English documentation and bilingual menu-bar UI.
- Release hygiene, contribution guidance, security policy, and macOS CI.
- A checksummed source-installer ZIP with Finder-friendly install and uninstall
  wrappers and dedicated English/Chinese usage guides.

### Changed

- The installer requires an existing `dsh` installation instead of silently
  running a global npm install.
- Project-managed runtime links live under `~/.dsh/dshmenu/bin` to avoid
  colliding with user-managed files under `~/.dsh/bin`.
- LaunchAgent plists are rendered with `plutil`, preserving paths containing
  XML-significant characters.
- The default Web workspace is configurable with `DSH_WORKDIR`.
- Installation changes are backed up and restored on a failed lifecycle
  switch; the rollback path has an isolated fake-launchctl regression test.
