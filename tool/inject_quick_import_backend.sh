#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <private-source-root>" >&2
  exit 64
fi

private_root="$1"
private_impl="$private_root/lib/services/quick_import/local_quick_import_backend.dart"
private_binding="$private_root/lib/services/quick_import/backend_binding.dart"
target_dir="lib/services/quick_import"

for source_file in "$private_impl" "$private_binding"; do
  if [[ ! -f "$source_file" ]]; then
    echo "Missing required private source: $source_file" >&2
    exit 66
  fi
done

if ! grep -q "LocalQuickImportBackend" "$private_binding"; then
  echo "Private binding does not select LocalQuickImportBackend." >&2
  exit 65
fi

install -m 600 "$private_impl" "$target_dir/local_quick_import_backend.dart"
install -m 600 "$private_binding" "$target_dir/backend_binding.dart"

echo "Injected private quick-import backend."
