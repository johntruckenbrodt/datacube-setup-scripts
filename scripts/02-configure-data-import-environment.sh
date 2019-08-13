#!/bin/bash
#
# Copyright (C) 2018 Felix Glaser
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -e

SCRIPTDIR="$(readlink -f "$(dirname "$0")")"
declare -r SCRIPTDIR

# shellcheck source=/dev/null
source "$SCRIPTDIR/util.sh"

echo "[DATACUBE-SETUP] Installing additional packages for data import into conda environment..."

declare -ra PYTHON_PACKAGES=(
  "numpy"
  "pathlib"
  "pyyaml"
  "python-dateutil"
  "rasterio"
  "shapely"
  "cachetools"
)

conda install --name "$CUBEENV" --yes "${PYTHON_PACKAGES[@]}"

echo "[DATACUBE-SETUP] Installed additional packages for import."

echo "[DATACUBE-SETUP] Creating datacube data directories..."

mkdir -vp "$DATA_HOME"
mkdir -vp "$DATA_HOME/ingested_data"
mkdir -vp "$DATA_HOME/original_data"

chmod --recursive 775 "$DATA_HOME"

echo "[DATACUBE-SETUP] Created datacube data directories."
