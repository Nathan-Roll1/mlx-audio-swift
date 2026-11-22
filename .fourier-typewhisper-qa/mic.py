"""Play a reference through the HAL input after the unmodified app starts recording."""
from pathlib import Path
import json, subprocess, time, urllib.error, urllib.request

result = Path('/tmp/fourier-typewhisper-mic-result.json')
state = {}
def stamp(**data):
    state.update(data)
    tmp = result.with_suffix('.tmp')
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(result)
def request(path, method='GET'):
    req = urllib.request.Request(
        f'http://127.0.0.1:{connection["port"]}{path}',
        headers={'Authorization':'Bearer '+connection['token']},
        method=method,
    )
    return json.load(urllib.request.urlopen(req, timeout=45))
try:
    for _ in range(240):
        if subprocess.run(['/usr/bin/pbpaste'], capture_output=True).stdout == b'fourier-test-editor-ready': break
        time.sleep(1)
    else: raise RuntimeError('Focused external editor did not signal readiness')
    setup = json.loads(Path('/tmp/fourier-signed-ui-fixture.json').read_text())
    discovery = Path.home()/'Library/Application Support/TypeWhisper/api-discovery.json'
    for _ in range(75):
        if discovery.is_file(): break
        time.sleep(.4)
    connection = json.loads(discovery.read_text())
    stamp(stage='starting')
    recording = request('/v1/dictation/start','POST')
    if recording.get('status') != 'recording':
        raise RuntimeError('App did not start recording')
    stamp(stage='recording', session=recording['id'])
    time.sleep(.5)
    subprocess.run(['/usr/bin/afplay','-v','0.85',setup['wav']], check=True)
    time.sleep(.7)
    request('/v1/dictation/stop','POST')
    stamp(stage='stopped')
    for _ in range(160):
        session = request('/v1/dictation/transcription?id='+recording['id'])
        t = session.get('transcription')
        if t:
            stamp(stage='transcribed', text=t.get('text'), raw=t.get('raw_text'), engine=t.get('engine'), model=t.get('model'), target=t.get('app_bundle_id'), duration=t.get('duration'))
            break
        if session.get('status') in ('failed','cancelled'):
            raise RuntimeError(str(session.get('error') or session.get('status')))
        time.sleep(.5)
    else: raise RuntimeError('Timed out waiting for the recorded transcript')
except Exception as err:
    detail=err.read(400).decode(errors='replace') if isinstance(err,urllib.error.HTTPError) else str(err)
    stamp(stage='failure',detail=detail)
    raise
