from pathlib import Path,PurePosixPath
import hashlib,json,re,stat,zipfile,plistlib
root=Path('/data/rjt-writing-delivery-commit-40604256480');retained=root/'retained';retained.mkdir(exist_ok=True)
run=json.loads((root/'run-final.json').read_text());assert run['databaseId']==40604256480 and run['headSha']=='6394dc0fb777e77a5dc237b42a68455dba1fac99' and run['status']=='completed' and run['conclusion']=='success'
metadata=json.loads((root/'artifacts.json').read_text())['artifacts'];expected=json.loads((root/'git-expectations.json').read_text());archives={};members=[]
for kind,name,suffix in [('observations','roma.writing-delivery-commit-observations','contract.json'),('native','roma.writing-delivery-commit-native-evidence','baseline/build.log')]:
 a=[a for a in metadata if a['name']==name];assert len(a)==1;a=a[0];data=(root/(kind+'.zip')).read_bytes();sha=hashlib.sha256(data).hexdigest();assert len(data)==a['size_in_bytes'] and a['digest']=='sha256:'+sha
 z=zipfile.ZipFile(root/(kind+'.zip'));assert z.testzip() is None;names=z.namelist();assert len(names)==len(set(names));match=[n for n in names if n==suffix or n.endswith('/'+suffix)];assert len(match)==1
 for i in z.infolist():
  p=PurePosixPath(i.filename);assert not p.is_absolute() and '..' not in p.parts and not stat.S_ISLNK(i.external_attr>>16)
  if not i.is_dir():members.append({'archive':kind,'path':i.filename,'bytes':i.file_size,'sha256':hashlib.sha256(z.read(i.filename)).hexdigest()})
 archives[kind]={'zip':z,'id':a['id'],'bytes':len(data),'sha256':sha,'crc_members':len(names),'download_count':1,'prefix':match[0][:-len(suffix)]}
def raw(path,kind='observations'):return archives[kind]['zip'].read(archives[kind]['prefix']+path)
def obj(path,kind='observations'):return json.loads(raw(path,kind))
contract=obj('contract.json');assert contract['source_sha']==expected['candidate']['head'] and contract['baseline_reference_sha']==expected['baseline']['head'] and contract['lane']=='baseline'
original=obj('baseline-original-source.json');assert original==expected['baseline']['source'];assert obj('candidate-source.json')==expected['candidate']['source']
session='VoiceInk/Services/WritingActionSession.swift';audio='VoiceInkTests/DictationPolishAudioFileTests.swift';writing='VoiceInkTests/WritingActionDeliveryCommitTests.swift';baseline=obj('baseline-source.json')
assert {k:v for k,v in baseline.items() if k not in {session,audio}}=={k:v for k,v in original.items() if k not in {session,audio}}
assert baseline[session]==contract['session_bridged_sha256']=='a04c539eb86d85ffb22f9a3fab46ceabbd69c297b8cfd63af8d3257a704b561e'
assert baseline[audio]==contract['oracle_sha256'][audio]=='365bc7f2b3b019ba2dd9284d8901b8b18fc4c82db1827cd7e134c109f95ab1e9' and writing not in original
assert contract['oracle_sha256'][writing]=='43933722762e49b156387907dcf0631be35154745b14b8d0ac5393ed81e12506'
assert obj('baseline/source-after.json')==baseline
for name,sha in contract['oracle_sha256'].items():assert hashlib.sha256(raw('source/'+name)).hexdigest()==sha
missing_hidden_helpers=[]
for name,sha in contract['helper_sha256'].items():
 assert sha==expected['candidate']['source'][name]
 key=archives['observations']['prefix']+'source/'+name
 if key in archives['observations']['zip'].namelist():assert hashlib.sha256(raw('source/'+name)).hexdigest()==sha
 else:
  assert name=='.github/workflows/voiceink-writing-delivery-commit-check.yml';missing_hidden_helpers.append(name)
