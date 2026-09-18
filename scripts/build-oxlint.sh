#!/usr/bin/env bash
# Build oxlint + tsgolint from local checkouts and stage them in .oxlint-internal/.
#
# Type-aware linting of .gts/.gjs needs two changes that are not released:
#   oxlint    routes files it only knows through a languageOptions.parser override
#             to tsgolint, instead of skipping them   (oxc-project/oxc#26236)
#   tsgolint  honors the tsconfig's contentMappers   (oxc-project/tsgolint#1166)
#
# Point OXC_DIR and TSGOLINT_DIR at checkouts of those branches.
set -euo pipefail

OXC_DIR="${OXC_DIR:?set OXC_DIR to an oxc checkout on the branch from oxc#26236}"
TSGOLINT_DIR="${TSGOLINT_DIR:?set TSGOLINT_DIR to a tsgolint checkout on the branch from tsgolint#1166}"
# oxc's own build wants a recent Node; ember-content-mapper's floor is 22.21.1.
BUILD_NODE="${BUILD_NODE:-24.12.0}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$repo_root/.oxlint-internal"

for dir in "$OXC_DIR" "$TSGOLINT_DIR"; do
  [ -d "$dir" ] || { echo "missing checkout: $dir" >&2; exit 1; }
done

echo "==> tsgolint ($TSGOLINT_DIR)"
(cd "$TSGOLINT_DIR" && go build -ldflags="-s -w" -trimpath -o tsgolint ./cmd/tsgolint)

echo "==> oxlint ($OXC_DIR)"
if command -v volta >/dev/null 2>&1; then
  (cd "$OXC_DIR/apps/oxlint" && volta run --node "$BUILD_NODE" -- pnpm run build)
else
  (cd "$OXC_DIR/apps/oxlint" && pnpm run build)
fi

echo "==> staging into $dest"
rm -rf "$dest"
mkdir -p "$dest/oxlint/bin" "$dest/bin"
cp -R "$OXC_DIR/apps/oxlint/dist" "$dest/oxlint/dist"
cp "$OXC_DIR/npm/oxlint/package.json" "$dest/oxlint/package.json"
cp "$OXC_DIR/npm/oxlint/bin/oxlint" "$dest/oxlint/bin/oxlint"
cp "$TSGOLINT_DIR/tsgolint" "$dest/bin/tsgolint"
chmod +x "$dest/oxlint/bin/oxlint" "$dest/bin/tsgolint"

# Record what was staged, so a stale build is identifiable.
{
  echo "oxc:      $(git -C "$OXC_DIR" rev-parse --short HEAD) ($(git -C "$OXC_DIR" rev-parse --abbrev-ref HEAD))"
  echo "tsgolint: $(git -C "$TSGOLINT_DIR" rev-parse --short HEAD) ($(git -C "$TSGOLINT_DIR" rev-parse --abbrev-ref HEAD))"
  echo "built:    $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(uname -sm)"
} > "$dest/BUILD-INFO"

cat "$dest/BUILD-INFO"
