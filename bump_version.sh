#!/bin/bash

if [ $# -ne 1 ]; then
    echo "usage: $0 new_version_string"
    exit 1
fi

new_version=$1
echo "Bumping to new version -> $new_version"

sed -ie 's/^## Version: .*/## Version: '$new_version'/' PetesDefensiveHistory.toc

sed -ie 's/ns.ADDON_VERSION = .*/ns.ADDON_VERSION = \"'$new_version'\"/' Globals.lua