assert hashlib.sha256(raw('source/baseline-original-session.swift')).hexdigest()==original[session]==contract['session_original_sha256']=='10fc37409284b6c5bc4d60986bfd7b030046c08654c639781061c5b7058c6596'
assert hashlib.sha256(raw('source/baseline-original-audio-tests.swift')).hexdigest()==original[audio]
assert hashlib.sha256(raw('source/session-value-initializer.patch')).hexdigest()==contract['bridge_sha256']=='1b6048e13f973dc7cc8aae5ab13ff90a586396c7e7bffdeadca9a162e4ae2bea'
assert obj('baseline/source-preservation.json')['runtime_sources_preserved_except_initializer_bridge'] is True
sites=contract['expected_baseline_assertions'];assert len(sites)==25
log=raw('baseline/tests.log').decode();cases=contract['tests'];assert len(cases)==3 and sorted(re.findall(r'\bTest (\w+)\(\) started\.',log))==sorted(cases)
for name in cases:assert re.findall(r'\bTest '+name+r'\(\) (passed|failed|skipped) after ',log)==['failed']
assert re.findall(r'Test run with (\d+) tests in (\d+) suites failed',log)==[('3','3')]
issues=[s for s in log.splitlines() if 'recorded an issue' in s];assert len(issues)==25;seen=[]
for issue in issues:
 m=re.search(r'\bTest (\w+)\(\) recorded an issue at (.+):(\d+):\d+:.*Expectation failed:',issue);assert m;key=PurePosixPath(m[2]).name+':'+m[3];assert key in sites and sites[key]['test']==m[1];site=sites[key]
 source=raw('source/VoiceInkTests/'+site['file']).decode();assert '#expect('+site['expression'] in source.splitlines()[site['line']-1]
 kind=site['observed']
 if kind=='canceled-state':assert '→ .canceled' in issue
 elif kind=='one-cancellation':assert re.search(r'→\s*1\)\s*==\s*0',issue)
 elif kind=='nonempty-first-query':assert '(firstVisibleRows → [VoiceInk.Transcription]).isEmpty → false' in issue
 elif kind=='nil':assert '→ nil' in issue
 else:assert kind=='The transcription was canceled.' and '→ "The transcription was canceled."' in issue
 seen.append(key)
assert sorted(seen)==sorted(sites)
assert len(re.findall(r'^.*SwiftData\.DefaultStore save failed with error: Error Domain=NSCocoaErrorDomain Code=513\b[^\n]*',log,re.M))==1
verdict=obj('baseline/result.json');assert verdict['valid'] and not verdict['errors'] and verdict['classification']=='intended-post-delivery-and-first-query-failures' and sorted(verdict['failure_sites'])==sorted(sites)
assert obj('baseline/exit.json')['test_without_building_exit_code']==65
result=obj('result.json');assert result['classification']=='matched-baseline-valid' and result['source_sha']==run['headSha'] and result['result']==verdict and result['contract_sha256']==hashlib.sha256(raw('contract.json')).hexdigest()
before=obj('baseline/identity-before.json');assert before==obj('baseline/identity-after.json');selection=obj('baseline/selection/receipt.json');assert selection['valid'] and len(selection['requested'])==3 and sorted(selection['requested'])==sorted(selection['enabled']) and not set(selection['requested'])&set(selection['disabled'])
sign=obj('baseline/test-host-signature/result.json');assert sign['strict_deep_verification_passed'] and sign['signature']=='adhoc' and sign['executable_sha256']==before['app_files_sha256']['Contents/MacOS/roma just talk']
csreq=raw('baseline/host.csreq','native');tcc=obj('baseline/tcc.json');assert len(tcc)==2 and {r['service'] for r in tcc}=={'kTCCServiceAccessibility','kTCCServiceMicrophone'} and all(r['auth_value']==2 and r['requirement']==csreq.hex().upper() for r in tcc)
cfg=raw('baseline/isolated.xctestrun','native');configuration=obj('baseline/configuration.json');assert hashlib.sha256(cfg).hexdigest()==configuration['isolated_sha256'];pv=plistlib.loads(cfg)
if 'TestConfigurations' in pv:targets=[t for c in pv['TestConfigurations'] for t in c['TestTargets']]
else:targets=[v for k,v in pv.items() if not k.startswith('__')]
assert len(targets)==1;t=targets[0];assert '-selectedAIProvider' not in t['CommandLineArguments'] and configuration['seed_preferences']['selectedAIProvider']=='Local CLI' and t['CommandLineArguments']==configuration['command_line_arguments']
assert t['EnvironmentVariables']['CFFIXED_USER_HOME']==configuration['isolated_user_home'] and t['ParallelizationEnabled'] is False
settings=obj('baseline/build-settings.json');settings=[s['buildSettings'] for s in settings if s.get('target')=='VoiceInk'];assert len(settings)==1 and 'LOCAL_BUILD' in settings[0]['SWIFT_ACTIVE_COMPILATION_CONDITIONS'].split()
packages=obj('baseline/packages-before.json');canonical=raw('packages/canonical.Package.resolved');assert hashlib.sha256(canonical).hexdigest()==contract['canonical_lock_sha256']==expected['candidate']['source']['VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'];pins=json.loads(canonical)['pins'];assert len(pins)==41 and packages['revisions']=={p['identity']:p['state']['revision'] for p in pins}
build=raw('baseline/build.log','native').decode();assert '** TEST BUILD SUCCEEDED **' in build
for path in ['TranscriptionPipeline.swift','AudioFileTranscriptionManager.swift','WritingTarget.swift']:
 assert re.search(r'SwiftCompile[^\n]*'+path,build)
