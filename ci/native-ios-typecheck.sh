#!/usr/bin/env bash
# Native Apple-framework compile gate for Zen Note.
#
# The Linux swift Docker build only reaches ZenNoteCore because Package.swift
# gates AppModule behind canImport(AppleProductTypes). This script compiles
# every AppModule source (SwiftUI/UIKit/PDFKit/PencilKit) against Xcode's iOS
# simulator SDK instead, with a separately compiled, matching ZenNoteCore.
#
# It then regenerates the one-file v1 migration helper, recovers the exact v1
# sources from the v1 commit, compiles the v1 core the same way, and compiles
# the generated helper together with the remaining v1 AppModule sources.
#
# Both gates always run; a failing current app never hides helper diagnostics.
# No signing, no Apple developer membership, no test targets, no simulator run.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${CI_OUT:-$ROOT/ci-out}"
V1_COMMIT="144cf16b016474ba1c0036bfb1f2822ef99a9784"
TARGET="arm64-apple-ios16.0-simulator"

rm -rf "$OUT"
mkdir -p "$OUT/app-core" "$OUT/app-module" "$OUT/v1-core" "$OUT/v1-module" \
         "$OUT/v1-sources/ZenNoteCore" "$OUT/v1-sources/AppModule"

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"
SWIFT_FLAGS=(-sdk "$SDK" -target "$TARGET" -swift-version 5 -parse-as-library)

SUMMARY="$OUT/diagnostics-summary.txt"
: > "$SUMMARY"

say() {
  printf '%s\n' "$*"
  printf '%s\n' "$*" >> "$SUMMARY"
}

print_cmd() {
  local rendered="+"
  local arg
  for arg in "$@"; do
    rendered="$rendered $(printf '%q' "$arg")"
  done
  say "$rendered"
}

print_sources() {
  local file
  for file in "$@"; do
    say "    ${file#"$ROOT"/}"
  done
}

collect_diagnostics() {
  grep -E '(error|warning): ' "$1" 2>/dev/null | head -n 300 >> "$SUMMARY" || true
}

say "## Zen Note native compile gate"
say "- target: $TARGET (minimum deployment iOS 16.0, Swift language version 5)"
say "- SDK: iphonesimulator $SDK_VERSION"
say "- SDK path: $SDK"
say "- compiler: $(swift --version 2>&1 | head -n 2 | tr '\n' ' ')"
say ""

app_status="FAIL"
v1_status="FAIL"

