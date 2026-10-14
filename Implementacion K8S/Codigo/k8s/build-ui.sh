#!/bin/bash
# Construir pharmago-ui con un tag versionado y desplegarlo sin downtime
# Uso: ./build-ui.sh

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

"$SCRIPT_DIR/build-images.sh" ui
"$SCRIPT_DIR/deploy.sh" ui
