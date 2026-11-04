#!/bin/bash
# Run on macOS with Xcode: bash mobile_game/tools/build_ios.sh
# Produces a real arm64 device app; intentionally does not sign or upload it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${IOS_OUTPUT_DIR:-$PROJECT_DIR/builds/ios}"
TOOL_CACHE="${IOS_TOOL_CACHE:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/starlantern-godot-4.7.2}"
GODOT_TAG="4.7.2-stable"
GODOT_TEMPLATE_VERSION="4.7.2.stable"
RELEASE_BASE="https://github.com/godotengine/godot-builds/releases/download/$GODOT_TAG"
EDITOR_NAME="Godot_v4.7.2-stable_macos.universal.zip"
EDITOR_SHA256="c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e"
TEMPLATES_NAME="Godot_v4.7.2-stable_export_templates.tpz"
TEMPLATES_SHA256="f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
PRESET="iOS"
PRODUCT_NAME="StarLanternIsland"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ "$(uname -s)" = "Darwin" ] || die "iOS compilation requires macOS and Xcode. Windows can only prepare the Xcode project."
for command_name in curl ditto python3 shasum xcodebuild xcrun plutil codesign; do
  command -v "$command_name" >/dev/null 2>&1 || die "Missing tool: $command_name"
done

mkdir -p "$OUTPUT_DIR/logs" "$TOOL_CACHE"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
TOOL_CACHE="$(cd "$TOOL_CACHE" && pwd)"
LOG_DIR="$OUTPUT_DIR/logs"
# Unique directories make reruns safe without deleting arbitrary existing paths.
WORK_DIR="$(mktemp -d "$OUTPUT_DIR/work.XXXXXX")"
XCODE_DIR="$WORK_DIR/Xcode"
PROJECT_PATH="$XCODE_DIR/$PRODUCT_NAME.xcodeproj"
DERIVED_DATA="$WORK_DIR/DerivedData"
mkdir -p "$XCODE_DIR"

if [ -z "${DEVELOPER_DIR:-}" ]; then
  for xcode_app in /Applications/Xcode_26.3.app /Applications/Xcode_26.2.app /Applications/Xcode_26.1.1.app /Applications/Xcode.app; do
    if [ -d "$xcode_app/Contents/Developer" ]; then
      export DEVELOPER_DIR="$xcode_app/Contents/Developer"
      break
    fi
  done
fi
xcodebuild -version | tee "$LOG_DIR/xcode-version.txt"
xcrun --sdk iphoneos --show-sdk-version | tee "$LOG_DIR/iphoneos-sdk-version.txt"

# The checksums are pinned to the official 4.7.2 release assets, not a mirror.
download_verified() {
  local asset_name="$1" expected_hash="$2" destination="$TOOL_CACHE/$1"
  local actual_hash=""
  if [ -f "$destination" ]; then
    actual_hash="$(shasum -a 256 "$destination" | awk '{print $1}')"
  fi
  if [ "$actual_hash" != "$expected_hash" ]; then
    curl --fail --location --retry 3 --retry-delay 3 "$RELEASE_BASE/$asset_name" --output "$destination.part"
    actual_hash="$(shasum -a 256 "$destination.part" | awk '{print $1}')"
    [ "$actual_hash" = "$expected_hash" ] || die "SHA256 mismatch for $asset_name: $actual_hash"
    mv "$destination.part" "$destination"
  fi
  printf '%s  %s\n' "$expected_hash" "$asset_name"
}
download_verified "$EDITOR_NAME" "$EDITOR_SHA256" | tee "$LOG_DIR/editor-download.txt"
download_verified "$TEMPLATES_NAME" "$TEMPLATES_SHA256" | tee "$LOG_DIR/templates-download.txt"

