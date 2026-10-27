from pathlib import Path,PurePosixPath
import hashlib,json,re,stat,zipfile,plistlib
root=Path('/data/rjt-dictionary-context-40599068412');retained=root/'partial-retained';retained.mkdir(exist_ok=True)
run=json.loads((root/'run-final.json').read_text());assert run['databaseId']==40599068412 and run['headSha']=='641dcc6de3341acdffe41fe62f45e074bec749ef' and run['conclusion']=='failure' and run['status']=='completed'
metadata=json.loads((root/'artifacts.json').read_text())['artifacts'];expected=json.loads((root/'git-expectations.json').read_text());archives={};members=[]
for kind,name,suffix in [('observations','roma.dictionary-context-observations','contract.json'),('native','roma.dictionary-context-native-evidence','baseline/build.log')]:
 a=[v for v in metadata if v['name']==name];assert len(a)==1;a=a[0];data=(root/(kind+'.zip')).read_bytes();sha=hashlib.sha256(data).hexdigest();assert len(data)==a['size_in_bytes'] and a['digest']=='sha256:'+sha
 z=zipfile.ZipFile(root/(kind+'.zip'));assert z.testzip() is None;names=z.namelist();assert len(names)==len(set(names));matches=[n for n in names if n==suffix or n.endswith('/'+suffix)];assert len(matches)==1
 for i in z.infolist():
  p=PurePosixPath(i.filename);assert not p.is_absolute() and '..' not in p.parts and not stat.S_ISLNK(i.external_attr>>16)
  if not i.is_dir():members.append({'archive':kind,'path':i.filename,'bytes':i.file_size,'sha256':hashlib.sha256(z.read(i.filename)).hexdigest()})
 archives[kind]={'zip':z,'id':a['id'],'bytes':len(data),'sha256':sha,'crc_members':len(names),'download_count':1,'prefix':matches[0][:-len(suffix)]}
def raw(path,kind='observations'):return archives[kind]['zip'].read(archives[kind]['prefix']+path)
def obj(path,kind='observations'):return json.loads(raw(path,kind))
contract=obj('contract.json');assert contract['source_sha']==expected['candidate']['head'] and contract['baseline_reference_sha']==expected['baseline']['head'] and contract['oracle_sha256']=='3e76e3c168c50c73b028ba564746981cb0a82e5f0371d3a60174cde76b41cd33'
for lane in ['baseline','candidate']:assert obj(lane+'-source.json')==expected[lane]['source']
assert obj('baseline/source-after.json')==expected['baseline']['source'];pres=obj('baseline/source-preservation.json');assert pres['all_pinned_tracked_sources_unchanged'] is True and pres['injected_only_common_oracle'] is True
assert hashlib.sha256(raw('source/DictionaryContextFreshnessTests.swift')).hexdigest()==contract['oracle_sha256']
for name,sha in contract['helper_sha256'].items():assert sha==expected['candidate']['source'][name]
for lane in ['baseline','candidate']:assert hashlib.sha256(raw('source/'+lane+'-dictionary.swift')).hexdigest()==contract[lane+'_service_sha256']==expected[lane]['source']['VoiceInk/Services/DictionaryService.swift']
cases={'applyingAnotherStoreNeverReusesThePreviousStoresRules':(20,'First store','Second store'),'aFreshContextReadsChangesSavedByAnotherContext':(41,'First value','Second value')}
log=raw('baseline/tests.log').decode();assert sorted(re.findall(r'\bTest (\w+)\(\) started\.',log))==sorted(cases)
for name in cases:assert re.findall(r'\bTest '+name+r'\(\) (passed|failed|skipped) after ',log)==['failed']
issues=[s for s in log.splitlines() if 'recorded an issue' in s];assert len(issues)==2
for name,(line,wrong,right) in cases.items():assert sum(name in s and 'DictionaryContextFreshnessTests.swift:'+str(line)+':13:' in s and wrong in s and right in s for s in issues)==1
assert re.findall(r'Test run with (\d+) tests in (\d+) suites failed',log)==[('2','2')]
verdict=obj('baseline/result.json');assert verdict['valid'] and not verdict['errors'] and verdict['exit_code']==65 and verdict['classification']=='intended-stale-dictionary-failures'
assert obj('baseline/exit.json')['test_without_building_exit_code']==65
before=obj('baseline/identity-before.json');assert before==obj('baseline/identity-after.json');selection=obj('baseline/selection/receipt.json');assert selection['valid'] and len(selection['requested'])==2 and sorted(selection['requested'])==sorted(selection['enabled']) and not set(selection['requested'])&set(selection['disabled'])
sign=obj('baseline/test-host-signature/result.json');assert sign['signature']=='adhoc' and sign['strict_deep_verification_passed'] and sign['executable_sha256']==before['app_files_sha256']['Contents/MacOS/roma just talk']
csreq=raw('baseline/host.csreq','native');tcc=obj('baseline/tcc.json');assert len(tcc)==2 and all(r['auth_value']==2 and r['requirement']==csreq.hex().upper() for r in tcc)
cfg=raw('baseline/isolated.xctestrun','native');assert hashlib.sha256(cfg).hexdigest()==obj('baseline/configuration.json')['isolated_sha256']
assert raw('baseline/packages-before.json')==raw('candidate/packages-before.json') and raw('baseline/static-whisper-before.json')==raw('candidate/static-whisper-before.json')
packages=obj('baseline/packages-before.json');canonical_bytes=raw('packages/canonical.Package.resolved');assert hashlib.sha256(canonical_bytes).hexdigest()==contract['canonical_lock_sha256'];pins=json.loads(canonical_bytes)['pins'];assert len(pins)==41 and packages['revisions']=={p['identity']:p['state']['revision'] for p in pins}
basebuild=raw('baseline/build.log','native').decode();assert '** TEST BUILD SUCCEEDED **' in basebuild and re.search(r'SwiftCompile[^\n]*DictionaryService\.swift',basebuild)
candbuild=raw('candidate/build.log','native');errors=[s for s in candbuild.decode().splitlines() if ' error:' in s];assert len(errors)==14 and all('CorrectionLibraryStoreUpgradeLiveTests.swift:89:59: error: property access can throw but is not marked with' in e for e in errors)
assert not any(n.endswith('candidate/tests.log') for n in archives['observations']['zip'].namelist());assert '** TEST BUILD FAILED **' in candbuild.decode()
for i in archives['observations']['zip'].infolist():
 if not i.is_dir():
  out=retained/'observations'/i.filename.removeprefix(archives['observations']['prefix']);out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(archives['observations']['zip'].read(i.filename))
