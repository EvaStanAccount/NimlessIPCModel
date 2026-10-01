#!/usr/bin/env bash
set -euo pipefail

mode="${1:-debug}"
target="${2:-all}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/$mode"
mkdir -p "$out"

common=(-d:mingw)
case "$mode" in
  debug)
    common+=(-d:debug)
    ;;
  inspect)
    common+=(-d:debug --lineDir:on)
    ;;
  release)
    common+=(--t:"-s" --l:"-Wl,-s")
    ;;
  *)
    echo "usage: tools/build.sh [debug|inspect|release] [all|server|client|tests]" >&2
    exit 2
    ;;
esac

build_one() {
  local name="$1"
  local src="$2"
  nim c "${common[@]}" -o:"$out/$name.exe" "$root/$src"
}

case "$target" in
  all)
    build_one named-pipe-server src/server.nim
    build_one named-pipe-client src/client.nim
    build_one protocol-tests tests/protocol_tests.nim
    ;;
  server)
    build_one named-pipe-server src/server.nim
    ;;
  client)
    build_one named-pipe-client src/client.nim
    ;;
  tests)
    build_one protocol-tests tests/protocol_tests.nim
    ;;
  *)
    echo "unknown target: $target" >&2
    exit 2
    ;;
esac

printf 'built %s %s in %s\n' "$mode" "$target" "$out"
