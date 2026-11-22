set -euo pipefail
test "$(git rev-parse HEAD)" = 55e39acddef13a87331ee807c37d723e6412b5fd
qa="$GITHUB_WORKSPACE/qa/airdraft-fourier"
git apply --check "$qa/row.patch" && git apply "$qa/row.patch"
cp "$qa/RuntimeProof.swift" Packages/AirdraftCore/Tests/AirdraftCoreTests/
fixture=Packages/AirdraftCore/Tests/AirdraftCoreTests/qa-fixtures
mkdir -p "$fixture"
curl -fsSL --retry 2 https://raw.githubusercontent.com/ggml-org/whisper.cpp/b0a11594aec50892a02cd8d129eee2dfe93a8bb8/samples/jfk.wav -o "$fixture/jfk.wav"
curl -fsSL --retry 2 https://raw.githubusercontent.com/handy-computer/transcribe.cpp/cfa237c2551a4b2d3a56ff8fe5461e3c67c51772/samples/fleurs-en.wav -o "$fixture/fleurs.wav"
(echo "59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e  $fixture/jfk.wav"; echo "7835bd6ffb54ce38a2a9bcde3905ba424faed94d50a474f21a9cbe9209b869df  $fixture/fleurs.wav") | shasum -a 256 -c -
python3 scripts/localization.py check
cmp AGENTS.md CLAUDE.md
