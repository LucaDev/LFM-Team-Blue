#!/usr/bin/env bash

PATH="../psbt/"
FILE="$PATH/psbt-approve.sh"

exec pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY \
  xfce4-terminal --hold --command \
  "bash -lc '$FILE; echo; read -n1 -rsp \"Taste…\"'"