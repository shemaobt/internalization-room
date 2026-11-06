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
build_number="$(version_at "$head" | sed -n 's/^version:.*+\([0-9][0-9]*\)[[:space:]]*$/\1/p')"
if [ -z "$build_number" ]; then
  echo "::error::The version in pubspec.yaml carries no +N. The stores take the build number from pubspec.yaml alone; write the version as x.y.z+N." >&2
  exit 1
fi
echo "build_number=$build_number"
