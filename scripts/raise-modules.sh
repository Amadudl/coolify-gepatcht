#!/bin/sh
# Hebt Go Module auf eine Mindestversion an (Argumente: modul@version ...).
# Neuere Versionen im Modulgraph bleiben stehen, es wird nie zurueckgesetzt.
# Danach go mod tidy und, falls das Projekt vendort, go mod vendor.
set -eu

for spec in "$@"; do
  mod=${spec%@*}
  want=${spec#*@}
  have=$(go list -m -f '{{.Version}}' "$mod" 2>/dev/null || true)
  if [ -z "$have" ]; then
    echo "$mod: nicht im Modulgraph, uebersprungen"
    continue
  fi
  lowest=$(printf '%s\n%s\n' "$have" "$want" | sort -V | head -n 1)
  if [ "$have" != "$want" ] && [ "$lowest" = "$have" ]; then
    go get "$mod@$want"
    echo "$mod: $have -> $want"
  else
    echo "$mod: $have bleibt"
  fi
done

go mod tidy
if [ -d vendor ]; then
  go mod vendor
fi

for spec in "$@"; do
  mod=${spec%@*}
  go list -m -f '{{.Path}} {{.Version}}' "$mod" 2>/dev/null || true
done
