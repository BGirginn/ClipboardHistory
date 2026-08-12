# Contributing

ClipboardHistory is a local-only macOS application. Contributions must not add telemetry, analytics, remote APIs, cloud synchronization, AI services, account systems, or background network access.

Before opening a pull request:

1. Build with Swift 6 strict concurrency and no warnings.
2. Add a failing regression test before a bug fix and cover success, cancellation, and error paths.
3. Keep tests isolated from the user's Application Support directory, UserDefaults suite, general pasteboard, and production Keychain service.
4. Run `scripts/verify-static-quality.sh` and the unit/UI suites.
5. Produce one combined `.xcresult` and run `scripts/verify-coverage.sh`; aggregate production coverage must be at least 95%, and no production Swift source with executable regions may be completely untested. Files below 80% are reported for follow-up.
6. Update English and Turkish strings together and document user-visible changes.

Generated data and DerivedData belong under `/private/tmp`. Never commit certificates, private keys, provisioning profiles, real archives, real databases, or absolute user paths. Commits that alter migrations, archive parsing, deletion, encryption, or pasteboard identity require negative tests and security review.

See [TESTING.md](../docs/TESTING.md) for the complete release matrix. A passing local run is necessary but does not replace macOS 14, 15, and 26 arm64 evidence.
