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

echo "[DCUI-Setup] Setting up Datacube UI..."

echo "[DCUI-Setup] Creating directories for processing results..."

declare -r UIDIR="$DATA_HOME/ui_results"
mkdir -vp "$UIDIR"
mkdir -vp "${UIDIR}_temp"
mkdir -vp "$UIDIR/custom_mosaic"
mkdir -vp "$UIDIR/fractional_cover"
mkdir -vp "$UIDIR/tsm"
mkdir -vp "$UIDIR/water_detection"
mkdir -vp "$UIDIR/slip"

chmod --recursive 775 "$UIDIR"

echo "[DCUI-Setup] Cloning repository of Datacube UI..."
git clone --recurse-submodules https://github.com/ceos-seo/data_cube_ui -b master "$DCUBE_HOME/data_cube_ui"

echo "[DCUI-Setup] Patching the Datacube UI..."

pushd "$DCUBE_HOME/data_cube_ui"
declare patch="${PATCHDIR}/0001-configurable-results-directory.patch"
echo "[DCUI-Setup] Checking if patch '$patch' can be applied..."
git apply --stat "$patch"
git apply --check "$patch"
echo "[DCUI-Setup] Applying patch '$patch'..."
git apply "$patch"
echo "[DCUI-Setup] Patch '$patch' successfully applied."
popd

echo "[DCUI-Setup] Asking if patch for Django 2.0 is desired..."
patch="${PATCHDIR}/0002-django-2-migration.patch"
echo -n "Should the patch '$patch' be applied? [Y/n] "
read -r shall_patch_django
case "$shall_patch_django" in
y | Y | '')
  pushd "$DCUBE_HOME/data_cube_ui"

  echo "[DCUI-Setup] Checking if patch '$patch' can be applied..."
  git apply --stat "$patch"
  git apply --check "$patch"
  echo "[DCUI-Setup] Applying patch '$patch'..."
  git apply "$patch"
  echo "[DCUI-Setup] Patch '$patch' successfully applied."

  popd
  ;;
*)
  echo "[DCUI-Setup] Skipping application of patch for Django 2.0..."
  ;;
esac
unset shall_patch_django

echo "[DCUI-Setup] Installing required packages from distro repository..."
declare -ar PACKAGES=(
  apache2
  redis-server
  libfreeimage3
  imagemagick
  gdal-bin
)

sudo apt install --assume-yes "${PACKAGES[@]}"

echo "[DCUI-Setup] Installing required python packages into conda environment..."
declare -ar PYTHON_PACKAGES=(
  "django=2.0.8"
  redis
  imageio
  django-bootstrap3
  matplotlib
  celery
  pip
)

conda install --name "$CUBEENV" --yes "${PYTHON_PACKAGES[@]}"

_activate

# packages stringcase and mod_wsgi are not available via conda, so we fall
# back to the pip *inside* our conda environment
pip install stringcase

# install mod_wsgi into conda environment
echo "[DCUI-Setup] Installing mod_wsgi in conda environment..."
sudo apt install --assume-yes apache2-dev build-essential
pip install mod_wsgi
sudo "$(command -v mod_wsgi-express)" install-module | sed -n '/LoadModule/p' | sudo tee /etc/apache2/mods-available/wsgi.load
_exsed --in-place 's,(WSGIPythonHome ).*,\1'"$CONDA_PREFIX"',' "${CONFDIR}/wsgi.conf"
_exsed --in-place 's,(WSGIPythonPath ).*,\1'"${CONDA_PREFIX}/lib/python3.6/site-packages"',' "${CONFDIR}/wsgi.conf"
sudo install -vDm644 "${CONFDIR}/wsgi.conf" /etc/apache2/mods-available/wsgi.conf

_deactivate

echo "[DCUI-SETUP] Configuring Django..."
declare DJANGO_SETTINGS="${DCUBE_HOME}/data_cube_ui/data_cube_ui/settings.py"

# configure ADMIN_EMAIL
echo "[DCUI-SETUP-DJANGO] Configuring admin email..."
echo -n "Please enter the admin email address to use (will be used for Apache, too): "
read -r admin_email

_exsed --in-place "s/^(ADMIN_EMAIL = ).*/\1'\
$(echo -n "$admin_email" | _sedescape)\
'/" "$DJANGO_SETTINGS"

# configure LOCAL_USER
echo "[DCUI-SETUP-DJANGO] Configuring user..."
_exsed --in-place "s/^(LOCAL_USER = ).*/\1'\
$(echo -n "$USER" | _sedescape)\
'/" "$DJANGO_SETTINGS"

# configure RESULTS_DATA_DIR
echo "[DCUI-SETUP-DJANGO] Configuring results data directory..."
_exsed --in-place "s/^(RESULTS_DATA_DIR = ).*/\1'\
$(echo -n "$DATA_HOME/ui_results" | _sedescape)\
'/" "$DJANGO_SETTINGS"

# configure DATABASES (using configuration from $HOME/.datacube.conf)
echo "[DCUI-SETUP-DJANGO] Configuring database user..."
_exsed --in-place "s/^(\s*'USER': ?).*$/\1'\
$(_exsed --quiet "s/^db_username: (.*)$/\1/p" "$HOME/.datacube.conf" | _sedescape)\
',/" "$DJANGO_SETTINGS"

echo "[DCUI-SETUP-DJANGO] Configuring database password..."
_exsed --in-place "s/^(\s*'PASSWORD': ?).*$/\1'\
$(_exsed --quiet "s/^db_password: (.*)$/\1/p" "$HOME/.datacube.conf" | _sedescape)\
',/" "$DJANGO_SETTINGS"

