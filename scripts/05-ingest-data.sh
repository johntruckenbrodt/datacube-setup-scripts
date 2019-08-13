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

SCRIPTDIR="$(readlink -f "$(dirname "$0")")"
declare -r SCRIPTDIR

# shellcheck source=/dev/null
source "$SCRIPTDIR/util.sh"

_activate

echo "[DATACUBE-INGEST] Ingesting sample data..."

echo "[DATACUBE-INGEST] Adding new product definition to datacube..."
datacube product add "$DCUBE_HOME/agdc-v2/ingest/dataset_types/ls8_collections_sr_scene.yaml"

echo "[DATACUBE-INGEST] Preparing data for ingestion..."
python "$DCUBE_HOME/agdc-v2/ingest/prepare_scripts/usgs_ls_ard_prepare.py" "$DCUBE_HOME"/data/original_data/LC08*

echo "[DATACUBE-INGEST] Adding dataset metadata to datacube..."
datacube dataset add "$DCUBE_HOME"/data/original_data/LC08*/*.yaml --auto-match

echo "[DATACUBE-INGEST] Ingesting data..."
datacube -v ingest \
  -c "$DCUBE_HOME/agdc-v2/ingest/ingestion_configs/ls8_collections_sr_fuente_de_piedra_example.yaml" \
  --executor multiproc 2

_deactivate

echo "[DATACUBE-INGEST] Data ingestion finished."
