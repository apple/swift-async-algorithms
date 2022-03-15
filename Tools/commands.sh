#!/bin/sh

if [[ -z "${TOOLCHAINS}" ]]; then
    SWIFT_PATH="$(xcrun -f swift)"
    LLVM_COV_PATH="$(xcrun -f llvm-cov)"
else
    SWIFT_PATH="$(xcrun --toolchain ${TOOLCHAINS} -f swift)"
    LLVM_COV_PATH="$(xcrun --toolchain ${TOOLCHAINS} -f llvm-cov)"
    SWIFT_BIN_DIR="$(dirname ${SWIFT_PATH})"
    export DYLD_LIBRARY_PATH="${SWIFT_BIN_DIR}/../lib/swift/macosx/"
fi

BIN_PATH="$(${SWIFT_PATH} build --show-bin-path)"
XCTEST_BUNDLE_PATH="$(find ${BIN_PATH} -name '*.xctest')"

TEST_PACKAGE="$(basename $XCTEST_BUNDLE_PATH .xctest)"
COV_BIN="$XCTEST_BUNDLE_PATH/Contents/MacOS/$TEST_PACKAGE"