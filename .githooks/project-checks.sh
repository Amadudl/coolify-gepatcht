#!/bin/sh
# Projektpruefungen fuer den pre-commit Hook (coolify-gepatcht): Shell Syntax, Workflow.
set -e
cd "$(git rev-parse --show-toplevel)"
sh -n test.sh
sh -n scripts/raise-modules.sh
if command -v actionlint >/dev/null 2>&1; then
  actionlint -no-color
fi
