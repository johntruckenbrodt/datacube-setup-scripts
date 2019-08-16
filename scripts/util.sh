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

################################################################################
# Utility script to be sourced by the other scripts or for interactive work
################################################################################

# prevent this file from being executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This file is intended to be sourced. Executing it is pointless." >>/dev/stderr
  exit 1
fi

################################################################################
# Constants
################################################################################
if [[ -z "$SCRIPTDIR" ]]; then
  echo "Error: Cannot find out, in which directory I am. Aborting." >>/dev/stderr
  exit 1
fi

source "$SCRIPTDIR/config"
if [[ -z "$CONDA_SH" ]]; then
  echo "Error: CONDA_SH is not configured. Please configure it in $SCRIPTDIR/config!" >>/dev/stderr
  exit 1
elif [[ -z "$DCUBE_HOME" ]]; then
  echo "Error: DCUBE_HOME is not configured. Please configure it in $SCRIPTDIR/config!" >>/dev/stderr
  exit 1
elif [[ -z "$CUBEENV" ]]; then
  echo "Warning: No name for the Datacube conda environment configured. Using 'cubeenv'."
  CUBEENV="cubeenv"
fi

# make variables read-only
declare -r CONDA_SH="$CONDA_SH"
declare -r CUBEENV="$CUBEENV"
declare -r DCUBE_HOME="$DCUBE_HOME"

declare -r DATA_HOME="$DCUBE_HOME/data"
declare -r PATCHDIR="$(readlink -f "${SCRIPTDIR}/../patches")"
declare -r CONFDIR="$(readlink -f "${SCRIPTDIR}/../conf")"

# determine init system (non-systemd case is for Ubuntu 16.04)
if pidof systemd >/dev/null; then
  declare -r INITSYS="systemd"
else
  declare -r INITSYS="other"
fi

################################################################################
# Loading conda
################################################################################
# abort if loading conda fails
source "$CONDA_SH" || exit 1

################################################################################
# Helper Functions
################################################################################

##
# Returns 0 if a conda environment is active, else returns 1.
function _isInVenv() {
  if [[ -n "$CONDA_DEFAULT_ENV" ]]; then
    return 0
  else
    return 1
  fi
}

##
# Activates the datacube environment if it is not active yet.
function _activate() {
  _isInVenv || {
    echo "Activating environment $CUBEENV"
    conda activate "$CUBEENV"
  }
}

##
# Deactivates the datacube environment if it is still activated.
function _deactivate() {
  _isInVenv && {
    echo "Deactivating environment $CUBEENV"
    conda deactivate
  }
}

##
# Wrapper for sed to use extended regular expressions. Call with '-s' to run
# sed as super user.
function _exsed() {
  if [[ "$1" == "-s" ]]; then
    shift
    sudo sed --regexp-extended "$@"
  else
    sed --regexp-extended "$@"
  fi
}

##
# Escape a string for sed substitions. This function is expecting input from
# stdin.
function _sedescape() {
  _exsed "s/(\/|\\\\|&)/\\\\\1/g"
}

##
# Helper function for backups. Backs up only when we do not already have
# backup ending in ".datacube.bak".
# usage:
# _backup FILE
function _backup() {
  if [[ "$1" == "-s" ]]; then
    local use_sudo=1
    shift
  fi

  if [[ ! -e "${1}.datacube.bak" ]]; then
    echo "[NOTICE] Creating a backup of '$1' named '${1}.datacube.bak'..."
    if [[ $use_sudo -eq 1 ]]; then
      sudo cp -v "$1" "${1}.datacube.bak"
    else
      cp -v "$1" "${1}.datacube.bak"
    fi
  fi
}

# check if a postgresql user exists; returns 1 if true
# usage:
# _pguser_exist username
function _pguser_exist() {
  sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$1'"
}

# check if a database exists for a user
# usage:
# _pgdb_exist username databasename; returns 1 if true
function _pgdb_exist() {
  psql -U "$1" -tAc "SELECT 1 FROM pg_database WHERE datname='$2'"
}
