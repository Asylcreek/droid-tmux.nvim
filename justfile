set shell := ["sh", "-cu"]

default:
  @just --list

lint:
  stylua --check .
  luacheck lua plugin

test:
  nvim --headless -u NONE -i NONE \
    '+set rtp+=$PWD' \
    '+lua require("tests.run").run()' \
    '+qa'

check: lint test

fix:
  stylua .
