#!/bin/bash
# Build the app: the Rust archive, the Swift sources, then the bundle.
#
#   scripts/app-build.sh            build Macmon.app in dist/, ad-hoc signed
#   scripts/app-build.sh test       run the Swift tests
#   scripts/app-build.sh run        build, then open the app
#   scripts/app-build.sh install    build, then copy the app to /Applications (or ~/Applications)
#   scripts/app-build.sh uninstall  remove the installed app
#
# DEST overrides where install puts it, used by the sandbox test and by anyone who wants it
# elsewhere. Nothing here needs sudo: /Applications is writable by an administrator.
#
# The Rust archive is linked here rather than in Package.swift: SwiftPM cannot express a
# repository-relative search path, and the archive needs Apple's private IOReport stub, which
# the Rust `#[link]` attributes do not carry into it.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

app_name=Macmon
bundle=$root/dist/$app_name.app
archive=$root/target/release/libmacmon_ffi.a
dest=${DEST:-/Applications}
installed=$dest/$app_name.app

# `-L`/`-l` and every framework, in this order: the linker resolves the archive's undefined
# symbols from what follows it.
link_flags=(
  -Xlinker -L"$root/target/release"
  -Xlinker -lmacmon_ffi
  -Xlinker -framework -Xlinker CoreFoundation
  -Xlinker -framework -Xlinker IOKit
  -Xlinker -framework -Xlinker Foundation
  -Xlinker -lIOReport
)

echo "==> cargo build --release -p macmon-ffi"
cargo build --release --locked -p macmon-ffi
test -f "$archive" || { echo "no archive at $archive" >&2; exit 1; }

case "${1:-build}" in
test)
  echo "==> swift test"
  exec swift test --package-path macos "${link_flags[@]}"
  ;;
uninstall)
  if [ -d "$installed" ]; then
    rm -rf "$installed"
    echo "==> removed $installed"
  else
    echo "==> nothing installed at $installed"
  fi
  exit 0
  ;;
esac

echo "==> swift build -c release"
swift build -c release --package-path macos "${link_flags[@]}"
bin=$(swift build -c release --package-path macos --show-bin-path)/MacmonApp
test -x "$bin" || { echo "no app binary at $bin" >&2; exit 1; }

echo "==> assembling $bundle"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin" "$bundle/Contents/MacOS/$app_name"
cp macos/Resources/Info.plist "$bundle/Contents/Info.plist"
if [ -f macos/Resources/Macmon.icns ]; then
  cp macos/Resources/Macmon.icns "$bundle/Contents/Resources/$app_name.icns"
else
  echo "==> no icon: run scripts/make-icon.sh to build one" >&2
fi

echo "==> codesign (ad-hoc)"
codesign --force --sign - --timestamp=none "$bundle"
codesign --verify --strict "$bundle"
echo "==> $bundle"

case "${1:-build}" in
run)
  open "$bundle"
  ;;
install)
  # An explicit DEST is created if missing; the default /Applications needs administrator rights,
  # and a user without them gets ~/Applications rather than a sudo prompt.
  if [ ! -d "$dest" ]; then
    mkdir -p "$dest" 2>/dev/null || true
  fi
  if [ ! -w "$dest" ]; then
    dest=$HOME/Applications
    installed=$dest/$app_name.app
    mkdir -p "$dest"
    echo "==> $dest is not writable, installing to $dest instead"
  fi
  rm -rf "$installed"
  cp -R "$bundle" "$installed"
  echo "==> installed $installed"
  echo "==> start at login: right-click the menu bar item and tick 'Start at login'"
  ;;
esac
