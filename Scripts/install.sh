#!/bin/sh
set -eu

usage() {
  echo 'Usage: install.sh [--product swift-agent] [BIN_DIRECTORY]'
  echo 'Build and install a self-contained executable from this checkout (default: ~/.local/bin).'
  echo 'Run again after updating the checkout to install a newer build.'
}

product=swift-agent
if [ "${1:-}" = --product ]; then
  product=${2:-}
  case "$product" in swift-agent) shift 2 ;; *) usage >&2; exit 1 ;; esac
fi
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ -z "$1" ]; }; then
  usage >&2
  exit 1
fi

source_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin_directory=${1:-"$HOME/.local/bin"}
mkdir -p -- "$bin_directory"
bin_directory=$(CDPATH= cd -- "$bin_directory" && pwd)

swift build --package-path "$source_directory" -c release --product "$product"
build_directory=$(swift build --package-path "$source_directory" -c release --show-bin-path)

# Stage beside the destination so replacement is atomic, including on Linux
# where copying over a running executable can fail with "Text file busy".
staged_binary=$(mktemp "$bin_directory/.$product.XXXXXX")
trap 'rm -f -- "$staged_binary"' EXIT
trap 'exit 1' HUP INT TERM
cp -- "$build_directory/$product" "$staged_binary"
chmod 755 "$staged_binary"
"$staged_binary" --version
mv -f -- "$staged_binary" "$bin_directory/$product"
echo "Installed $bin_directory/$product"
case ":$PATH:" in
  *":$bin_directory:"*) ;;
  *) echo "Add $bin_directory to PATH to run $product from any directory." ;;
esac
