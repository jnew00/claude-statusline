#!/bin/bash
# Chain target for the kickbacks CLI adapter (stacks its ad above this).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/statusline-with-usage.sh"
