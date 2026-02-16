#!@bash@
set -euo pipefail

export PYTHONPATH="@pythonpath@${PYTHONPATH:+:$PYTHONPATH}"
exec @python@ @script@ "$@"
