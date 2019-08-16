#!/bin/bash
#
# Copyright (C) 2018-2019 Felix Glaser, John Truckenbrodt
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

# exit immediately if a command exits with a non-zero status
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
  sudo yum check-update
  sudo yum install binutils
fi

echo "[DATACUBE-SETUP] Setting up conda and creating environment..."

conda update --yes -n base -c defaults conda
conda config --append channels conda-forge

if ! conda info --envs | grep -q "^$CUBEENV"; then
  echo "[DATACUBE-SETUP] creating virtual environment $CUBEENV"
  conda create --yes --name "$CUBEENV" python=3.6
fi
conda install -n "$CUBEENV" datacube cython jupyter matplotlib scipy

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
    sudo yum -y install postgresql postgresql-server postgresql-contrib
  fi

  echo "[DATACUBE-SETUP] Configuring postgresql..."
  # collect info about the currently running postgresql service and its configuration files
  pg_service=$(systemctl list-unit-files | grep enabled | grep '^postgresql' | awk '{ print $1 }')
  pg_hba=$(sudo -u postgres psql -P format=unaligned -c "show hba_file;" | head -2 | tail -1)
  pg_conf="${pg_hba/pg_hba/postgresql}"
  echo "running $pg_service with configuration in"
  echo " - $pg_hba"
  echo " - $pg_conf"
  ##########################################################################
  # modify pg_hba.conf
  _backup -s "$pg_hba"
  # configuring tcp socket access for $DB_USER
  if ! sudo egrep "^host\s+all\s+${DB_USER}\s+samenet\s+trust$" "$pg_hba" >/dev/null; then
    echo "host    all             ${DB_USER}             samenet                 trust" |
      sudo tee --append "$pg_hba"
  fi
  # this alone was found to not work properly in some situations;
  # instead, adjusting the following did the trick:
  # from
  # host    all             all             127.0.0.1/32            ident
  # host    all             all             ::1/128                 ident
  # to
  # host    all             all             127.0.0.1/32            md5
  # host    all             all             ::1/128                 md5
  # this can be achieved with the following line:
  # sed -i -E 's/(host +all +all[ a-z0-9\.\:/]*)ident/\1md5/g' "$pg_hba"
  unset pg_hba arr
  ##########################################################################
  # modify postgresql.conf
  _backup -s "$pg_conf"
  _exsed -s --in-place \
    -e 's/^#?(max_connections =) ?[0-9]+(.*)/\1 1000\2/' \
    -e "s%^#?(unix_socket_directories =) ?('[A-Za-z/-]+)'(.*)%\1 \2,/tmp'\3%" \
    -e 's/^#?(shared_buffers =) ?[0-9]+[kMG]B(.*)/\1 4096MB\2/' \
    -e 's/^#?(work_mem =) ?[0-9]+[kMG]B(.*)/\1 64MB\2/' \
    -e 's/^#?(maintenance_work_mem =) ?[0-9]+[kMG]B(.*)/\1 256MB\2/' \
    -e "s/^#?(timezone =) ?'[A-Za-z-]+'(.*)/\1 'UTC'\2/" \
    "$pg_conf"

  unset pg_conf arr
  ##########################################################################
  # restart postgresql service after the configuration changes
  if [[ "$INITSYS" == "systemd" ]]; then
    sudo systemctl restart "$pg_service"
  else
    sudo service "${pg_service/\.service/}" restart
  fi
  unset pg_service
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
if ! [ "$(_pguser_exist "$DB_USER")" = '1' ]; then
  echo " - adding new user $DB_USER"
  sudo --user=postgres createuser --superuser "$DB_USER"
fi
if ! [ "$(_pgdb_exist "$DB_USER" "$DB_USER")" = '1' ]; then
  echo " - creating database $DB_USER for user $DB_USER"
  createdb
fi
sudo --user=postgres psql --command="ALTER USER $DB_USER WITH PASSWORD '$DB_PASSWD';"
if ! [ "$(_pgdb_exist "$DB_USER" datacube)" = '1' ]; then
  echo " - creating database datacube for user $DB_USER"
  createdb datacube
fi
unset user_exist db_exist
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
