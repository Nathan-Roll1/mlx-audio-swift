set -euo pipefail
test "$(uname -m)" = arm64
echo "Host $(sw_vers -productVersion) on $(uname -m)"
xcodebuild -version
base="$RUNNER_TEMP/typewhisper"
mkdir -p "$base/sdk-src" "$base/interface"
app="$base/TypeWhisper.app"
plugin="$base/Qwen3Plugin.bundle"
cd "$base"
curl --retry 3 -fsSL 'https://github.com/TypeWhisper/typewhisper-mac/releases/download/v1.8.3/TypeWhisper-v1.8.3.zip' -o app.zip
curl --retry 3 -fsSL 'https://github.com/TypeWhisper/typewhisper-mac/releases/download/plugin-qwen3-v1.3.0/Qwen3Plugin.zip' -o plugin.zip
printf '%s\n' 'b6467c30a21f11a6ed3cd29a5eea927e840af0bcdf25c9f30be8a85d66fc41f7  app.zip' '3766243197b57257fd504a899f190744cd78c8bc4a4350a2aae2e7b08aa906cc  plugin.zip' | shasum -a 256 -c
ditto -x -k app.zip .
ditto -x -k plugin.zip .
for signed in "$app" "$plugin"; do
  codesign --verify --deep --strict "$signed"
  codesign -dv --verbose=4 "$signed" 2>&1 | grep -E '^Identifier|^Authority|^TeamIdentifier'
