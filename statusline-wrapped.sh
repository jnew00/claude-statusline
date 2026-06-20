#!/bin/bash
# Chain target for the kickbacks CLI adapter (it stacks its ad above this).
# Renders the full usage HUD. Codebacks earnings are pulled directly into the
# HUD's bottom box; codebacks impressions are reported by its hooks, so its ad
# line is intentionally NOT displayed here.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/statusline-with-usage.sh"