# ---------------------------------------------------------------- Gate 1 ----
say "## Gate 1/2: current app"
say "### ZenNoteCore (current), compiled separately for the simulator SDK"
core_sources=("$ROOT"/ZenNote.swiftpm/Sources/ZenNoteCore/*.swift)
say "sources (${#core_sources[@]}):"
print_sources "${core_sources[@]}"

print_cmd swiftc "${SWIFT_FLAGS[@]}" -module-name ZenNoteCore -emit-module \
  -emit-module-path "$OUT/app-core/ZenNoteCore.swiftmodule" "${core_sources[@]}"
swiftc "${SWIFT_FLAGS[@]}" -module-name ZenNoteCore -emit-module \
  -emit-module-path "$OUT/app-core/ZenNoteCore.swiftmodule" \
  "${core_sources[@]}" > "$OUT/app-core-module.log" 2>&1
core_module_status=$?

print_cmd swiftc "${SWIFT_FLAGS[@]}" -module-name ZenNoteCore -whole-module-optimization \
  -c -o "$OUT/app-core/ZenNoteCore.o" "${core_sources[@]}"
swiftc "${SWIFT_FLAGS[@]}" -module-name ZenNoteCore -whole-module-optimization \
  -c -o "$OUT/app-core/ZenNoteCore.o" \
  "${core_sources[@]}" > "$OUT/app-core-object.log" 2>&1
core_object_status=$?

printf '%s\n' "--- swiftc ZenNoteCore module ---"
cat "$OUT/app-core-module.log"
printf '%s\n' "--- swiftc ZenNoteCore object ---"
cat "$OUT/app-core-object.log"
collect_diagnostics "$OUT/app-core-module.log"
collect_diagnostics "$OUT/app-core-object.log"

say "### AppModule (current)"
app_sources=("$ROOT"/ZenNote.swiftpm/Sources/AppModule/*.swift)
say "sources (${#app_sources[@]}):"
print_sources "${app_sources[@]}"

print_cmd swiftc "${SWIFT_FLAGS[@]}" -module-name AppModule -I "$OUT/app-core" -c \
  "${app_sources[@]}"
( cd "$OUT/app-module" && swiftc "${SWIFT_FLAGS[@]}" -module-name AppModule \
  -I "$OUT/app-core" -c "${app_sources[@]}" ) > "$OUT/app-module.log" 2>&1
app_module_status=$?

printf '%s\n' "--- swiftc AppModule ---"
cat "$OUT/app-module.log"
collect_diagnostics "$OUT/app-module.log"
say "AppModule objects emitted: $(ls -1 "$OUT/app-module" 2>/dev/null | grep -c '\.o$')"

if [ "$core_module_status" -eq 0 ] && [ "$core_object_status" -eq 0 ] \
   && [ "$app_module_status" -eq 0 ]; then
  app_status="PASS"
fi
say "Gate 1 result: $app_status (core module=$core_module_status, core object=$core_object_status, AppModule compile=$app_module_status)"
say ""

# ---------------------------------------------------------------- Gate 2 ----
say "## Gate 2/2: one-file v1 migration helper (v1 commit ${V1_COMMIT:0:7})"

node "$ROOT/scripts/package-v1-migration.mjs" > "$OUT/generate.log" 2>&1
gen_status=$?
cat "$OUT/generate.log"
say "package-v1-migration.mjs exit=$gen_status"
say "helper guard lines:"
grep -n 'ZENNOTE_MIGRATION_PORTABLE' "$ROOT/migrations/v1/ContentView.swift" 2>/dev/null \
  | head -n 5 | while IFS= read -r line; do say "    $line"; done
say "ZENNOTE_MIGRATION_PORTABLE is NOT defined here; the SwiftUI/UIKit branch must compile."

extract_ok=1
say "recovering v1 sources from git:"
for name in DiskStore Models; do
  git -C "$ROOT" show "$V1_COMMIT:ZenNote.swiftpm/Sources/ZenNoteCore/$name.swift" \
    > "$OUT/v1-sources/ZenNoteCore/$name.swift" || extract_ok=0
done
for name in AppModel DrawingSettings DrawingSurface LocalWriter Notebook PDFReader ZenNoteApp; do
  git -C "$ROOT" show "$V1_COMMIT:ZenNote.swiftpm/Sources/AppModule/$name.swift" \
    > "$OUT/v1-sources/AppModule/$name.swift" || extract_ok=0
done
say "v1 extraction ok=$extract_ok; v1 ContentView.swift is intentionally excluded (replaced by the generated helper)"

if [ "$gen_status" -eq 0 ] && [ "$extract_ok" -eq 1 ]; then
  say "### ZenNoteCore (v1), compiled separately for the simulator SDK"
  v1_core_sources=("$OUT/v1-sources/ZenNoteCore/"*.swift)
  print_sources "${v1_core_sources[@]}"

  print_cmd swiftc "${SWIFT_FLAGS[@]}" -module-name ZenNoteCore -emit-module \
    -emit-module-path "$OUT/v1-core/ZenNoteCore.swiftmodule" "${v1_core_sources[@]}"
  swiftc "${SWIFT_FLAGS[@]}" -module-name ZenNoteCore -emit-module \
    -emit-module-path "$OUT/v1-core/ZenNoteCore.swiftmodule" \
    "${v1_core_sources[@]}" > "$OUT/v1-core-module.log" 2>&1
  v1_core_module_status=$?

  print_cmd swiftc "${SWIFT_FLAGS[@]}" -module-name ZenNoteCore -whole-module-optimization \
    -c -o "$OUT/v1-core/ZenNoteCore.o" "${v1_core_sources[@]}"
  swiftc "${SWIFT_FLAGS[@]}" -module-name ZenNoteCore -whole-module-optimization \
    -c -o "$OUT/v1-core/ZenNoteCore.o" \
    "${v1_core_sources[@]}" > "$OUT/v1-core-object.log" 2>&1
  v1_core_object_status=$?

  printf '%s\n' "--- swiftc v1 ZenNoteCore module ---"
  cat "$OUT/v1-core-module.log"
  printf '%s\n' "--- swiftc v1 ZenNoteCore object ---"
  cat "$OUT/v1-core-object.log"
  collect_diagnostics "$OUT/v1-core-module.log"
  collect_diagnostics "$OUT/v1-core-object.log"

  say "### v1 AppModule with generated ContentView.swift"
  v1_app_sources=("$OUT/v1-sources/AppModule/"*.swift "$ROOT/migrations/v1/ContentView.swift")
  print_sources "${v1_app_sources[@]}"

  print_cmd swiftc "${SWIFT_FLAGS[@]}" -module-name AppModule -I "$OUT/v1-core" -c \
    "${v1_app_sources[@]}"
  ( cd "$OUT/v1-module" && swiftc "${SWIFT_FLAGS[@]}" -module-name AppModule \
    -I "$OUT/v1-core" -c "${v1_app_sources[@]}" ) > "$OUT/v1-module.log" 2>&1
  v1_module_status=$?

  printf '%s\n' "--- swiftc v1 AppModule ---"
  cat "$OUT/v1-module.log"
  collect_diagnostics "$OUT/v1-module.log"
  say "v1 AppModule objects emitted: $(ls -1 "$OUT/v1-module" 2>/dev/null | grep -c '\.o$')"

  if [ "$v1_core_module_status" -eq 0 ] && [ "$v1_core_object_status" -eq 0 ] \
     && [ "$v1_module_status" -eq 0 ]; then
    v1_status="PASS"
  fi
  say "Gate 2 result: $v1_status (core module=$v1_core_module_status, core object=$v1_core_object_status, AppModule compile=$v1_module_status)"
else
  say "Gate 2 cannot compile: generation exit=$gen_status extraction_ok=$extract_ok"
fi

say ""
say "## Result"
say "current app gate: $app_status"
say "v1 migration helper gate: $v1_status"

if [ "$app_status" = "PASS" ] && [ "$v1_status" = "PASS" ]; then
  exit 0
fi
exit 1