done
domain=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
echo "BUNDLE_ID=$domain"
plutil -extract NSServices json -o - "$app/Contents/Info.plist" || true
mkdir -p "$HOME/Library/Application Support/TypeWhisper/Plugins"
ditto "$plugin" "$HOME/Library/Application Support/TypeWhisper/Plugins/Qwen3Plugin.bundle"
defaults write "$domain" plugin.com.typewhisper.qwen3.enabled -bool true
defaults write "$domain" apiServerEnabled -bool false
defaults write "$domain" setupWizardCompleted -bool true
defaults write "$domain" SUEnableAutomaticChecks -bool false
open -gna "$app"
sleep 2
pgrep -x TypeWhisper || true
git -C sdk-src init -q
git -C sdk-src remote add origin https://github.com/TypeWhisper/typewhisper-mac.git
git -C sdk-src config core.sparseCheckout true
cat > sdk-src/.git/info/sparse-checkout <<'EOF'
/TypeWhisperPluginSDK/Sources/TypeWhisperPluginSDK/*.swift
/TypeWhisperPluginSDK/Sources/TypeWhisperPluginSDKTesting/*.swift
EOF
git -C sdk-src fetch -q --filter=blob:none --depth=1 origin 8ab179c028ab384359bddcdc24b31cc159e1a870
git -C sdk-src checkout -q --detach FETCH_HEAD
swiftc -swift-version 5 -parse-as-library -module-name TypeWhisperPluginSDK -emit-module -emit-module-path "$base/interface/TypeWhisperPluginSDK.swiftmodule" -target arm64-apple-macos15.0 "$base"/sdk-src/TypeWhisperPluginSDK/Sources/TypeWhisperPluginSDK/*.swift
frameworks="$app/Contents/Frameworks"
swiftc -swift-version 5 -parse-as-library -I "$base/interface" -F "$frameworks" -framework TypeWhisperPluginSDK -Xlinker -rpath -Xlinker "$frameworks" -target arm64-apple-macos15.0 "$base"/sdk-src/TypeWhisperPluginSDK/Sources/TypeWhisperPluginSDKTesting/PluginTestSupport.swift "$GITHUB_WORKSPACE/.fourier-typewhisper-qa/Verify.swift" -o "$base/verify"
otool -L "$base/verify" | grep TypeWhisperPluginSDK
otool -L "$plugin/Contents/MacOS/Qwen3Plugin" | grep TypeWhisperPluginSDK
curl --retry 3 -fsSL https://raw.githubusercontent.com/ggml-org/whisper.cpp/b0a11594aec50892a02cd8d129eee2dfe93a8bb8/samples/jfk.wav -o jfk.wav
curl --retry 3 -fsSL https://raw.githubusercontent.com/brittain9/speech-kit-obsidian-plugin/5d62e514bef084d65c9e0ea590636982b084aa43/native/tests/fixtures/audio/7021-79740-0000.wav -o libri.wav
printf '%s\n' '59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e  jfk.wav' 'd0d6bcf2e108dde9e7c1575ad843512213b1cff5ea77b9231e7f256591aa0986  libri.wav' | shasum -a 256 -c
modeldata="$HOME/Library/Application Support/TypeWhisper/PluginData/com.typewhisper.qwen3"
mkdir -p "$modeldata"
"$base/verify" "$plugin" "$modeldata" "$base/jfk.wav" "$base/libri.wav" | tee "$base/result.log"
# Restore user preferences recorded by the genuine importer for the release-app UI check.
modelid="$(python3 -c 'import json,sys;print(json.loads([l for l in open(sys.argv[1]) if l.startswith("SIGNED_PLUGIN_RESULT=")][0].split("=",1)[1])["id"])' "$base/result.log")"
killall TypeWhisper || true
sleep 2
defaults write "$domain" plugin.com.typewhisper.qwen3.loadedModel -string "$modelid"
defaults write "$domain" plugin.com.typewhisper.qwen3.selectedModel -string "$modelid"
defaults write "$domain" selectedEngine -string qwen3
defaults write "$domain" modelAutoUnloadSeconds -int 0
defaults write "$domain" fileTranscriptionEngine -string qwen3
defaults write "$domain" fileTranscriptionModel -string "$modelid"
defaults write "$domain" fileTranscriptionLanguage -string en
defaults write "$domain" fileTranscriptionAutoSave -bool true
defaults write "$domain" fileTranscriptionAutoSaveFormat -string txt
python3 - "$app/Contents/Info.plist" "$domain" "$base/jfk.wav" <<'PY'
import json,plistlib,sys
x=plistlib.load(open(sys.argv[1],'rb'))
s=next(v for v in x['NSServices'] if 'transcri' in str(v).lower())
n=s['NSMenuItem']['default'];print('SERVICE',n)
open('/tmp/fourier-signed-ui-fixture.json','w').write(json.dumps({'service':n,'bundle':sys.argv[2],'wav':sys.argv[3]}))
PY
command -v xcodegen || brew install xcodegen
mkdir -p ui/Runner ui/Tests
cp "$GITHUB_WORKSPACE/.fourier-typewhisper-qa/SignedAppUI.swift" ui/Tests/
cat > ui/Runner/Main.swift <<'EOF'
import SwiftUI
@main struct Empty: App {
    @State private var contents = ""
    var body: some Scene {
        WindowGroup { TextEditor(text: $contents).accessibilityIdentifier("pasteTestField").frame(minWidth: 300, minHeight: 120) }
    }
}
EOF
cat > ui/project.yml <<'EOF'
name: ReleaseUI
options:
  deploymentTarget:
    macOS: "15.0"
settings:
  GENERATE_INFOPLIST_FILE: YES
  CODE_SIGN_IDENTITY: "-"
  ENABLE_HARDENED_RUNTIME: NO
targets:
  Empty:
    type: application
    platform: macOS
    sources: [Runner]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: dev.local.fourier.empty
  ReleaseUITests:
    type: bundle.ui-testing
    platform: macOS
    sources: [Tests]
    dependencies: [{target: Empty}]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: dev.local.fourier.ui
      TEST_TARGET_NAME: Empty
schemes:
  ReleaseUI:
    build:
      targets: {Empty: all, ReleaseUITests: [test]}
    test:
      targets: [ReleaseUITests]
EOF
cd ui
xcodegen generate
set +e
xcodebuild test -scheme ReleaseUI -destination 'platform=macOS' -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- > "$base/ui.log" 2>&1
ret=$?
grep -E 'SERVICES_NAME|SIGNED_GUI_|GUI_TREE|error:|XCTAssert|failed|Test Case' "$base/ui.log" | tail -100 || true
/usr/bin/log show --last 4m --style compact --predicate 'process == "TypeWhisper" && (messageType == error || messageType == fault)' | tail -40 || true
echo "SIGNED_GUI_EXIT=$ret"
exit "$ret"
