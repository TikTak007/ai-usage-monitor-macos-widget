# Security policy

## Supported version

Only the latest commit on the default branch is supported. This is a small
community project and does not promise a particular response or maintenance
window.

## Reporting a vulnerability

Do not open a public issue containing credentials, tokens, account details,
private usage values, machine-specific paths, or raw provider responses.
Instead, use the repository owner's private security-reporting channel when
one is configured. If no private channel is available, open a minimal public
issue that contains no sensitive details and asks how to report privately.

## Security boundaries

- AI Usage Monitor must not read, copy, print, or persist Codex authentication files.
- The widget bridge must remain bound to IPv4 loopback (`127.0.0.1`).
- Only normalized usage fields may cross the widget bridge.
- The project must not redeem banked resets, alter account settings, bypass
  usage limits, or disable macOS security controls.
- Build and installation instructions must not require `sudo`.

## Local build trust

This repository distributes source, not a prebuilt binary. Review the source
and build scripts before running them. An Apple Development signature is
recommended for reliable WidgetKit discovery; do not work around a signing
failure by disabling Gatekeeper or other platform protections.
