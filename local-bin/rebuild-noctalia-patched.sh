#!/usr/bin/env bash
# Build Noctalia with the patches in dotfiles/patches/noctalia for the version pacman has installed.
# Installs into a versioned prefix under ~/.local/opt/noctalia-patched and points ~/.local/bin/noctalia
# (first on niri's PATH) at it. Does nothing if that version + patch set is already built.
# On failure the link is removed so the stock /usr/bin/noctalia runs instead.
set -uo pipefail

PATCH_DIR="$HOME/src/dotfiles/patches/noctalia"
WORK="$HOME/.cache/noctalia-patched"
SRC="$WORK/src"
BUILD="$WORK/build"
ROOT="$HOME/.local/opt/noctalia-patched"
LINK="$HOME/.local/bin/noctalia"
REPO="https://github.com/noctalia-dev/noctalia"

log() { echo "rebuild-noctalia-patched: $*"; }
notify() { notify-send -a "Noctalia" "$1" "${2:-}" >/dev/null 2>&1 || true; }

fail() {
    rm -f "$LINK"
    log "FAILED: $1 (falling back to stock /usr/bin/noctalia)"
    notify "Patched Noctalia build failed" "$1. Using the stock package. Log: journalctl --user -u noctalia-patched-rebuild"
    exit 1
}

# the .path unit fires while pacman is still mid-transaction: wait for it to finish
for _ in $(seq 1 600); do
    [ -e /var/lib/pacman/db.lck ] || break
    sleep 1
done

pkgver=$(pacman -Q noctalia 2>/dev/null | awk '{print $2}')
[ -n "$pkgver" ] || fail "noctalia package not installed"
version="${pkgver%%-*}"
tag="v$version"
shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
[ ${#patches[@]} -gt 0 ] || fail "no patches in $PATCH_DIR"
patch_hash=$(cat "${patches[@]}" | sha256sum | cut -c1-12)
prefix="$ROOT/$tag-$patch_hash"
binary="$prefix/bin/noctalia"

if [ -x "$binary" ] && [ "$(readlink "$LINK" 2>/dev/null)" = "$binary" ]; then
    log "$tag with patches $patch_hash already built"
    exit 0
fi

log "building $tag with ${#patches[@]} patch(es) ($patch_hash)"
mkdir -p "$WORK" "$ROOT"
if [ -d "$SRC/.git" ]; then
    git -C "$SRC" fetch --quiet --depth 1 origin "refs/tags/$tag:refs/tags/$tag" || fail "fetching $tag"
    git -C "$SRC" checkout --quiet --force "$tag" || fail "checking out $tag"
    git -C "$SRC" clean --quiet -fd || fail "cleaning source tree"
else
    git clone --quiet --depth 1 --branch "$tag" "$REPO" "$SRC" || fail "cloning $tag"
fi

for p in "${patches[@]}"; do
    git -C "$SRC" apply "$p" || fail "$(basename "$p") doesn't apply to $tag"
done

# same options as the upstream justfile's release mode, minus test targets
cpp_std=$(sed -nE "s/^cpp-std[[:space:]]*:=[[:space:]]*['\"]?([^'\"[:space:]]+)['\"]?[[:space:]]*$/\1/p" "$SRC/justfile" 2>/dev/null)
args=(--buildtype=release -Db_lto=true -Dtests=disabled --prefix "$prefix")
[ -n "$cpp_std" ] && args+=("-Dcpp_std=$cpp_std")
if [ -f "$BUILD/build.ninja" ]; then
    meson setup --wipe "$BUILD" "$SRC" "${args[@]}" || fail "meson setup"
else
    meson setup "$BUILD" "$SRC" "${args[@]}" || fail "meson setup"
fi
meson compile -C "$BUILD" noctalia || fail "compile"
meson install --no-rebuild --quiet -C "$BUILD" || fail "install"

"$binary" --version 2>/dev/null | grep -qF "$version" || fail "built binary doesn't report version $version"

# swap the link atomically so nothing ever sees a half-written path
ln -s "$binary" "$LINK.new" && mv -T "$LINK.new" "$LINK" || fail "linking $LINK"
log "installed $binary"

# older builds are no longer referenced
for old in "$ROOT"/*/; do
    [ "${old%/}" = "$prefix" ] || gio trash "${old%/}" 2>/dev/null || true
done

# restart the shell onto the patched binary if something else is running
pid=$(pgrep -u "$(id -u)" -x noctalia | head -1)
if [ -n "$pid" ] && [ "$(readlink "/proc/$pid/exe")" != "$binary" ]; then
    kill -TERM "$pid"
    for _ in $(seq 1 50); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    niri msg action spawn-sh -- noctalia || fail "relaunching noctalia"
    log "restarted noctalia"
fi
notify "Noctalia $version rebuilt" "Local patches applied."
