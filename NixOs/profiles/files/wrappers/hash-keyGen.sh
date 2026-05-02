#!/usr/bin/env bash

PATH="../auth/"
FILE="$PATH/hash-keyGen.sh"

exec pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY \
  xfce4-terminal --hold --command \
  "bash -lc '$FILE; echo; read -n1 -rsp \"Taste…\"'"
