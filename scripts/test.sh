#!/usr/bin/env sh
# Run the test suite. Neovim is the interpreter, so specs get the real vim API.
set -e
cd "$(dirname "$0")/.."
exec nvim -l spec/run.lua "$@"
