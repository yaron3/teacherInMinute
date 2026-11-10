#!/bin/sh
#
# Keeps the Android build working when Xcode's Swift is newer than the Swift
# toolchain the Android build uses.
#
# Skip builds the Swift code for Android with the toolchain that matches the
# installed Swift Android SDK (for example swift-6.3.1-RELEASE.xctoolchain).
# SwiftPM compiles every package's Package.swift for the Mac first, against the
# macOS SDK of the selected Xcode. When Xcode ships a newer Swift than that
# toolchain, the SDK's Swift modules can use compiler flags the older toolchain
# does not know. Xcode 27.2 (Swift 6.4) did exactly that: the swift 6.3.1
# toolchain crashes on every manifest that imports Foundation with
#
#     unknown argument: '-target-arch-variant'
#
# SwiftPM reads SDKROOT, but Skip starts SwiftPM with a clean environment, so
# SDKROOT cannot simply be exported. Skip does let SWIFT_TOOLCHAIN_DIR name the
# folder it looks for toolchains in. This script builds that folder:
#
#   ~/Library/Developer/Toolchains-SkipShim/
#     swift-<v>-RELEASE.xctoolchain   the real toolchain, except that its
#                                     `swift` first sets SDKROOT to the newest
#                                     macOS SDK the toolchain can read
#     <every other toolchain>         linked as is
#
# The "Run skip gradle" build phase runs this and, if the folder exists, points
# SWIFT_TOOLCHAIN_DIR at it. When every installed macOS SDK is readable again
# (a newer Swift Android SDK, or an older Xcode), the folder is removed and the
# build goes back to the plain toolchains.
#
# Usage: android-toolchain-shim.sh [--quiet]   build or refresh the folder
#        android-toolchain-shim.sh --remove    delete it
#
# For a Gradle build run by hand:
#   SWIFT_TOOLCHAIN_DIR=~/Library/Developer/Toolchains-SkipShim ./gradlew …

set -eu

SHIM_DIR="${HOME}/Library/Developer/Toolchains-SkipShim"
TOOLCHAINS_DIR="${HOME}/Library/Developer/Toolchains"
SWIFT_SDKS_DIR="${HOME}/Library/org.swift.swiftpm/swift-sdks"
FLAG="target-arch-variant"
QUIET=""

note() { [ -n "${QUIET}" ] || echo "note: $*"; }

case "${1:-}" in
  --remove) rm -rf "${SHIM_DIR}" "${HOME}/Library/Developer/.skip-toolchain-shim-stamp"; note "removed ${SHIM_DIR}"; exit 0 ;;
  --quiet) QUIET=1 ;;
esac

# An SDK the old toolchain can read has no Swift module using the new flag.
sdk_is_readable() {
  ! grep -rqs -- "-${FLAG}" "$1/usr/lib/swift" 2>/dev/null
}

XCODE_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
[ -n "${XCODE_SDK}" ] || exit 0

# Nothing to do when neither Xcode, the SDKs, the toolchains nor the Swift SDKs
# changed since the last check. Kept outside SHIM_DIR so it also covers "no
# shim needed", and checked first: the scans below read every Swift module of
# each SDK they try, which costs seconds on every build.
STAMP="${HOME}/Library/Developer/.skip-toolchain-shim-stamp"
WANT="${XCODE_SDK}|$(ls -d "$(dirname "${XCODE_SDK}")"/MacOSX*.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | tr '\n' ' ')|$(ls "${TOOLCHAINS_DIR}" 2>/dev/null | tr '\n' ' ')|$(ls "${SWIFT_SDKS_DIR}" 2>/dev/null | tr '\n' ' ')"
if [ -f "${STAMP}" ] && [ "$(cat "${STAMP}")" = "${WANT}" ]; then
  exit 0
fi

if sdk_is_readable "${XCODE_SDK}"; then
  if [ -d "${SHIM_DIR}" ]; then
    rm -rf "${SHIM_DIR}"
    note "the macOS SDK is readable again; removed ${SHIM_DIR}"
  fi
  echo "${WANT}" > "${STAMP}"
  exit 0
fi

# Newest macOS SDK without the flag, from Xcode and the Command Line Tools.
HOST_SDK=""
for sdk in $(ls -d \
    "$(dirname "${XCODE_SDK}")"/MacOSX[0-9]*.sdk \
    /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk 2>/dev/null \
    | awk -F/ '{ v=$NF; sub(/^MacOSX/, "", v); sub(/\.sdk$/, "", v); print v "\t" $0 }' \
    | sort -t. -k1,1nr -k2,2nr | cut -f2); do
  if sdk_is_readable "${sdk}"; then HOST_SDK="${sdk}"; break; fi
done
if [ -z "${HOST_SDK}" ]; then
  echo "warning: no installed macOS SDK can be read by the Android Swift toolchain;" \
       "install a Swift Android SDK matching Xcode's Swift (skip android sdk install)" >&2
  exit 0
fi

rm -rf "${SHIM_DIR}"
mkdir -p "${SHIM_DIR}"

# Toolchains an installed Swift Android SDK asks for, e.g. swift-6.3.1-RELEASE.
NEEDED="$(ls "${SWIFT_SDKS_DIR}" 2>/dev/null | sed -n 's/^\(swift-.*-RELEASE\)_android.*/\1/p' | sort -u)"

for real in "${TOOLCHAINS_DIR}"/*.xctoolchain; do
  [ -e "${real}" ] || continue
  name="$(basename "${real}" .xctoolchain)"
  if ! echo "${NEEDED}" | grep -qx "${name}"; then
    ln -s "${real}" "${SHIM_DIR}/"
    continue
  fi
  real="$(cd "${real}" && pwd -P)"
  shim="${SHIM_DIR}/${name}.xctoolchain"
  mkdir -p "${shim}/usr/bin"
  for entry in "${real}"/*; do
    [ "$(basename "${entry}")" = usr ] || ln -s "${entry}" "${shim}/"
  done
  for entry in "${real}"/usr/*; do
    [ "$(basename "${entry}")" = bin ] || ln -s "${entry}" "${shim}/usr/"
  done
  for entry in "${real}"/usr/bin/*; do
    [ "$(basename "${entry}")" = swift ] || ln -s "${entry}" "${shim}/usr/bin/"
  done
  cat > "${shim}/usr/bin/swift" <<EOF
#!/bin/sh
# Written by teacher-minute/scripts/android-toolchain-shim.sh: compile package
# manifests against a macOS SDK this toolchain can read.
export SDKROOT="${HOST_SDK}"
exec "${real}/usr/bin/swift" "\$@"
EOF
  chmod +x "${shim}/usr/bin/swift"
  note "${name}: manifests compile against $(basename "${HOST_SDK}")"
done

echo "${WANT}" > "${STAMP}"
