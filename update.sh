#!/usr/bin/env bash
# Refreshes the version and hash in flake.nix from Nanitor's "latest" .deb.
set -euo pipefail
cd "$(dirname "$0")"

url=https://nanitor.io/agents/nanitor-agent-latest_amd64.deb
json=$(nix store prefetch-file --json "$url")
hash=$(nix run nixpkgs#jq -- -r .hash <<<"$json")
path=$(nix run nixpkgs#jq -- -r .storePath <<<"$json")
version=$(nix shell nixpkgs#dpkg -c dpkg-deb -f "$path" Version)

sed -i -E "s|sha256 = \"sha256-[^\"]+\"|sha256 = \"$hash\"|" flake.nix
sed -i -E "s|version = \"[^\"]+\";|version = \"$version\";|" flake.nix
echo "version=$version hash=$hash"
