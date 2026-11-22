import hashlib,json,struct,re
from pathlib import Path
p=Path('Fourier-MLX-4bit')
weights=list(p.glob('*.safetensors'))
headers={}
for f in weights:
 with f.open('rb') as b:
  n=struct.unpack('<Q',b.read(8))[0];headers.update(json.loads(b.read(n)))
scales=[k for k in headers if k.endswith('.scales')]
assert scales and not any(k.startswith('audio_tower.') for k in scales)
refs={'jfk':('59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e','And so my fellow Americans ask not what your country can do for you ask what you can do for your country'),
      'libri':('d0d6bcf2e108dde9e7c1575ad843512213b1cff5ea77b9231e7f256591aa0986','To such persons these indirect modes of training children in habits of subordination to their will or rather of yielding to their influence are specially useful')}
def edits(a,b):
 r=list(range(len(b)+1))
 for i,x in enumerate(a):
  s=[i+1]
  for j,y in enumerate(b):s.append(min(s[-1]+1,r[j+1]+1,r[j]+(x!=y)))
  r=s
 return r[-1]
out={}
for key,(wavhash,ref) in refs.items():
 assert hashlib.sha256(Path(key+'.wav').read_bytes()).hexdigest()==wavhash
 text=Path(key+'-transcript.txt').read_text().strip();norm=lambda x:re.findall(r"[a-z]+",x.lower())
 out[key]=dict(words=len(norm(ref)),edits=edits(norm(ref),norm(text)),text=text)
print('STABLE_MLX_RESULT='+json.dumps({'files':{f.name:f.stat().st_size for f in weights},'quantized_modules':len(scales),'audio_encoder_quantized':False,'samples':out}),flush=True)
assert all(v['edits']<=2 for v in out.values()),out
