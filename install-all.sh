#!/bin/bash

set -e
set -o pipefail

if [ ! -d ~/.mason ]; then
    git clone --depth=1 https://github.com/mapbox/mason.git ~/.mason
    alias mason='~/.mason/mason'
fi

rm -rf test-all
git clone --quiet https://github.com/mapbox/mason.git test-all
cd test-all
for b in $(git for-each-ref --sort=-committerdate refs/remotes --format='%(refname:short)'); do
    git checkout --quiet $b
    if [ -f ./script.sh ]; then
        echo $b
        ./script.sh install
    fi
done
