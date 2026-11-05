#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$PROJECT_ROOT/artifacts}"
STAMP="${STAMP:-$(date +%Y%m%d-%H%M%S)}"
ARCHIVE="$OUT_DIR/pact-project-$STAMP.tgz"
B64_FILE="$ARCHIVE.b64"

mkdir -p "$OUT_DIR"

EXCLUDES="$(mktemp)"
trap 'rm -f "$EXCLUDES"' EXIT

# Always exclude VCS metadata and the output directory.
cat >>"$EXCLUDES" <<'EOF'
.git
.svn
.hg
.bzr
CVS
_darcs
artifacts
*.tgz
*.b64
EOF

# Translate each .gitignore into tar exclude patterns. Patterns are relative to
# the directory containing the .gitignore, so prefix them with that directory.
while IFS= read -r ignore_file; do
  ignore_dir="$(dirname "$ignore_file")"
  rel_dir="${ignore_dir#"$PROJECT_ROOT"}"
  rel_dir="${rel_dir#/}"

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line="${raw_line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue

    if [[ "$line" == !* ]]; then
      printf 'warning: unsupported gitignore negation ignored: %s\n' "$line" >&2
      continue
    fi

    pattern="${line#/}"
    pattern="${pattern%/}"

    [ -z "$pattern" ] && continue

    if [ -n "$rel_dir" ]; then
      printf '%s/%s\n' "$rel_dir" "$pattern" >>"$EXCLUDES"
    fi

    # A gitignore pattern without a slash matches at any depth; tar treats a
    # bare name the same way, so keep the unprefixed form too.
    if [[ "$pattern" != */* ]]; then
      printf '%s\n' "$pattern" >>"$EXCLUDES"
    fi
  done <"$ignore_file"
done < <(find "$PROJECT_ROOT" -name .gitignore -not -path '*/.git/*' -not -path '*/node_modules/*' | sort)

printf 'Creating %s\n' "$ARCHIVE"
tar \
  --exclude-from="$EXCLUDES" \
  -czf "$ARCHIVE" \
  -C "$PROJECT_ROOT" .

if tar -tzf "$ARCHIVE" | grep -Eq '(^|/)\.git/|(^|/)node_modules/'; then
  printf 'ERROR: archive still contains .git or node_modules\n' >&2
  exit 1
fi

printf 'Encoding %s\n' "$B64_FILE"
base64 -w 0 "$ARCHIVE" >"$B64_FILE"
printf '\n' >>"$B64_FILE"

printf '\nDone:\n'
printf '  archive: %s (%s)\n' "$ARCHIVE" "$(du -h "$ARCHIVE" | cut -f1)"
printf '  base64:  %s (%s)\n' "$B64_FILE" "$(du -h "$B64_FILE" | cut -f1)"
printf '\nDecode with: base64 -d %q > %q\n' "$B64_FILE" "${ARCHIVE%.tgz}.decoded.tgz"
