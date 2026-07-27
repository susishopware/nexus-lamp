#!/usr/bin/env bash
# Builds the firmware and assembles everything the installer directory needs:
#
#   nexus-lampe.factory.bin   full image, flashed from the browser by ESP Web Tools
#   nexus-lampe.ota.bin       update image, pulled by lamps already in the field
#   manifest.json             serves both, generated from project_version + md5
#
# Publish this directory over https (GitHub Pages is enough) and point
# `update_manifest_url` in the firmware at the manifest.
set -euo pipefail

cd "$(dirname "$0")/.."

version=$(sed -nE 's/^[[:space:]]*project_version:[[:space:]]*"([^"]+)".*/\1/p' \
  firmware/nexus-lampe.yaml | head -1)
if [[ -z $version ]]; then
  echo "could not read project_version from firmware/nexus-lampe.yaml" >&2
  exit 1
fi

# Local checkout uses the venv; CI has esphome straight on PATH.
if [[ -x .venv/bin/esphome ]]; then
  esphome=.venv/bin/esphome
else
  esphome=esphome
fi

"$esphome" compile firmware/nexus-lampe.yaml

build="firmware/.esphome/build/nexus-lampe/build"
cp "$build/firmware.factory.bin" installer/nexus-lampe.factory.bin
cp "$build/firmware.ota.bin" installer/nexus-lampe.ota.bin

# The lamp refuses an update whose md5 does not match, so this has to be the
# hash of the exact ota image we just copied.
if command -v md5sum >/dev/null; then
  md5=$(md5sum installer/nexus-lampe.ota.bin | cut -d' ' -f1)
else
  md5=$(md5 -q installer/nexus-lampe.ota.bin)
fi

cat > installer/manifest.json <<JSON
{
  "name": "Nexus Lampe",
  "version": "$version",
  "home_assistant_domain": "esphome",
  "new_install_prompt_erase": true,
  "improv": true,
  "builds": [
    {
      "chipFamily": "ESP32",
      "parts": [
        { "path": "nexus-lampe.factory.bin", "offset": 0 }
      ],
      "ota": {
        "path": "nexus-lampe.ota.bin",
        "md5": "$md5",
        "summary": "Nexus Lampe $version"
      }
    }
  ]
}
JSON

printf 'version   %s\n' "$version"
printf 'ota md5   %s\n' "$md5"
printf 'factory   %s\n' "$(du -h installer/nexus-lampe.factory.bin | cut -f1)"
printf 'ota       %s\n' "$(du -h installer/nexus-lampe.ota.bin | cut -f1)"
printf 'manifest  installer/manifest.json\n'
