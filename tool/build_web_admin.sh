#!/usr/bin/env bash
# Bygger Flutter Web til forælder-admin UDEN projektets tunge assets og UDEN alfamon_trace.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BACKUP="${ROOT}/pubspec.yaml.bak.web_admin_$$"

restore_pubspec() {
  if [[ -f "$BACKUP" ]]; then
    mv "$BACKUP" "${ROOT}/pubspec.yaml"
    (cd "$ROOT" && flutter pub get)
  fi
}
trap restore_pubspec EXIT INT TERM

cp "${ROOT}/pubspec.yaml" "$BACKUP"
cp "${ROOT}/pubspec_web.yaml" "${ROOT}/pubspec.yaml"

flutter pub get
flutter build web --release "$@"

trap - EXIT INT TERM
restore_pubspec

echo "Færdig: build/web/ (admin-web, minimale assets). Upload hele build/web/."
