#!/bin/bash
# Builds Lazy Scan in release mode and packages dist/Lazy Scan.app
set -euo pipefail
cd "$(dirname "$0")/.."

# --ship builds only the live, complete languages.
[ $# -eq 0 ] || { [ $# -eq 1 ] && [ "$1" = "--ship" ]; } || { echo "usage: $0 [--ship]" >&2; exit 1; }

echo "==> Generating strings…"
python3 scripts/gen_l10n.py ${1:+"$1"}

echo "==> Building (release)…"
swift build -c release

APP="dist/Lazy Scan.app"
BIN=".build/release/LazyScan"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/LazyScan"

LANGS=$(cat l10n/out/languages.mac.txt)

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key> <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>@LANGS@</array>
    <key>CFBundleName</key>              <string>Lazy Scan</string>
    <key>CFBundleDisplayName</key>       <string>Lazy Scan</string>
    <key>CFBundleIdentifier</key>        <string>local.lazyscan.app</string>
    <key>CFBundleExecutable</key>        <string>LazyScan</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSApplicationSupportsSecureRestorableState</key> <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Lazy Scan looks for scanners on your local network, such as printers that scan, so you can scan from them, and receives documents from your paired phone.</string>
    <key>NSBonjourServices</key>
    <array><string>_lazyscan._tcp</string></array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>      <string>Lazy Scan document</string>
            <key>CFBundleTypeRole</key>      <string>Viewer</string>
            <key>LSHandlerRank</key>         <string>Owner</string>
            <key>LSItemContentTypes</key>    <array><string>com.lazyscan.package</string></array>
        </dict>
    </array>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>       <string>local.lazyscan.app</string>
            <key>CFBundleURLSchemes</key>    <array><string>lazyscan</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>      <string>com.lazyscan.package</string>
            <key>UTTypeDescription</key>     <string>Lazy Scan document</string>
            <key>UTTypeConformsTo</key>      <array><string>public.data</string><string>public.archive</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key> <array><string>lsdoc</string></array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST
sed -i.bak "s|@LANGS@|$(for lang in $LANGS; do printf '<string>%s</string>' "$lang"; done)|" "$APP/Contents/Info.plist"
rm "$APP/Contents/Info.plist.bak"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Kit.strings, InfoPlist.strings and Localizable.strings come from scripts/gen_l10n.py.
# macOS only picks a language when the bundle has its lproj, so a missing one stops the build.
for lang in $LANGS; do
  [ -d "l10n/out/mac/$lang.lproj" ] || { echo "$lang.lproj is missing from l10n/out/mac" >&2; exit 1; }
  cp -R "l10n/out/mac/$lang.lproj" "$APP/Contents/Resources/"
done

# The page corner model and its licence, where FastViTCornerModel looks in a packaged app. Without it
# (scripts/fetch_docaligner.sh not run) the app finds pages with its own search. ONNX Runtime is linked
# in either way, so its licence always goes in.
MODELS=Sources/LazyScanModel/Models
cp "$MODELS/ONNXRuntime-LICENSE.txt" "$MODELS/ONNXRuntime-THIRD-PARTY-NOTICES.txt" "$APP/Contents/Resources/"
cp THIRD-PARTY-NOTICES.txt "$APP/Contents/Resources/"
if [ -f "$MODELS/fastvit_t8_h_e_bifpn_256_fp32.onnx" ]; then
  cp "$MODELS/fastvit_t8_h_e_bifpn_256_fp32.onnx" "$MODELS/DocAligner-LICENSE.txt" "$APP/Contents/Resources/"
else
  echo "    No corner model fetched; the app will use its own page search."
fi

# App icon (optional — skipped if generation fails)
if [ ! -f dist/icon_1024.png ] || [ scripts/MakeIcon.swift -nt dist/icon_1024.png ]; then
  mkdir -p dist
  swift scripts/MakeIcon.swift dist/icon_1024.png || true
fi
if [ -f dist/icon_1024.png ]; then
  echo "==> Building icon…"
  ICONSET=dist/AppIcon.iconset
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s dist/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s*2))
    sips -z $d $d dist/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" && rm -rf "$ICONSET"
fi

echo "==> Signing (ad-hoc)…"
codesign --force --deep -s - "$APP"

echo "==> Done: $APP"
echo "    Launch with:  open \"$APP\""
