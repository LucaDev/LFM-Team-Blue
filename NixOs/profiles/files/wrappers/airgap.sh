#!/usr/bin/env bash

PATH="../setup/"
FILE="$PATH/airgap.sh"

exec pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY \
  xfce4-terminal --hold --command \
  "bash -lc '$FILE; echo; read -n1 -rsp \"Taste…\"'"