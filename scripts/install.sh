#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'setup-corpus: %s\n' "$*" >&2
  exit 1
}

download() {
  curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 300 --retry 3 "$@"
}

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) target=x86_64-unknown-linux-gnu ;;
  Darwin/x86_64) target=x86_64-apple-darwin ;;
  Darwin/arm64|Darwin/aarch64) target=aarch64-apple-darwin ;;
  *) fail 'Supported runners are Linux x64 and macOS x64/Arm64.' ;;
esac

repository=https://github.com/runcorpus/corpus
version=${CORPUS_VERSION:-latest}
if [[ "$version" == latest ]]; then
  release_url=$(download --output /dev/null --write-out '%{url_effective}' \
    "$repository/releases/latest")
  case "$release_url" in
    "$repository/releases/tag/v"*) version=${release_url##*/v} ;;
    *) fail "Could not resolve the latest stable release: $release_url" ;;
  esac
else
  version=${version#v}
fi
printf '%s\n' "$version" | grep -Eq \
  '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?(\+[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$' \
  || fail "Invalid corpus-version: $version"

if command -v sha256sum >/dev/null 2>&1; then
  checksum_tool=sha256sum
elif command -v shasum >/dev/null 2>&1; then
  checksum_tool=shasum
else
  fail 'SHA-256 verification requires sha256sum or shasum.'
fi

temporary=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/setup-corpus.XXXXXXXX")
staged=''
cleanup() {
  rm -rf "$temporary"
  if [[ -n "$staged" ]]; then rm -f "$staged"; fi
}
trap cleanup EXIT

archive=corpus-$version-$target.tar.gz
base_url=$repository/releases/download/v$version
printf 'Downloading Corpus %s for %s\n' "$version" "$target"
download --output "$temporary/$archive" "$base_url/$archive"
download --output "$temporary/$archive.sha256" "$base_url/$archive.sha256"

# Accept a bare digest or a sha256sum/shasum line naming this archive.
expected=$(awk -v name="$archive" '
  NF {
    count++
    if (NF != 1 && !(NF == 2 && ($2 == name || $2 == "*" name))) bad = 1
    hash = $1
  }
  END { if (count != 1 || bad) exit 1; print hash }
' "$temporary/$archive.sha256") || fail 'Malformed checksum file.'
printf '%s\n' "$expected" | grep -Eq '^[0-9a-fA-F]{64}$' \
  || fail 'Malformed SHA-256 digest.'
expected=$(printf '%s' "$expected" | tr 'A-F' 'a-f')
if [[ "$checksum_tool" == sha256sum ]]; then
  actual=$(sha256sum "$temporary/$archive")
else
  actual=$(shasum -a 256 "$temporary/$archive")
fi
[[ "${actual%% *}" == "$expected" ]] || fail 'SHA-256 mismatch.'

tar -tzf "$temporary/$archive" > "$temporary/members"
member=$(awk '
  /(^|\/)corpus$/ { count++; member = $0 }
  END { if (count != 1) exit 1; print member }
' "$temporary/members") || fail 'Archive must contain exactly one corpus executable.'
case "$member" in
  /*|-*|..|../*|*/../*|*/..) fail 'Unsafe executable path in release archive.' ;;
esac
# Extract only the executable without writing archive-controlled paths.
tar -xOzf "$temporary/$archive" "$member" > "$temporary/corpus"
[[ -s "$temporary/corpus" ]] || fail 'Archive contains an empty executable.'
chmod 755 "$temporary/corpus"
reported_version=$("$temporary/corpus" --version)
case "$reported_version" in
  "corpus $version"|"corpus $version "*) ;;
  *) fail "Version mismatch: expected corpus $version, got $reported_version" ;;
esac

install_dir=$HOME/.corpus/bin
mkdir -p "$install_dir"
[[ ! -d "$install_dir/corpus" ]] || fail "$install_dir/corpus is a directory."
# Stage on the destination filesystem so publishing the verified binary is atomic.
staged=$(mktemp "$install_dir/.corpus-install.XXXXXXXX")
cp "$temporary/corpus" "$staged"
chmod 755 "$staged"
mv -f "$staged" "$install_dir/corpus"
echo "$install_dir" >> "$GITHUB_PATH"
