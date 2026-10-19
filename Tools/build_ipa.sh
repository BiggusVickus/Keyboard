#!/bin/sh
# Builds Taalhulp.ipa for the Windows auto-refresh (Tools/windows/).
# Run on the Mac after code changes:  sh Tools/build_ipa.sh
# Then copy build/Taalhulp.ipa to the Windows PC and run Setup-AutoRefresh.ps1 -UpdateIpaOnly.
#
# The build is signed normally by Xcode (your Apple ID from Xcode → Settings → Accounts), so the
# app and keyboard keep their App Group entitlement; Windows re-signs it every week.
set -eu
cd "$(dirname "$0")/.."

xcodegen
xcodebuild \
    -project Taalhulp.xcodeproj \
    -scheme Taalhulp \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath build/DerivedData \
    -allowProvisioningUpdates \
    -quiet \
    build

APP=build/DerivedData/Build/Products/Release-iphoneos/Taalhulp.app
rm -rf build/ipa build/Taalhulp.ipa
mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry ../Taalhulp.ipa Payload)
rm -rf build/ipa
echo "Built build/Taalhulp.ipa"
