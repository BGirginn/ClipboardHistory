# Security policy

ClipboardHistory handles sensitive local data. Please do not disclose a suspected vulnerability in a public issue. Use GitHub's private vulnerability-reporting form for this repository. If that form is unavailable, contact the repository owner through the private contact method on the GitHub profile and include `ClipboardHistory security` in the subject.

Include the affected commit or version, macOS version and architecture, reproduction steps, expected impact, and whether the report involves clipboard data, archive parsing, Keychain access, code signing, or filesystem traversal. Do not attach real secrets or a production clipboard database; use synthetic fixtures.

Only versions listed as supported in the latest release receive fixes. There is currently no published `v1.0.0-beta.1`; the working tree is pre-release and must not be treated as a supported binary.

The project will not ask reporters to weaken Gatekeeper, remove quarantine attributes, publish private keys, or upload a real clipboard history. See [the threat model](docs/PRIVACY_AND_THREAT_MODEL.md) for security boundaries and non-goals.
