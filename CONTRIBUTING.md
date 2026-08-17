# Contributing

Thank you for helping improve DShMenu. This is an independent community
project for macOS users of DeepSeek Harness.

## Before opening a change

- Use an issue or discussion for behavior changes that affect installation,
  LaunchAgent state, data locations, or compatibility.
- Never test destructive lifecycle changes against another person's live
  `~/.dsh` directory.
- Keep user data, API keys, sessions, storages, logs, and generated app bundles
  out of commits.

## Development

Requirements:

- macOS 12 or later
- Xcode Command Line Tools with `swiftc`
- Bash, `plutil`, `launchctl`, `codesign`, and `curl` from macOS
- `ripgrep` for the repository checks

Run the isolated checks:

```bash
./tests/check.sh
```

Run the throwaway LaunchAgent matrix only on a disposable interactive macOS
login session:

```bash
RUN_LAUNCHCTL_MATRIX=1 ./tests/check.sh
```

The production matrix in `tests/production-state-matrix.md` changes the real
Web service state and is never part of CI.

## Pull requests

- Explain the user-visible behavior and failure mode being changed.
- Add or update an isolated regression check.
- Keep launchd identifiers and existing installation paths compatible unless
  the change includes an explicit migration and rollback path.
- Run `./tests/check.sh` and include the tested macOS, Node.js, and dsh
  versions.
