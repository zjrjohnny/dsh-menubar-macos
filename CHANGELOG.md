# Changelog

All notable changes to this project will be documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- English documentation and bilingual menu-bar UI.
- Release hygiene, contribution guidance, security policy, and macOS CI.
- Source-only release workflow with ad-hoc local signing verification.

### Changed

- The installer now requires an existing `dsh` installation instead of
  silently running a global npm install.
- Project-managed runtime links live under `~/.dsh/dshmenu/bin` to avoid
  colliding with user-managed files under `~/.dsh/bin`.
- LaunchAgent plists are rendered with `plutil`, preserving paths containing
  XML-significant characters.
- The default Web workspace is the parent directory of the repository; it can
  be overridden with `DSH_WORKDIR`.
- Installation changes are backed up and restored on a failed lifecycle
  switch; the rollback path has an isolated fake-launchctl regression test.

## [0.1.0] - 2026-08-17

### Added

- Native AppKit menu-bar controller for the DeepSeek Harness Web UI.
- Per-user LaunchAgents for the Web service, menu bar, and daily log rotation.
- Login-start preference control, identity-aware health checks, single-instance
  locking, configurable port, internal log viewer, and installer state
  preservation.
