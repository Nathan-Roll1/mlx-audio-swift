set -euo pipefail
base="$RUNNER_TEMP/mic-ui"
mkdir -p "$base" "$RUNNER_TEMP/permission-screens"
cd "$base"
curl --retry 1 --max-time 70 -fsSL https://github.com/TypeWhisper/typewhisper-mac/releases/download/v1.8.3/TypeWhisper-v1.8.3.zip -o app.zip
echo 'b6467c30a21f11a6ed3cd29a5eea927e840af0bcdf25c9f30be8a85d66fc41f7  app.zip' | shasum -a 256 -c
ditto -x -k app.zip .
app="$base/TypeWhisper.app"
codesign --verify --deep --strict "$app"
codesign -dv --verbose=2 "$app" 2>&1 | grep -E 'Identifier|TeamIdentifier|Authority'
domain=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
# Resume the normal installation wizard on its Permissions page. These are
# TypeWhisper UI preferences only; the OS decides privacy authorization.
defaults write "$domain" setupWizardCompleted -bool false
defaults write "$domain" setupWizardCurrentStep -int 1
defaults write "$domain" usageIntent -string personalOSS
defaults write "$domain" welcomeSheetShown -bool true
defaults write "$domain" iOSCompanionPromoCampaign -string ios-app-store-launch-2026-09
defaults write "$domain" lastSeenWhatsNewContentVersion -int 1
defaults write "$domain" SUEnableAutomaticChecks -bool false
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
command -v xcodegen || brew install xcodegen
mkdir -p ui/Runner ui/Tests
cp "$GITHUB_WORKSPACE/.fourier-typewhisper-qa/Onboarding.swift" ui/Tests/
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
(
  for seq in {1..30}; do
    if [[ "$(pbpaste 2>/dev/null)" = "fourier-record-permission-probe" ]]; then
      screencapture -x "$RUNNER_TEMP/permission-screens/first.png" || true
      sleep 3
      screencapture -x "$RUNNER_TEMP/permission-screens/after.png" || true
      break
    fi
    sleep 3
  done
) &
probe=$!
set +e
xcodebuild test -scheme ReleaseUI -destination 'platform=macOS' -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- > "$base/xcode.log" 2>&1
ret=$?
kill "$probe" 2>/dev/null || true
grep -E 'PERMISSION_PROBE|error:|Test Case' "$base/xcode.log" | tail -85 || true
log show --last 2m --style compact --predicate 'subsystem == "com.apple.TCC" AND (eventMessage CONTAINS[c] "typewhisper" OR eventMessage CONTAINS[c] "kTCCServiceMicrophone")' | tail -24 || true
exit "$ret"
