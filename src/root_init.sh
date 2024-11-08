#!/bin/bash

# Docker init script
# Copyright (c) 2017 Julian Xhokaxhiu
# Copyright (C) 2017-2018 Nicola Corna <nicola@corna.info>
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

USER=$(id -nu "${UID}" 2>/dev/null)

if [ -n "${USER}" ]; then 
  echo "Executing with existing user ${USER}, UID: ${UID}"
else
  USER="lineageos"
  groupadd -g "${UID}" -o "${USER}" && \
  useradd -m -u "${UID}" -g "${UID}" -o -s /bin/bash "${USER}"; \
  echo "Executing with new user ${USER}, UID: ${UID}"
fi

chown -R "${USER}":"${USER}" /root
exec su -c /root/init.sh "${USER}"