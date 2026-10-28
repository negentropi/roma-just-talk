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
assert read('verification-mode.json')=={'sourceSHA':'0184f9a1552d281cd6b416446b92e091b6bdad29','mode':'full','fullGateRequired':True}
status=read('workflow-status.json');assert status['headSha']=='0184f9a1552d281cd6b416446b92e091b6bdad29' and status['conclusion']=='success'
t=read('ui-case-summary.json');assert not t['failures'] and len(t['tests'])==8 and all(x['starts']==1 and x['results']==['passed'] for x in t['tests'].values())
assert read('independent-copy-byte-audit.json')['classification']=='passed'
assert read('independent-paired-static-byte-audit.json')['classification']=='passed'
v=read('raw/candidate/verification-verdicts.json');assert v['valid'] and v['driver_exit_code']==0 and v['ui']['classification']=='passed'
n=v['native'];assert n['classification']=='passed' and n['phases']['verify']['testAttempted'] and n['pair']['valid']
r=n['phases']['verify']['result'];assert r['valid'] and r['verificationReadOnly'] and not r['saveCompleted'] and r['statsUnchanged'] and r['correctionReceiptsUnchanged']
assert r['savedCounts']=={'Transcription':5,'WordReplacement':2,'VocabularyWord':1,'SessionMetric':0}
c=r['corrections'];assert c['managedCorrectionAbsent'] and c['managedSourceRetained'] and c['retainedCorrectionPresent'] and c['retainedSourceDeleted'] and c['noForeignRows']
assert c['retainedDateWithinPreviewApproval']
for phase in ['seed','verify']:
 checks=read(f'raw/candidate/history-seed/{phase}/tcc-check.json')['checks']
 for x in checks.values():assert x['valid'] and x['raw_bytes_equal'] and x['actual'][0]['auth_value']==2 and x['actual']==x['expected']
for service in ['system-tcc.json','microphone-tcc.json']:
 q=p/'raw/candidate/history-seed';assert (q/'seed'/service).read_bytes()==(q/'verify'/service).read_bytes()
for name in ['identity','app-signature','test-bundle-signature']:
 q=p/'raw/candidate/history-seed';values=[q/phase/(name+suffix+'.txt') for phase,suffix in [('seed','-before'),('seed','-after'),('verify','-before'),('verify','-after')]]
 assert len({x.read_bytes() for x in values})==1,name
c=read('raw/candidate/history-seed/closed-after-ui.json');assert c['valid'] and c['ownedAppExited'] and c['normalStoresHaveNoOpenDescriptors']
assert len(read('shortcut-censuses.json'))==8
for c in read('shortcut-censuses.json'):
 assert all(x['synchronized'] for x in c['phases'])
 assert next(x['keys'] for x in c['phases'] if x['phase']=='before')==next(x['keys'] for x in c['phases'] if x['phase']=='restored')
monitors=read('microphone-interruption-censuses.json');assert len(monitors)==2
for m in monitors:
 c=m['content'];assert c['recognized'] and c['rejectReason'] is None
 assert c['owner']['pid']==63805 and c['owner']['runningCount']==1 and c['bundlePurpose']==c['expectedPurpose']
 a=[x for x in c['buttons'] if x['identifier']=='action-button-1'];b=[x for x in c['buttons'] if x['identifier']=='action-button-2'];assert len(a)==len(b)==1
 assert a[0]['title']=='Allow' and b[0]['title']=='Don’t Allow' and a[0]['label']==b[0]['label']==''
assert len(read('microphone-consent-outcomes.json'))==2
for x in read('microphone-consent-outcomes.json'):
 assert x['text']=='clicked Allow (action-button-1); dialog dismissed: true'
 assert sha(p/'raw'/x['exported'])==x['sha256']
assert read('frozen-eight-methods.json')['all_eight_method_bodies_byte_equal']
assert len(read('visual-review.json')['screenshots'])==45
assert not read('visual-review.json')['findings']
assert 'Handling user permission dialog by clicking' not in (p/'raw/candidate/tests.log').read_text()
print('PASS: UI8 once, Copy11/pairedStatic11 exact; two owned Allow clicks/dismissals; signedMic/AX2 stable; normal-store read-only native verification passed T5/W2/V1/stats0. CI packaging only; no publication.')
