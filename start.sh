#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
g++ -std=c++17 -Wall -Wextra -Werror -O2 server.cpp -o bst-server
./bst-server &
bst_pid=$!
trap 'kill "$bst_pid" 2>/dev/null || true' EXIT
python3 bridge.py
