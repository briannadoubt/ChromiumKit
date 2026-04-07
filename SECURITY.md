# Security Policy

## Supported Versions

ChromiumKit is still pre-1.0, so security fixes are only guaranteed on:

- the latest `main` branch
- the latest tagged ChromiumKit release
- the latest pinned stable CEF update once it has been merged

Older branches, older experimental tags, and superseded CEF pins should be
treated as unsupported unless explicitly noted otherwise in a release.

## Reporting A Vulnerability

Please do not open public GitHub issues for security problems.

Preferred path:

1. Use GitHub's private vulnerability reporting for this repository by clicking
   `Security` -> `Report a vulnerability` once that option is available on the
   public repo.

If private vulnerability reporting is temporarily unavailable:

1. Do not include exploit details in a public issue.
2. Contact the maintainer privately first and request a non-public disclosure
   channel.
3. Wait for acknowledgement before sharing proof-of-concept details more
   broadly.

Please include:

- affected ChromiumKit version or commit
- affected macOS / Xcode version
- whether the issue is in ChromiumKit glue code, host packaging, or upstream
  CEF / Chromium behavior
- clear reproduction steps
- any crash logs, sample projects, or screenshots that help confirm impact

## Response Targets

Best-effort targets for initial maintainer response:

- acknowledgement within 5 business days
- status update or triage within 10 business days

These are targets, not guarantees. ChromiumKit is a small independent open
source project.

## Scope Notes

ChromiumKit wraps and redistributes CEF, which in turn ships Chromium
components. Some reports will turn out to be upstream CEF or Chromium issues
rather than ChromiumKit-specific defects. If that happens, ChromiumKit will
still try to:

- confirm whether the issue is reproducible in ChromiumKit
- document the affected versions and mitigation options
- track the relevant upstream fix where possible