# configure HOST for agdc database
perl -i -pe "BEGIN{undef \$/;} s/(\s+)('PASSWORD': ?'.*',?)(\n)(?!\s+'HOST': ?'.*',?\n)(\s+\},?)/\1\2\1'HOST': 'localhost',\3\4/g" "$DJANGO_SETTINGS"

# configure TIME_ZONE (using timedatectl or /etc/timezone)
echo "[DCUI-SETUP-DJANGO] Configuring timezone..."
if command -v timedatectl >/dev/null && timedatectl status > /dev/null 2>&1; then
  _exsed --in-place "s/^(TIME_ZONE = ).*/\1'\
$(timedatectl status | awk '$1 ~ /Time/ && $2 ~ /zone:/ { print $3 }' | _sedescape)\
'/" "$DJANGO_SETTINGS"
elif [[ -e "/etc/timezone" ]]; then
  _exsed --in-place "s/^(TIME_ZONE = ).*/\1'\
$(cat /etc/timezone | _sedescape)\
'/" "$DJANGO_SETTINGS"
fi

# copy database login from datacube.conf into .pgpass file
echo "*:*:*:$(_exsed --quiet "s/^db_username: (.*)$/\1/p" "$HOME/.datacube.conf"):$(_exsed --quiet "s/^db_password: (.*)$/\1/p" "$HOME/.datacube.conf" | _exsed -e 's/:/\\:/g' -e 's/\\/\\\\/g')" \
  >>"$HOME/.pgpass"
chmod 0600 "$HOME/.pgpass"

echo "[DCUI-SETUP] Checking for Postfix installation..."
echo -n "Should Postfix be installed and configured automatically? [y/N] "
read -r install_postfix
case "$install_postfix" in
y | Y)
  echo "[DCUI-SETUP] Installing Postfix..."
  # TODO: automate interactive setup of postfix
  sudo apt install --assume-yes postfix mailutils
  # TODO: is stopping the service required or would a restart suffice?
  if [[ "$INITSYS" == "systemd" ]]; then
    sudo systemctl stop postfix.service
  else
    sudo service postfix stop
  fi

  echo "[DCUI-SETUP] Configuring Postfix..."
  _backup -s /etc/postfix/main.cf
  _exsed -s --in-place 's/(inet_interfaces = ).*/\1localhost/' /etc/postfix/main.cf
  if [[ "$INITSYS" == "systemd" ]]; then
    sudo systemctl start postfix.service
  else
    sudo service postfix start
  fi
  ;;
*)
  echo "[DCUI-SETUP] Skipping installation and configuration of Postfix..."
  echo "[DCUI-SETUP] Please take a look into the README and see, what needs to be configured."
  echo "[DCUI-SETUP] Apply the configuration, reload/restart Postfix and return to this installer."
  echo -n "Continue setup? [ENTER]"
  read -r shall_continue
  unset shall_continue
  ;;
esac
unset install_postfix

echo "[DCUI-SETUP] Configuring Apache Web Server..."
echo -n "Please enter the value for ServerName (i.e. the domain name): "
read -r server_name

echo "[DCUI-SETUP] Creating VirtualHost at /etc/apache2/sites-available/dc_ui.conf..."
cat <<APACHECONF | sudo tee /etc/apache2/sites-available/dc_ui.conf
<VirtualHost *:80>
    # Admin email, Server Name (domain name) and any aliases
    ServerAdmin ${admin_email}
    ServerName ${server_name:-$HOST}

    WSGIDaemonProcess dc_ui python-path=${DCUBE_HOME}/data_cube_ui
    WSGIProcessGroup dc_ui
    WSGIApplicationGroup %{GLOBAL}

    WSGIScriptAlias / ${DCUBE_HOME}/data_cube_ui/data_cube_ui/wsgi.py

    <Directory "${DCUBE_HOME}/data_cube_ui/data_cube_ui/">
    	<Files wsgi.py>
    		Require all granted
    	</Files>
    </Directory>

    #django static
    Alias /static/ ${DCUBE_HOME}/data_cube_ui/static/
    <Directory ${DCUBE_HOME}/data_cube_ui/static>
    	Require all granted
    </Directory>

    #results.
    Alias /datacube/ ${DATA_HOME}/
    <Directory ${DATA_HOME}/>
    	Require all granted
    </Directory>

    # enable compression
    SetOutputFilter DEFLATE

    ErrorLog \${APACHE_LOG_DIR}/datacube-error.log
    CustomLog \${APACHE_LOG_DIR}/datacube-access.log combined

</VirtualHost>

# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
APACHECONF

# unset variables not used anymore
unset admin_email server_name

# deactivating default site and activating the datacube ui
sudo a2enmod wsgi
sudo a2dissite 000-default.conf
sudo a2ensite dc_ui.conf

if [[ "$INITSYS" == "systemd" ]]; then
  sudo systemctl restart apache2.service
else
  sudo service apache2 restart
fi

echo "[DCUI-Setup] Finished scripted setup."
echo "[DCUI-Setup] Although the script configured Django, there are still some"
echo "[DCUI-Setup] steps to be executed manually. Check correctness of the Django configuration"
echo "[DCUI-Setup] in '${DCUBE_HOME}/data_cube_ui/data_cube_ui/settings.py' and then"
echo "[DCUI-Setup] follow the steps outlined in https://github.com/ceos-seo/data_cube_ui/blob/master/docs/ui_install.md#database_initialization to initialize Django"
echo "[DCUI-Setup]"
echo "[DCUI-Setup] In the current setup with a conda environment, it may occur,"
echo "[DCUI-Setup] that python code run by Apache via 'mod_wsgi' has trouble to"
echo "[DCUI-Setup] see some of the libraries installed in the conda environment."
echo "[DCUI-Setup] Read the 'Known Issues' section of the README for workarounds."
