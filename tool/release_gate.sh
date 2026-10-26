#!/usr/bin/env bash
set -euo pipefail

base="$1"
head="$2"
notes=(fastlane/metadata/pt-BR/release_notes.txt fastlane/metadata/en-US/release_notes.txt)

version_at() {
  git show "$1:pubspec.yaml" | grep '^version:'
}

if [ "$(version_at "$base")" != "$(version_at "$head")" ]; then
  if git diff --quiet "$base" "$head" -- "${notes[@]}"; then
    echo "::error::The version changed, but neither ${notes[0]} nor ${notes[1]} did. A release tells the stores what changed." >&2
    exit 1
  fi
  echo "changed=true"
else
  echo "changed=false"
fi
echo "build_number=$(version_at "$head" | sed 's/.*+//')"