for i in archives['observations']['zip'].infolist():
 if not i.is_dir():
  out=retained/'observations'/i.filename.removeprefix(archives['observations']['prefix']);out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(archives['observations']['zip'].read(i.filename))
for name in ['run-final.json','artifacts.json']:(retained/name).write_bytes((root/name).read_bytes())
(retained/'artifact-members.json').write_text(json.dumps(members,indent=2)+'\n');(retained/'baseline-isolated.xctestrun').write_bytes(cfg);(retained/'baseline-host.csreq').write_bytes(csreq)
(retained/'baseline-build-excerpt.txt').write_text('\n'.join([s for s in build.splitlines() if s.startswith('SwiftCompile') and any(n in s for n in ['TranscriptionPipeline.swift','AudioFileTranscriptionManager.swift','WritingTarget.swift'])]+['** TEST BUILD SUCCEEDED **'])+'\n')
receipt={'run_id':40604256480,'url':run['url'],'head_sha':run['headSha'],'classification':'valid-native-old-post-delivery-and-first-query-red','baseline_reference_sha':contract['baseline_reference_sha'],'artifacts':{k:{key:v[key] for key in ['id','bytes','sha256','crc_members','download_count']} for k,v in archives.items()},'source_closure':{'source_head_tracked_files_match_git':len(expected['candidate']['source']),'historical_original_tracked_files_match_git':len(original),'historical_receiver_sources_preserved_except_initializer_bridge':True,'test_instrumentation':contract['instrumentation'],'source_after_matches_before':True,'common_oracle_sha256':contract['oracle_sha256'],'natural_initializer_bridge_sha256':contract['bridge_sha256'],'canonical_packages':41,'hidden_helper_bytes_not_in_observation_archive':missing_hidden_helpers,'hidden_helper_hashes_equal_pinned_git_and_full_source_census':True},'actual_results':{'native_started':3,'native_failed':3,'skipped':0,'issues':25,'exit_code':65,'post_mutation_metadata_issues':24,'first_caller_query_ghost_issue':1,'controlled_read_only_Cocoa513_diagnostics':1,'strict_fixture_provider_requirements_passed':True,'other_positive_controls_passed':True,'unchanged_full_app_and_test_bundle_identity':True,'exact_nested_selection_verified':True,'strict_adhoc_debug_signature_verified':True,'fresh_signed_TCC_matches_csreq':True,'isolated_xctestrun_bytes_verified':True,'spaced_provider_absent_from_argv':True},'raw_log_identity':{'build_bytes':len(build.encode()),'build_sha256':hashlib.sha256(build.encode()).hexdigest(),'tests_bytes':len(log.encode()),'tests_sha256':hashlib.sha256(log.encode()).hexdigest()},'candidate_tested':False,'limits':['Controlled native app pipeline and SwiftData boundary only','Fake editor access and synthetic recognition/provider outputs; no physical/editor UI/ASR/model-quality proof','Old bugs reproduced; candidate fix and cross-run matched comparison remain required','No future Undo gesture, CloudKit synchronization, or general dictation-profile acceptance claim','Raw build/xcresult archive remains on remote /data; no failed-log fetch needed for this successful diagnostic run']}
(retained/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'classification':receipt['classification'],'actual_results':receipt['actual_results'],'artifacts':receipt['artifacts']}))
