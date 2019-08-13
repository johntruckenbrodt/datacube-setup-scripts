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

echo "[DATACUBE-SETUP] Installing some basic packages..."
if [ -n "$(command -v apt-get)" ]; then
  sudo apt update
  sudo apt install binutils
elif [ -n "$(command -v yum)" ]; then
  sudo yum install binutils
fi

echo "[DATACUBE-SETUP] Setting up conda and creating environment..."

conda config --append channels conda-forge
conda create --yes --name "$CUBEENV" python=3.6 datacube cython jupyter matplotlib scipy

echo "[DATACUBE-SETUP] Preparing PostgreSQL for the Datacube..."

echo -n "Enter the name for the database user (must be a valid user in your Linux system, using '$USER' if you enter nothing): "
read -r DB_USER
DB_USER="${DB_USER:-$USER}"

echo -n "Enter a password for the database user (leave empty to generate one): "
read -r DB_PASSWD
DB_PASSWD="${DB_PASSWD:-$(strings /dev/urandom | grep -E -o "[[:alnum:]]*" | tr -d '\n' | fold -b20 | head -n1)}"

echo "[DATACUBE-SETUP] Checking for PostgreSQL installation..."
echo -n "Should PostgreSQL be installed and configured automatically? [y/N] "
read -r install_postgres

case "$install_postgres" in
y | Y)
  echo "[DATACUBE-SETUP] Installing postgresql..."
  if [ -n "$(command -v apt-get)" ]; then
    sudo apt install --assume-yes postgresql postgresql-client postgresql-contrib
  elif [ -n "$(command -v yum)" ]; then
    sudo yum -y install postgresql-server postgresql-contrib
  fi

  # getting postgresql version
  pg_ver="$(dpkg -l postgresql | tail -n1 | awk '{ print $3 }' | cut -d+ -f1)"

  echo "[DATACUBE-SETUP] Configuring postgresql..."

  _backup -s "/etc/postgresql/$pg_ver/main/pg_hba.conf"
  # configuring tcp socket access for $DB_USER
  if ! sudo egrep "^host\s+all\s+${DB_USER}\s+samenet\s+trust$" "/etc/postgresql/$pg_ver/main/pg_hba.conf" >/dev/null; then
    echo "host    all             ${DB_USER}       samenet                 trust" |
      sudo tee --append "/etc/postgresql/$pg_ver/main/pg_hba.conf"
  fi

  _backup -s "/etc/postgresql/$pg_ver/main/postgresql.conf"
  _exsed -s --in-place \
    -e 's/^#?(max_connections =) ?[0-9]+(.*)/\1 1000\2/' \
    -e "s%^#?(unix_socket_directories =) ?('[A-Za-z/-]+)'(.*)%\1 \2,/tmp'\3%" \
    -e 's/^#?(shared_buffers =) ?[0-9]+[kMG]B(.*)/\1 4096MB\2/' \
    -e 's/^#?(work_mem =) ?[0-9]+[kMG]B(.*)/\1 64MB\2/' \
    -e 's/^#?(maintenance_work_mem =) ?[0-9]+[kMG]B(.*)/\1 256MB\2/' \
    -e "s/^#?(timezone =) ?'[A-Za-z-]+'(.*)/\1 'UTC'\2/" \
    "/etc/postgresql/$pg_ver/main/postgresql.conf"

  unset pg_ver

  if [[ "$INITSYS" == "systemd" ]]; then
    sudo systemctl restart postgresql.service
  else
    sudo service postgresql restart
  fi
  ;;
*)
  echo "[DATACUBE-SETUP] Skipping installation and configuration of PostgreSQL..."
  echo "[DATACUBE-SETUP] Please take a look into '${CONFDIR}/postgresql.conf' and the README to see, what needs to be configured."
  echo "[DATACUBE-SETUP] Apply the configuration, reload/restart PostgreSQL and return to this installer."
  echo -n "Continue setup? [ENTER]"
  read -r shall_continue
  unset shall_continue
  ;;
esac
unset install_postgres

echo "[DATACUBE-SETUP] Setting up postgresql database and users..."
sudo --user=postgres createuser --superuser "$DB_USER"
# create database for the newly created user
createdb
sudo --user=postgres psql --command="ALTER USER $DB_USER WITH PASSWORD '$DB_PASSWD';"
createdb datacube

echo "[DATABASE-SETUP] Configuring database access for datacube..."
cat >"$HOME/.datacube.conf" <<CONFIG
[datacube]
db_database: datacube
db_hostname: localhost
db_username: $DB_USER
db_password: $DB_PASSWD
CONFIG

unset DB_USER DB_PASSWD

echo "[DATABASE-SETUP] Initializing datacube..."
_activate
datacube -v system init
_deactivate

echo "[DATACUBE-SETUP] Setup finished."
