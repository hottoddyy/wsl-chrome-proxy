#!/bin/sh
set -eu

port="${1:-18081}"
script="${2:?proxy script path required}"
state_dir="/tmp/wsl-chrome-proxy"

mkdir -p "$state_dir"

if ss -ltn | grep -q ":$port "; then
  exit 0
fi

nohup python3 "$script" --host 0.0.0.0 --port "$port" > "$state_dir/proxy.log" 2>&1 &
sleep 0.2
