#!/usr/bin/env bash

set -e

export GOPATH=$(pwd)

go build -v flapjack
