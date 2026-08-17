# Security Policy

## Supported versions

Security fixes are provided for the latest tagged release. DeepSeek Harness is
currently in developer preview, so compatibility fixes may require upgrading
both projects.

## Reporting a vulnerability

Do not publish API keys, session data, local paths, logs, or proof-of-concept
details that could harm users in a public issue. Use GitHub's private security
advisory feature for the repository when available, or contact the maintainer
privately through the address listed on their GitHub profile.

Include the affected DShMenu version, macOS version, dsh version, reproduction
steps, impact, and whether the issue requires local user interaction.

## Security boundary

DShMenu runs entirely in the current user's login session. It does not request
root privileges. It controls only its documented per-user LaunchAgents. The
Web UI listens on the address chosen by DeepSeek Harness; users should verify
their upstream dsh configuration before exposing it beyond loopback.
