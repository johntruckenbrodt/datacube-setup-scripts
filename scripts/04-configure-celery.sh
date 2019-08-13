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

_activate
celery_bin="$(command -v celery)"
declare -r celery_bin
_deactivate

GROUP="$(id --group --name "$USER")"
declare -r GROUP

function _systemd_celery_setup() {
  echo "[DC_CELERY-SETUP] Installing celery systemd service..."
  _exsed --in-place \
    -e "s,(User=).*,\1$USER," \
    -e "s,(Group=).*,\1$GROUP," \
    -e "s,(WorkingDirectory=).*,\1$DCUBE_HOME/data_cube_ui," \
    "${CONFDIR}/systemd/celery.service"
  sudo install -vDm644 "${CONFDIR}/systemd/celery.service" /etc/systemd/system/celery.service
  _exsed --in-place \
    -e "s,(CELERY_BIN=\").*\",\1$celery_bin\"," \
    "${CONFDIR}/systemd/celery"
  sudo install -vDm644 "${CONFDIR}/systemd/celery" /etc/conf.d/celery

  echo "[DC_CELERY-SETUP] Installing celery-beat service..."
  _exsed --in-place \
    -e "s,(User=).*,\1$USER," \
    -e "s,(Group=).*,\1$GROUP," \
    -e "s,(WorkingDirectory=).*,\1$DCUBE_HOME/data_cube_ui," \
    "${CONFDIR}/systemd/celery-beat.service"
  sudo install -vDm644 "${CONFDIR}/systemd/celery-beat.service" /etc/systemd/system/celery-beat.service
  _exsed --in-place \
    -e "s,(CELERY_BIN=\").*\",\1$celery_bin\"," \
    "${CONFDIR}/systemd/celery-beat"
  sudo install -vDm644 "${CONFDIR}/systemd/celery-beat" /etc/conf.d/celery-beat

  echo "[DC_CELERY-SETUP] Installing tmpfiles.d configuration for celery and celery-beat..."
  sed --in-place -e "s/username/$USER/" -e "s/groupname/$GROUP/" "${CONFDIR}/systemd/celery.conf"
  sudo install -vDm644 "${CONFDIR}/systemd/celery.conf" /etc/tmpfiles.d/celery.conf
  sudo systemd-tmpfiles --create

  echo "[DC_CELERY-SETUP] Reloading systemd configuration..."
  sudo systemctl daemon-reload

  echo "[DC_CELERY-SETUP] Enabling and raising celery and celery-beat services..."
  sudo systemctl enable --now celery
  sudo systemctl enable --now celery-beat
}

function _upstart_celery_setup() {
  echo "[DC_CELERY-SETUP] Installing celery upstart service..."
  sudo install -vDm755 "${CONFDIR}/upstart/celeryd" /etc/init.d/celeryd
  _exsed --in-place \
    -e "s,(CELERY_BIN=\").*\",\1$celery_bin\"," \
    -e "s,(CELERYD_CHDIR=\").*\",\1$DCUBE_HOME/data_cube_ui\"," \
    -e "s,(CELERYD_USER=\").*\",\1$USER\"," \
    -e "s,(CELERYD_GROUP=\").*\",\1$GROUP\"," \
    "${CONFDIR}/upstart/celeryd_conf"
  sudo install -vDm644 "${CONFDIR}/upstart/celeryd_conf" /etc/default/celeryd

  echo "[DC_CELERY-SETUP] Installing celerybeat service..."
  sudo install -vDm755 "${CONFDIR}/upstart/celerybeat" /etc/init.d/celerybeat
  _exsed --in-place \
    -e "s,(CELERY_BIN=\").*\",\1$celery_bin\"," \
    -e "s,(CELERYD_CHDIR=\").*\",\1$DCUBE_HOME/data_cube_ui\"," \
    -e "s,(CELERYD_USER=\").*\",\1$USER\"," \
    -e "s,(CELERYD_GROUP=\").*\",\1$GROUP\"," \
    "${CONFDIR}/upstart/celerybeat_conf"
  sudo install -vDm644 "${CONFDIR}/upstart/celerybeat_conf" /etc/default/celerybeat

  sudo mkdir -pv /var/log/celery
  sudo chown "$USER:$GROUP" /var/log/celery

  echo "[DC_CELERY-SETUP] Raising celery and celerybeat services..."
  sudo service celeryd start
  sudo service celerybeat start
}

if [[ "$INITSYS" == "systemd" ]]; then
  _systemd_celery_setup
else
  _upstart_celery_setup
fi

echo "[DC_CELERY-SETUP] Finished celery setup."
