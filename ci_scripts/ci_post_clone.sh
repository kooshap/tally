#!/bin/sh
# Xcode Cloud runs this right after cloning. Tally.xcodeproj is generated and
# gitignored; project.yml is the source, so build it here the way ci.yml does.
set -eu

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
