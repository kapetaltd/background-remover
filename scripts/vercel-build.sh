#!/usr/bin/env bash
# Builds the Flutter web app on Vercel, whose build image has no Flutter SDK.
#   install: fetch a pinned Flutter SDK and the Dart packages
#   build:   compile to build/web (served by Vercel as static files)
set -euo pipefail

FLUTTER_VERSION="3.47.6"
FLUTTER_DIR="$PWD/.flutter"
export PATH="$FLUTTER_DIR/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true

case "${1:-}" in
  install)
    # The Flutter tool unpacks its web artifacts with unzip.
    if ! command -v unzip >/dev/null; then dnf install -y -q unzip; fi
    if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
      git clone --depth 1 --branch "$FLUTTER_VERSION" \
        https://github.com/flutter/flutter.git "$FLUTTER_DIR"
    fi
    git config --global --add safe.directory "$FLUTTER_DIR"
    flutter --disable-analytics >/dev/null
    flutter --version
    flutter pub get
    ;;
  build)
    flutter build web --release
    ;;
  *)
    echo "usage: $0 install|build" >&2
    exit 64
    ;;
esac