EDITOR_DIR="$TOOL_CACHE/editor"
mkdir -p "$EDITOR_DIR"
ditto -x -k "$TOOL_CACHE/$EDITOR_NAME" "$EDITOR_DIR"
GODOT="$EDITOR_DIR/Godot.app/Contents/MacOS/Godot"
[ -f "$GODOT" ] || die "Godot.app is missing from the official editor archive."
chmod +x "$GODOT"
"$GODOT" --headless --audio-driver Dummy --version | tee "$LOG_DIR/godot-version.txt"
grep -q '^4\.7\.2\.stable' "$LOG_DIR/godot-version.txt" || die "Wrong Godot editor version."

TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/$GODOT_TEMPLATE_VERSION"
mkdir -p "$TEMPLATE_DIR"
# Install the iOS template plus any separately packaged ICU data needed by Chinese
# text. Other platform templates are unnecessary for this job.
python3 - "$TOOL_CACHE/$TEMPLATES_NAME" "$TEMPLATE_DIR" <<'PY'
import pathlib, shutil, sys, zipfile
archive, destination = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
with zipfile.ZipFile(archive) as package:
    selected = [item for item in package.infolist() if not item.is_dir() and
                (pathlib.PurePosixPath(item.filename).name in ('ios.zip', 'version.txt') or
                 ('icu' in pathlib.PurePosixPath(item.filename).name.lower() and item.filename.endswith('.dat')))]
    ios_items = [item for item in selected if pathlib.PurePosixPath(item.filename).name == 'ios.zip']
    if len(ios_items) != 1:
        raise SystemExit('Expected exactly one ios.zip in the official export templates.')
    for item in selected:
        target = destination / pathlib.PurePosixPath(item.filename).name
        with package.open(item) as source, target.open('wb') as output:
            shutil.copyfileobj(source, output)
        print('Installed:', target.name, item.file_size)
PY

# Fail early if a future preset edit accidentally requests signing or uses the
# descriptive project version (1.2.1-hud-layout-fix) as an Apple numeric version.
python3 - "$PROJECT_DIR/export_presets.cfg" "$PRESET" <<'PY'
import configparser, re, sys
config = configparser.ConfigParser(interpolation=None, strict=False)
config.read(sys.argv[1], encoding='utf-8-sig')
def value(section, key, default=''):
    return config.get(section, key, fallback=default).strip().strip('"')
presets = [s for s in config.sections() if not s.endswith('.options') and
           value(s, 'name') == sys.argv[2] and value(s, 'platform') == 'iOS']
if len(presets) != 1:
    raise SystemExit('Exactly one iOS export preset named iOS is required.')
options = presets[0] + '.options'
assert value(options, 'application/export_project_only') == 'true', 'Use project-only iOS export.'
team = value(options, 'application/app_store_team_id')
assert re.fullmatch(r'[A-Z0-9]{10}', team), 'Team ID must contain 10 characters; unsigned placeholder is 0000000000.'
assert re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', value(options, 'application/bundle_identifier')), 'Missing bundle identifier.'
assert re.fullmatch(r'\d+\.\d+\.\d+', value(options, 'application/short_version')), 'Set numeric short_version explicitly.'
assert re.fullmatch(r'\d+(?:\.\d+){0,2}', value(options, 'application/version')), 'Set numeric build version explicitly.'
assert value(options, 'architectures/arm64', 'true') == 'true', 'Device arm64 must be enabled.'
print('Validated unsigned project-only iOS preset. Team field is not used to sign this build.')
PY

"$GODOT" --headless --audio-driver Dummy --editor --path "$PROJECT_DIR" --import 2>&1 | tee "$LOG_DIR/godot-import.log"
"$GODOT" --headless --audio-driver Dummy --path "$PROJECT_DIR" --export-release "$PRESET" "$PROJECT_PATH" 2>&1 | tee "$LOG_DIR/godot-export.log"
[ -s "$PROJECT_PATH/project.pbxproj" ] || die "Godot did not generate an Xcode project."
find "$XCODE_DIR" -type f -name '*.pck' -size +0c | grep -q . || die "Exported project has no game PCK."
find "$XCODE_DIR" -type d -name '*.xcframework' | grep -q . || die "Exported project has no Godot XCFramework."

