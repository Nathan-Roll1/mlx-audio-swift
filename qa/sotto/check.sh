#!/usr/bin/env bash
set -euo pipefail
cd "$RUNNER_TEMP"
fetch() { curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 20 --retry 2 "$1" -o "$2"; }
check() { echo "$1  $2" | shasum -a 256 -c -; }
sw_vers; arch
fetch https://github.com/FurkanCodes/Sotto/releases/download/v0.3.3/Sotto-0.3.3.zip Sotto.zip
check 767c9c8bc3387c8a0e6e334d41b28025c3fe11791a38d4dad9f56847a00ae751 Sotto.zip
ditto -xk Sotto.zip app
app=$(find "$PWD/app" -type d -name 'Sotto.app' | head -1)
codesign --verify --deep --strict "$app"
exe="$app/Contents/MacOS/Sotto"
"$exe" --list-models
fetch https://raw.githubusercontent.com/ggml-org/whisper.cpp/b0a11594aec50892a02cd8d129eee2dfe93a8bb8/samples/jfk.wav jfk.wav
check 59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e jfk.wav
fetch https://raw.githubusercontent.com/handy-computer/transcribe.cpp/cfa237c2551a4b2d3a56ff8fe5461e3c67c51772/samples/fleurs-en.wav fleurs.wav
check 7835bd6ffb54ce38a2a9bcde3905ba424faed94d50a474f21a9cbe9209b869df fleurs.wav
fetch https://huggingface.co/oruk/oruk-fourier-2b/resolve/8bcce21695e4ba13569c48de6cedffcb8a7576f5/Fourier-2B-Q8_0.gguf Fourier-2B-Q8_0.gguf
check 6a7c419bd571f7b0e21da2d5ab1e3a1a3938a83470d622be57427af98f322981 Fourier-2B-Q8_0.gguf
for clip in jfk fleurs; do
  echo "Running $clip"
  "$exe" --transcribe-file "$PWD/$clip.wav" --model "$PWD/Fourier-2B-Q8_0.gguf" --repeat 1 | tee "$clip.log"
done
python3 - <<'PY'
import json, re
from pathlib import Path
reference = {
    'jfk': 'and so my fellow americans ask not what your country can do for you ask what you can do for your country',
    'fleurs': 'however due to the slow communication channels styles in the west could lag behind by 25 to 30 year'}
def normalized(txt):
    txt = re.sub(r'[^a-z0-9 ]+',' ',txt.casefold())
    txt = re.sub(r'\btwenty\s+five\b','25',txt)
    txt = re.sub(r'\bthirty\b','30',txt)
    return txt.split()
def distance(a, b):
    row = list(range(len(b)+1))
    for i,x in enumerate(a,1):
        nextrow=[i]
        for j,y in enumerate(b,1):
            nextrow.append(min(row[j]+1,nextrow[-1]+1,row[j-1]+int(x!=y)))
        row=nextrow
    return row[-1]
for k, ref in reference.items():
    rows = [json.loads(s) for s in Path(k+'.log').read_text().splitlines() if s.lstrip().startswith('{')]
    assert len(rows)==1, rows
    r = rows[0]
    assert r['engine']=='gpu' and r['audio_seconds'] > 10 and r['text'],r
    rr = ref.split()
    errors = distance(rr, normalized(r['text']))
    print('RELEASE_RESULT '+json.dumps(dict(clip=k,normalized_word_errors=errors,reference_words=len(rr),**r)))
    assert errors<=2, (k,errors)
PY
