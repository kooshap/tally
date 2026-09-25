#!/bin/sh
# Xcode Cloud runs this right after cloning. Tally.xcodeproj is generated and
# gitignored; project.yml is the source, so build it here the way ci.yml does,
# with the XcodeGen version pinned in BuildTools/.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"
BuildTools/tool xcodegen generate
