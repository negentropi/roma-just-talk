#!/usr/bin/env python3
from pathlib import Path
import hashlib,json
p=Path(__file__).resolve().parent
def read(n):return json.loads((p/n).read_text())
def sha(x):return hashlib.sha256(x.read_bytes()).hexdigest()
for x in read('artifact-origins.json')['retained_raw_members']:
 q=p/'raw'/x['relative'];assert q.stat().st_size==x['bytes'] and sha(q)==x['sha256'],q
for x in read('source-pins.json')['files']:
 q=p/x['retained'];assert q.stat().st_size==x['bytes'] and sha(q)==x['sha256'],q
assert read('verification-mode.json')=={'sourceSHA':'9afb1ed848ea2c12c4a00d6173871d67d13bfb45','mode':'full','fullGateRequired':True}
t=read('ui-case-summary.json');assert not t['failures'] and len(t['tests'])==8 and all(x['starts']==1 and x['results']==['passed'] for x in t['tests'].values())
assert read('independent-copy-byte-audit.json')['classification']=='passed'
assert read('independent-paired-static-byte-audit.json')['classification']=='passed'
v=read('raw/candidate/verification-verdicts.json');assert v['ui']['classification']=='passed' and v['boundary']=='history-verify' and v['native']['boundary']=='native-permissions' and v['native']['phases']['verify']['testAttempted'] is False
checks=read('raw/candidate/history-seed/verify/tcc-check.json')['checks'];assert checks['system-tcc.json']['valid'];m=checks['microphone-tcc.json'];a=m['actual'][0];b=m['expected'][0];assert a['auth_value']==0 and b['auth_value']==2 and all(a[k]==b[k] for k in ['client','client_type','service','csreq'])
for name in ['identity','app-signature','test-bundle-signature']:
 q=p/'raw/candidate/history-seed';assert (q/'seed'/(name+'-before.txt')).read_bytes()==(q/'seed'/(name+'-after.txt')).read_bytes()==(q/'verify'/(name+'-before.txt')).read_bytes()
c=read('raw/candidate/history-seed/closed-after-ui.json');assert c['valid'] and c['ownedAppExited'] and c['normalStoresHaveNoOpenDescriptors']
for c in read('shortcut-censuses.json'):
 assert all(x['synchronized'] for x in c['phases'])
 assert next(x['keys'] for x in c['phases'] if x['phase']=='before')==next(x['keys'] for x in c['phases'] if x['phase']=='restored')
monitors=read('microphone-interruption-censuses.json');assert len(monitors)==2
for m in monitors:
 c=m['content'];assert not c['recognized'] and c['rejectReason']=='Allow button is not unique'
 assert c['owner']['pid']==65317 and c['owner']['runningCount']==1 and c['bundlePurpose']==c['expectedPurpose']
 assert sum(x['label']=='Allow' for x in c['buttons'])==0
 assert len([x for x in c['buttons'] if x['identifier']=='action-button-1'])==1
 assert len([x for x in c['buttons'] if x['identifier']=='action-button-2'])==1
assert read('frozen-eight-methods.json')['all_eight_method_bodies_byte_equal']
assert 'Handling user permission dialog by clicking' in (p/'microphone-interruption-excerpt.log').read_text()
assert len(read('visual-review.json')['screenshots'])==45
assert not read('visual-review.json')['findings']
print('PASS: eight UI cases once, Copy11/pairedStatic11 exact, two owned microphone dialogs rejected on zero Allow labels; physical closure/signatures exact. Final native semantic verification blocked; no full-green/Release claim.')
