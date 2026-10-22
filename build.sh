#!/bin/bash
# Jena icon: compile + render with Apple's own tools (Xcode 26 ictool + actool + iOS Simulator).
set -u
tmo(){ perl -e 'alarm shift; exec @ARGV' "$@"; }
OUT="$PWD/out"; mkdir -p "$OUT/ictool" "$OUT/actool" "$OUT/sim"
LOG="$OUT/log.txt"; exec >"$LOG" 2>&1
python3 -m pip install -q --break-system-packages huggingface_hub >/dev/null 2>&1 || python3 -m pip install -q huggingface_hub >/dev/null 2>&1
python3 -c "
import os; from huggingface_hub import snapshot_download
snapshot_download('Saidie000/jena-icon-build',repo_type='dataset',allow_patterns=['src/*','src/**'],local_dir='hf',token=os.environ['HF_TOKEN'])"
rm -rf Jena.icon; cp -R hf/src/Jena.icon ./Jena.icon; ls -R Jena.icon
echo "== machine"; sw_vers; uname -m
echo "== xcodes"; ls -d /Applications/Xcode*.app
XC=$(ls -d /Applications/Xcode_27*.app 2>/dev/null | grep -v -i beta | sort -V | tail -1); [ -z "$XC" ] && XC=$(ls -d /Applications/Xcode_26*.app 2>/dev/null | sort -V | tail -1)
[ -z "$XC" ] && XC=$(xcode-select -p | sed 's#/Contents/Developer##')
echo "using $XC"; sudo xcode-select -s "$XC"; xcodebuild -version
IC=$(find "$XC/Contents/Applications" -name ictool -type f 2>/dev/null | head -1)
echo "ictool=$IC"
"$IC" --help > "$OUT/ictool/help.txt" 2>&1; "$IC" -h >> "$OUT/ictool/help.txt" 2>&1; cat "$OUT/ictool/help.txt" | head -80
echo "== ictool renders"
for P in iOS; do
 for R in Default Dark ClearLight ClearDark TintedLight TintedDark; do
  for SZ in 1024; do
   F="$OUT/ictool/Jena-$P-$R-$SZ.png"
   tmo 120 "$IC" Jena.icon --export-image --output-file "$F" --platform "$P" --rendition "$R" --width $SZ --height $SZ --scale 1 >"$OUT/ictool/$R.err" 2>&1
   if [ -s "$F" ]; then echo "OK $R"; rm -f "$OUT/ictool/$R.err"; else echo "FAIL $R: $(head -c 300 "$OUT/ictool/$R.err")"; fi
  done
 done
done
# pink-tinted variants (tint hue/strength are ictool options)
for R in TintedLight TintedDark; do tmo 120 "$IC" Jena.icon --export-image --output-file "$OUT/ictool/Jena-iOS-$R-pink-1024.png" --platform iOS --rendition $R --width 1024 --height 1024 --scale 1 --tint-color 0.93 --tint-strength 0.75 >>"$OUT/ictool/tint.err" 2>&1 && echo "OK $R pink"; done
"$IC" --version
# small sizes of Default to show legibility
for SZ in 180 120 87 58; do tmo 120 "$IC" Jena.icon --export-image --output-file "$OUT/ictool/Jena-iOS-Default-$SZ.png" --platform iOS --rendition Default --width $SZ --height $SZ --scale 1 >/dev/null 2>&1; done
echo "== actool compile"
mkdir -p build/Jena.app
tmo 300 xcrun actool Jena.icon --compile "$OUT/actool" --output-format human-readable-text --notices --warnings --errors \
  --output-partial-info-plist "$OUT/actool/partial.plist" --app-icon Jena --include-all-app-icons \
  --enable-on-demand-resources NO --development-region en --target-device iphone --minimum-deployment-target 18.0 --platform iphonesimulator
echo "actool exit $?"; ls -la "$OUT/actool"
xcrun --sdk iphonesimulator assetutil --info "$OUT/actool/Assets.car" > "$OUT/actool/assetutil-info.json" 2>&1 || true
head -c 3000 "$OUT/actool/assetutil-info.json"
echo "== simulator app"
cp "$OUT/actool/Assets.car" build/Jena.app/ 2>/dev/null; cp "$OUT"/actool/*.png build/Jena.app/ 2>/dev/null
ARCH=$(uname -m)
SDKV=$(xcrun --sdk iphonesimulator --show-sdk-version); echo "sim sdk $SDKV"
xcrun --sdk iphonesimulator swiftc -parse-as-library -target $ARCH-apple-ios18.0-simulator app/main.swift -o build/Jena.app/Jena && echo "swiftc ok"
/usr/libexec/PlistBuddy -c "Clear dict" build/Jena.app/Info.plist >/dev/null 2>&1 || true
cat > build/Jena.app/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ncom.jena</string><key>CFBundleExecutable</key><string>Jena</string>
<key>CFBundleName</key><string>Jena</string><key>CFBundleDisplayName</key><string>Jena</string>
<key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.0</string><key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconName</key><string>Jena</string><key>MinimumOSVersion</key><string>18.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
<key>UIDeviceFamily</key><array><integer>1</integer></array><key>UILaunchScreen</key><dict/>
<key>LSRequiresIPhoneOS</key><true/>
</dict></plist>
PL
[ -f "$OUT/actool/partial.plist" ] && /usr/libexec/PlistBuddy -c "Merge $OUT/actool/partial.plist" build/Jena.app/Info.plist
plutil -p build/Jena.app/Info.plist
codesign -s - --force build/Jena.app && echo "signed"
DEV=$(xcrun simctl list devices available -j | python3 -c "
import json,sys,re
d=json.load(sys.stdin)['devices']
c=[(k,x) for k,v in d.items() if re.search(r'iOS-2[6-9]',k) for x in v if x['name'].startswith('iPhone') and 'Pro' in x['name'] and 'Max' not in x['name']]
c=c or [(k,x) for k,v in d.items() if re.search(r'iOS-2[6-9]',k) for x in v if x['name'].startswith('iPhone')]
c.sort(key=lambda t:[int(v) for v in re.findall(r'\d+',t[0])]); print(c[-1][1]['udid'] if c else '')")
echo "device $DEV"; xcrun simctl list devices available | grep -i iphone | head -5
if [ -n "$DEV" ]; then
  xcrun simctl boot "$DEV"; xcrun simctl bootstatus "$DEV" -b
  xcrun simctl ui "$DEV" appearance light
  sleep 25
  xcrun simctl io "$DEV" screenshot "$OUT/sim/home-before.png"
  xcrun simctl install "$DEV" build/Jena.app && echo "installed"
  sleep 15
  xcrun simctl io "$DEV" screenshot "$OUT/sim/home-light.png"
  xcrun simctl ui "$DEV" appearance dark; sleep 12
  xcrun simctl io "$DEV" screenshot "$OUT/sim/home-dark.png"
  xcrun simctl ui "$DEV" appearance light
  xcrun simctl shutdown "$DEV"
fi
echo "== done"; find "$OUT" -type f | sort
