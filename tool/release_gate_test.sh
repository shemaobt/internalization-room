#!/usr/bin/env bash
set -u

gate="$(cd "$(dirname "$0")" && pwd)/release_gate.sh"
failures=0

repo_at() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  mkdir -p "$dir/fastlane/metadata/pt-BR" "$dir/fastlane/metadata/en-US"
  printf 'name: room\nversion: %s\n' "$1" > "$dir/pubspec.yaml"
  : > "$dir/fastlane/metadata/pt-BR/release_notes.txt"
  : > "$dir/fastlane/metadata/en-US/release_notes.txt"
  commit "$dir" first
  echo "$dir"
}

commit() {
  git -C "$1" add -A
  git -C "$1" -c user.name=gate -c user.email=gate@test commit -q --allow-empty -m "$2"
}

expect_line() {
  local name="$1" output="$2" line="$3"
  if ! grep -qx "$line" <<< "$output"; then
    echo "FAIL: $name: expected the line «${line}», got:"
    echo "$output"
    failures=$((failures + 1))
  fi
}

repo="$(repo_at 0.1.0+1)"
printf 'name: room\nversion: 0.1.1+2\n' > "$repo/pubspec.yaml"
echo 'Novidades.' > "$repo/fastlane/metadata/pt-BR/release_notes.txt"
echo "What's new." > "$repo/fastlane/metadata/en-US/release_notes.txt"
commit "$repo" bump
output="$(cd "$repo" && bash "$gate" HEAD~1 HEAD 2>&1)"
expect_line "a raised version with its notes is a release" "$output" "changed=true"
expect_line "a release builds with the +N of the new pubspec" "$output" "build_number=2"

repo="$(repo_at 0.1.0+1)"
echo 'class Room {}' > "$repo/room.dart"
commit "$repo" "a change that is not a release"
output="$(cd "$repo" && bash "$gate" HEAD~1 HEAD 2>&1)"
expect_line "a push that keeps the version builds nothing" "$output" "changed=false"
expect_line "a dispatch on a kept version still knows its +N" "$output" "build_number=1"

repo="$(repo_at 0.1.0+1)"
printf 'name: room\nversion: 0.1.1+2\n' > "$repo/pubspec.yaml"
commit "$repo" "a bump with no note"
output="$(cd "$repo" && bash "$gate" HEAD~1 HEAD 2>&1 >/dev/null)"
status=$?
if [ "$status" -eq 0 ]; then
  echo "FAIL: a bump without a release note fails the gate: it exited 0"
  failures=$((failures + 1))
fi
for note in fastlane/metadata/pt-BR/release_notes.txt fastlane/metadata/en-US/release_notes.txt; do
  if ! grep -qF "$note" <<< "$output"; then
    echo "FAIL: a bump without a release note names ${note} in the log, got:"
    echo "$output"
    failures=$((failures + 1))
  fi
done

repo="$(repo_at 0.1.0+1)"
printf 'name: room\nversion: 0.1.1+2\n' > "$repo/pubspec.yaml"
echo 'Novidades.' > "$repo/fastlane/metadata/pt-BR/release_notes.txt"
commit "$repo" "a bump with one note"
output="$(cd "$repo" && bash "$gate" HEAD~1 HEAD 2>&1)"
expect_line "one changed note is enough, not both" "$output" "changed=true"

repo="$(repo_at 0.1.0+1)"
printf 'name: room\nversion: 0.1.1\n' > "$repo/pubspec.yaml"
echo 'Novidades.' > "$repo/fastlane/metadata/pt-BR/release_notes.txt"
echo "What's new." > "$repo/fastlane/metadata/en-US/release_notes.txt"
commit "$repo" "a bump that drops the build number"
output="$(cd "$repo" && bash "$gate" HEAD~1 HEAD 2>/dev/null)"
status=$?
errors="$(cd "$repo" && bash "$gate" HEAD~1 HEAD 2>&1 >/dev/null)"
if [ "$status" -eq 0 ] || grep -q '^build_number=' <<< "$output"; then
  echo "FAIL: a version with no +N fails the gate instead of building with a made-up number, got:"
  echo "$output"
  failures=$((failures + 1))
fi
if ! grep -qF "pubspec.yaml" <<< "$errors"; then
  echo "FAIL: a version with no +N names pubspec.yaml in the log, got:"
  echo "$errors"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
