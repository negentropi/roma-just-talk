from pathlib import Path,PurePosixPath
import hashlib,json,re,stat,zipfile
root=Path('/data/rjt-writing-delivery-commit-40597919426');retained=root/'invalid-retained';retained.mkdir(exist_ok=True)
run=json.loads((root/'run-final.json').read_text());assert run['databaseId']==40597919426 and run['headSha']=='c5859b1f59997633fbd59d92565eb70c173c8392' and run['status']=='completed' and run['conclusion']=='failure'
artifacts=json.loads((root/'artifacts.json').read_text())['artifacts'];a=[a for a in artifacts if a['name']=='roma.writing-delivery-commit-observations'];assert len(a)==1;a=a[0];data=(root/'observations.zip').read_bytes();sha=hashlib.sha256(data).hexdigest();assert len(data)==a['size_in_bytes'] and a['digest']=='sha256:'+sha
z=zipfile.ZipFile(root/'observations.zip');assert z.testzip() is None;names=z.namelist();assert len(names)==len(set(names));members=[]
for i in z.infolist():
 p=PurePosixPath(i.filename);assert not p.is_absolute() and '..' not in p.parts and not stat.S_ISLNK(i.external_attr>>16)
 if not i.is_dir():
  raw=z.read(i.filename);members.append({'path':i.filename,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()});out=retained/'observations'/i.filename;out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(raw)
expect=json.loads((root/'git-expectations.json').read_text());contract=json.loads(z.read('contract.json'));assert contract['source_sha']==expect['candidate']['head'] and contract['baseline_reference_sha']==expect['baseline']['head'] and contract['lane']=='baseline'
old=json.loads(z.read('baseline-original-source.json'));assert old==expect['baseline']['source'];assert json.loads(z.read('candidate-source.json'))==expect['candidate']['source']
session='VoiceInk/Services/WritingActionSession.swift';audio='VoiceInkTests/DictationPolishAudioFileTests.swift';writing='VoiceInkTests/WritingActionDeliveryCommitTests.swift';baseline=json.loads(z.read('baseline-source.json'))
assert {k:v for k,v in baseline.items() if k not in {session,audio}}=={k:v for k,v in old.items() if k not in {session,audio}}
assert baseline[session]==contract['session_bridged_sha256']=='a04c539eb86d85ffb22f9a3fab46ceabbd69c297b8cfd63af8d3257a704b561e'
assert baseline[audio]==contract['oracle_sha256'][audio]=='365bc7f2b3b019ba2dd9284d8901b8b18fc4c82db1827cd7e134c109f95ab1e9'
assert writing not in old and contract['oracle_sha256'][writing]=='43933722762e49b156387907dcf0631be35154745b14b8d0ac5393ed81e12506'
assert json.loads(z.read('baseline/source-after.json'))==baseline
for p,sha2 in contract['oracle_sha256'].items():assert hashlib.sha256(z.read('source/'+p)).hexdigest()==sha2
assert hashlib.sha256(z.read('source/session-value-initializer.patch')).hexdigest()==contract['bridge_sha256']=='1b6048e13f973dc7cc8aae5ab13ff90a586396c7e7bffdeadca9a162e4ae2bea'
preservation=json.loads(z.read('baseline/source-preservation.json'));assert preservation['runtime_sources_preserved_except_initializer_bridge'] is True
log=z.read('baseline/tests.log').decode();cases=contract['tests'];starts=re.findall(r'\bTest (\w+)\(\) started\.',log);assert len(cases)==3 and sorted(starts)==sorted(cases)
for case in cases:assert re.findall(r'\bTest '+case+r'\(\) (passed|failed|skipped) after ',log)==['failed']
issues=[line for line in log.splitlines() if re.search(r'\brecorded an issue\b',line)];assert len(issues)==3
assert all('(ai.selectedProvider == .localCLI && ai.isAPIKeyValid → false) && (ai.apiKey.isEmpty → <not evaluated>)' in line for line in issues)
assert sum('DictationPolishAudioFileTests.swift:519:13:' in line for line in issues)==1 and sum('WritingActionDeliveryCommitTests.swift:127:17:' in line for line in issues)==2
verdict=json.loads(z.read('baseline/result.json'));assert not verdict['valid'] and verdict['failure_sites']==[] and len(verdict['issues'])==3
assert json.loads(z.read('baseline/exit.json'))['test_without_building_exit_code']==65
before=json.loads(z.read('baseline/identity-before.json'));assert before==json.loads(z.read('baseline/identity-after.json'))
sel=json.loads(z.read('baseline/selection/receipt.json'));assert sel['valid'] and len(sel['requested'])==3 and sorted(sel['requested'])==sorted(sel['enabled'])
assert json.loads(z.read('baseline/test-host-signature/result.json'))['strict_deep_verification_passed'] is True
native=[a for a in artifacts if a['name']=='roma.writing-delivery-commit-native-evidence'];assert len(native)==1;native=native[0]
for name in ['run-final.json','artifacts.json','failed.log']:(retained/name).write_bytes((root/name).read_bytes())
(retained/'artifact-members.json').write_text(json.dumps(members,indent=2)+'\n')
receipt={'run_id':40597919426,'url':run['url'],'head_sha':run['headSha'],'classification':'invalid-pre-action-AIService-fixture-configuration','baseline_reference_sha':contract['baseline_reference_sha'],'artifact':{'id':a['id'],'bytes':len(data),'sha256':sha,'crc_members':len(members),'download_count':1},'native_artifact':{k:native[k] for k in ['id','name','size_in_bytes','digest']},'native_artifact_downloaded':False,'failed_log_fetch_count':1,'source_closure':{'candidate_tracked_files_match_git':len(expect['candidate']['source']),'baseline_original_tracked_files_match_git':len(old),'baseline_runtime_preserved_except_initializer_bridge':True,'explicit_test_instrumentation':contract['instrumentation'],'baseline_after_source_matches_before':True,'both_common_oracles_exact':contract['oracle_sha256']},'actual_results':{'started':3,'failed':3,'skipped':0,'issues':issues,'allowed_post_mutation_issues':0,'exit_code':65,'app_and_test_identity_unchanged':True,'strict_debug_host_signature_verified':True,'exact_selection_verified':True},'findings':['Each fixture throws at its AIService initialization requirement before entering the tested operation. The compound expression reveals configuration failure but does not isolate the failing provider/validity operand.','No fake editor mutation, import execution or controlled read-only completed-record save was reached; no Cocoa 513 fixture diagnostic appeared.','The classifier correctly rejected the three setup failures rather than treating any failing test as old-bug proof.'],'limits':['This is an invalid setup run, not old post-delivery cancellation or pending-import-row reproduction','No physical editor, ASR, provider model or Undo gesture behavior tested','Native build/xcresult artifact remains GitHub metadata only; no 94 MB download','No fix chosen from the compound error alone; runtime configuration diagnostics required']}
(retained/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'classification':receipt['classification'],'started':3,'setup_issues':3,'accepted_bug_issues':0,'members':len(members),'artifact_bytes':len(data)}))
