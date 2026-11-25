# setup-corpus

Install [Corpus](https://runcorpus.com), add `corpus` to PATH, and start the daemon
for subsequent steps in a GitHub Actions job.

```yaml
- uses: runcorpus/setup-corpus@main
- run: corpus --version
```

The default is the latest stable release. Set `corpus-version` to pin a release:

```yaml
- uses: runcorpus/setup-corpus@main
  with:
    corpus-version: '0.5.3'
```

Supports Linux x64 and macOS x64/Arm64 runners. The action downloads the matching
archive and its SHA-256 checksum directly from
[GitHub Releases](https://github.com/runcorpus/corpus/releases), verifies the
checksum and binary version, and installs the CLI in `$HOME/.corpus/bin`.
