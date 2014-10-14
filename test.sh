#!/usr/bin/env bash

set -e -u
set -o pipefail

. init
mason ls
mason install bzip