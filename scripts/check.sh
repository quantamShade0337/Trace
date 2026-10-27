#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/verification
swift test 2>&1 | tee build/verification/tests.log
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build \
  > build/verification/build.log 2>&1
print 'Release build passed. Build log: build/verification/build.log'
