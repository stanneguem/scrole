#!/usr/bin/env bash
set -euo pipefail

# Generates the SQLite WASM runtime and worker required by sqflite_common_ffi_web.
# Run from the repository root after `flutter pub get`.
dart run sqflite_common_ffi_web:setup