# The 4.7.2 template can retain a stale target UUID in its shared scheme. Resolve
# the generated native target rather than hard-coding either template UUID.
python3 - "$PROJECT_PATH" <<'PY'
import pathlib, re, sys, xml.etree.ElementTree as ET
project = pathlib.Path(sys.argv[1])
pbx = (project / 'project.pbxproj').read_text(encoding='utf-8-sig')
native_targets = re.findall(
    r'(?m)^\s*([A-Fa-f0-9]{24})\s*(?:/\*[^\n]*?\*/\s*)?=\s*\{\s*isa\s*=\s*PBXNativeTarget\s*;', pbx)
if len(native_targets) != 1:
    raise SystemExit('Expected one PBXNativeTarget; refusing ambiguous scheme repair: ' + repr(native_targets))
target_id = native_targets[0]
schemes = sorted((project / 'xcshareddata' / 'xcschemes').glob('*.xcscheme'))
if not schemes:
    raise SystemExit('The exported Xcode project has no shared scheme.')
total = repaired = 0
for scheme in schemes:
    tree = ET.parse(scheme)
    references = tree.findall('.//BuildableReference')
    if not references:
        raise SystemExit('Shared scheme has no buildable references: ' + str(scheme))
    changed = False
    for reference in references:
        if reference.get('ReferencedContainer') != 'container:' + project.name:
            raise SystemExit('Unexpected external project in shared scheme: ' + str(scheme))
        total += 1
        if reference.get('BlueprintIdentifier') != target_id:
            reference.set('BlueprintIdentifier', target_id)
            changed = True
            repaired += 1
    if changed:
        ET.indent(tree, space='   ')
        tree.write(scheme, encoding='utf-8', xml_declaration=True)
        with scheme.open('ab') as output:
            output.write(b'\n')
    if any(r.get('BlueprintIdentifier') != target_id for r in ET.parse(scheme).findall('.//BuildableReference')):
        raise SystemExit('Shared scheme target validation failed: ' + str(scheme))
print('Shared schemes validated:', total, 'references,', repaired, 'repaired; native target', target_id)
PY

cat > "$XCODE_DIR/README-UNSIGNED.txt" <<'TEXT'
StarLanternIsland iOS Xcode project — unsigned
Open StarLanternIsland.xcodeproj on a Mac with Xcode.
The team 0000000000 is only a placeholder, not an Apple signing identity.
For device installation, select your own Team, a matching Bundle Identifier,
and a valid development/distribution certificate and provisioning profile.
The accompanying unsigned IPA cannot be installed directly on an ordinary iPhone.
TEXT
# Save the complete export, including sibling resources and framework libraries,
# before xcodebuild so it remains available even when native compilation fails.
ditto -c -k --keepParent "$XCODE_DIR" "$OUTPUT_DIR/$PRODUCT_NAME-iOS-Xcode.zip"

xcodebuild -list -json -project "$PROJECT_PATH" > "$LOG_DIR/xcode-project.json"
SCHEME="${IOS_SCHEME:-$(python3 - "$LOG_DIR/xcode-project.json" "$PRODUCT_NAME" <<'PY'
import json, sys
project = json.load(open(sys.argv[1], encoding='utf-8'))
schemes = project.get('project', {}).get('schemes', [])
if sys.argv[2] in schemes:
    print(sys.argv[2])
elif len(schemes) == 1:
    print(schemes[0])
else:
    raise SystemExit('Cannot choose an Xcode scheme; set IOS_SCHEME explicitly: ' + repr(schemes))
PY
)}"
printf 'Building scheme: %s\n' "$SCHEME"
xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER= PROVISIONING_PROFILE= \
  build 2>&1 | tee "$LOG_DIR/xcode-build.log"

APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/$PRODUCT_NAME.app"
[ -d "$APP_PATH" ] || die "Compiled iPhoneOS app not found: $APP_PATH"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP_PATH/Info.plist")"
[ -s "$APP_PATH/$EXECUTABLE" ] || die "The compiled app has no executable."
xcrun lipo -archs "$APP_PATH/$EXECUTABLE" | tee "$LOG_DIR/app-architectures.txt"
grep -qw arm64 "$LOG_DIR/app-architectures.txt" || die "The app is not an arm64 device build."
/usr/libexec/PlistBuddy -c 'Print DTPlatformName' "$APP_PATH/Info.plist" | tee "$LOG_DIR/app-platform.txt"
grep -qx iphoneos "$LOG_DIR/app-platform.txt" || die "The app is not built for physical iOS devices."
find "$APP_PATH" -type f -name '*.pck' -size +0c | grep -q . || die "The compiled app is missing game data."
if codesign --display --verbose=2 "$APP_PATH" > "$LOG_DIR/app-signature.txt" 2>&1; then
  die "App unexpectedly has a code signature; this workflow must produce an explicitly unsigned artifact."
fi

PAYLOAD_PARENT="$WORK_DIR/package"
mkdir -p "$PAYLOAD_PARENT/Payload"
ditto "$APP_PATH" "$PAYLOAD_PARENT/Payload/$PRODUCT_NAME.app"
ditto -c -k --keepParent "$PAYLOAD_PARENT/Payload" "$OUTPUT_DIR/$PRODUCT_NAME-unsigned.ipa"
python3 - "$OUTPUT_DIR/$PRODUCT_NAME-unsigned.ipa" "$PRODUCT_NAME" "$EXECUTABLE" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as package:
    base = 'Payload/' + sys.argv[2] + '.app/'
    assert package.getinfo(base + 'Info.plist').file_size > 0
    assert package.getinfo(base + sys.argv[3]).file_size > 0
    assert any(i.filename.startswith(base) and i.filename.endswith('.pck') and i.file_size > 0 for i in package.infolist())
    assert not any(i.filename.startswith(base + '_CodeSignature/') for i in package.infolist()), 'Unexpected signing resources.'
print('Validated IPA: real device executable, Info.plist and game PCK under Payload/.')
PY

cp "$XCODE_DIR/README-UNSIGNED.txt" "$OUTPUT_DIR/README-UNSIGNED.txt"
python3 - "$OUTPUT_DIR" "$GODOT_TAG" "$EDITOR_SHA256" "$TEMPLATES_SHA256" "$LOG_DIR" <<'PY'
import datetime, json, os, pathlib, sys
out, version, editor_hash, templates_hash, logs = sys.argv[1:]
logs = pathlib.Path(logs)
def log(name):
    return (logs / name).read_text(encoding='utf-8').strip()
info = {
    'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'commit': os.environ.get('GITHUB_SHA', 'local-build'),
    'github_run_url': ('https://github.com/' + os.environ['GITHUB_REPOSITORY'] + '/actions/runs/' + os.environ['GITHUB_RUN_ID']) if 'GITHUB_RUN_ID' in os.environ else None,
    'godot_release': version, 'editor_sha256': editor_hash, 'templates_sha256': templates_hash,
    'xcode': log('xcode-version.txt'), 'iphoneos_sdk': log('iphoneos-sdk-version.txt'),
    'platform': 'iphoneos', 'architectures': log('app-architectures.txt'),
    'signed': False, 'directly_installable_on_iphone': False,
    'xcode_project': 'StarLanternIsland-iOS-Xcode.zip', 'ipa': 'StarLanternIsland-unsigned.ipa'
}
(pathlib.Path(out) / 'BUILD-INFO.json').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$PRODUCT_NAME-iOS-Xcode.zip" "$PRODUCT_NAME-unsigned.ipa" > SHA256SUMS
)
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<'TEXT'
### iOS unsigned build

Compiled a physical-device arm64 Release app with code signing disabled.

- `StarLanternIsland-iOS-Xcode.zip`: complete editable Xcode export.
- `StarLanternIsland-unsigned.ipa`: compiled app in `Payload/`, **not directly installable on an ordinary iPhone**.
- Build evidence contains Xcode/Godot versions, logs and `SHA256SUMS`.

No Apple certificate, private key or provisioning profile was used.
TEXT
fi
printf '\nBuild completed. Unsigned artifacts: %s\n' "$OUTPUT_DIR"