lines=candbuild.decode().splitlines();index=next(i for i,s in enumerate(lines) if ' error:' in s);(retained/'candidate-compiler-excerpt.txt').write_text('\n'.join(lines[max(0,index-3):index+18])+'\n')
(retained/'baseline-build-excerpt.txt').write_text('\n'.join([s for s in basebuild.splitlines() if s.startswith('SwiftCompile') and 'DictionaryService.swift' in s]+['** TEST BUILD SUCCEEDED **'])+'\n')
for name in ['run-final.json','artifacts.json','failed.log']:(retained/name).write_bytes((root/name).read_bytes())
(retained/'baseline-isolated.xctestrun').write_bytes(cfg);(retained/'baseline-host.csreq').write_bytes(csreq)
(retained/'artifact-members.json').write_text(json.dumps(members,indent=2)+'\n')
receipt={'run_id':40599068412,'url':run['url'],'head_sha':run['headSha'],'classification':'valid-native-baseline-red-candidate-pretest-compile-failure','baseline_reference_sha':contract['baseline_reference_sha'],'artifacts':{k:{key:v[key] for key in ['id','bytes','sha256','crc_members','download_count']} for k,v in archives.items()},'source_checks':{'candidate_tracked_files_match_git':len(expected['candidate']['source']),'baseline_tracked_files_match_git':len(expected['baseline']['source']),'historical_runtime_unchanged':True,'only_common_oracle_injected':contract['oracle_path'],'common_oracle_sha256':contract['oracle_sha256'],'canonical_packages':41,'both_lanes_package_and_static_whisper_inputs_identical':True},'baseline':{'native_tests_started':2,'native_tests_failed':2,'native_issues':issues,'classification':verdict['classification'],'source_bound_final_assertions_only':True,'setup_and_other_positive_controls_passed':True,'app_files_and_test_bundle_unchanged':True,'strict_adhoc_debug_signature_verified':True,'fresh_signed_TCC_matches_csreq':True,'isolated_launch_configuration_hash_verified':True},'candidate':{'native_tests_started':0,'test_build_failed':True,'repeated_diagnostics':14,'unique_error':'CorrectionLibraryStoreUpgradeLiveTests.swift:89:59: property access can throw but is not marked with try','missing_exit_json_is_follow_on_failure':True},'failed_log_fetch_count':1,'raw_build_logs':{'baseline':{'bytes':len(basebuild.encode()),'sha256':hashlib.sha256(basebuild.encode()).hexdigest()},'candidate':{'bytes':len(candbuild),'sha256':hashlib.sha256(candbuild).hexdigest()}},'followup':{'head':'907fe27d566a7b4c8de2c7b754015ba2f6994d7f','change':'Materialize try compatibility.voiceInkRule before constructing the rule array; actual retry separate.'},'limits':['Old per-store/per-context cache bugs reproduced in a controlled native app host','Candidate compilation failed before native execution; no passing fix or full matched result','No CloudKit synchronization, physical input, ASR, future Undo or read-only import behavior proof','Raw build logs and xcresults retained only in original remote /data archives']}
(retained/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'classification':receipt['classification'],'baseline_issues':len(issues),'candidate_native':0,'artifacts':receipt['artifacts']}))
