import hashlib,json,plistlib,re,stat,zipfile
from pathlib import Path,PurePosixPath
root=Path('/data/rjt-dictionary-context-40602009529');retained=root/'retained';retained.mkdir(exist_ok=True)
expected=json.loads((root/'git-expectations.json').read_text());run=json.loads((root/'run-final.json').read_text());artifacts=json.loads((root/'artifacts.json').read_text())['artifacts']
assert run['databaseId']==40602009529 and run['headSha']==expected['candidate']['head'] and run['headBranch']=='ci/rjt-dictionary-context-check-01a17bef' and run['status']=='completed' and run['conclusion']=='success'
archives={};member_receipts=[]
for kind,name in [('observations','roma.dictionary-context-observations'),('native','roma.dictionary-context-native-evidence')]:
 found=[a for a in artifacts if a['name']==name];assert len(found)==1;meta=found[0];path=root/(kind+'.zip');data=path.read_bytes();sha=hashlib.sha256(data).hexdigest();assert len(data)==meta['size_in_bytes'] and meta['digest']=='sha256:'+sha and not meta['expired']
 z=zipfile.ZipFile(path);assert z.testzip() is None;names=z.namelist();assert len(names)==len(set(names))
 for i in z.infolist():
  p=PurePosixPath(i.filename);assert not p.is_absolute() and '..' not in p.parts and not stat.S_ISLNK(i.external_attr>>16)
  if not i.is_dir():member_receipts.append({'archive':kind,'path':i.filename,'bytes':i.file_size,'sha256':hashlib.sha256(z.read(i.filename)).hexdigest()})
 archives[kind]={'zip':z,'meta':meta,'sha':sha,'bytes':len(data),'members':len([i for i in z.infolist() if not i.is_dir()])}
for kind,suffix in [('observations','contract.json'),('native','baseline/build.log')]:
 names=archives[kind]['zip'].namelist();matches=[n for n in names if n==suffix or n.endswith('/'+suffix)];assert len(matches)==1,(kind,matches)
 archives[kind]['prefix']=matches[0][:-len(suffix)]
def raw(path,kind='observations'):
 z=archives[kind]['zip'];name=archives[kind]['prefix']+path;assert name in z.namelist(),(kind,path);return z.read(name)
def obj(path,kind='observations'):return json.loads(raw(path,kind))
def save(path,data):
 p=retained/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
contract=obj('contract.json');assert contract['source_sha']==expected['candidate']['head'] and contract['baseline_reference_sha']==expected['baseline']['head']
assert contract['oracle_sha256']=='3e76e3c168c50c73b028ba564746981cb0a82e5f0371d3a60174cde76b41cd33'
for lane in ['baseline','candidate']:
 assert obj(lane+'-source.json')==expected[lane]['source']
 assert obj(lane+'/source-after.json')==expected[lane]['source']
 source=raw('source/'+lane+'-dictionary.swift');assert hashlib.sha256(source).hexdigest()==expected[lane]['source']['VoiceInk/Services/DictionaryService.swift']
 assert contract[lane+'_service_sha256']==hashlib.sha256(source).hexdigest()
 if lane=='baseline':assert b'cachedWordReplacementRules' in source
 else:assert b'cachedWordReplacementRules' not in source
assert obj('baseline/source-preservation.json')['all_pinned_tracked_sources_unchanged'] is True and obj('baseline/source-preservation.json')['injected_only_common_oracle'] is True
source_paths={'DictionaryContextFreshnessTests.swift':'VoiceInkTests/DictionaryContextFreshnessTests.swift','run-dictionary-context-regression.sh':'scripts/run-dictionary-context-regression.sh','voiceink-dictionary-context-check.yml':'.github/workflows/voiceink-dictionary-context-check.yml','verify-adhoc-macos-test-host.sh':'scripts/verify-adhoc-macos-test-host.sh','verify-adhoc-macos-test-host.test.sh':'scripts/tests/verify-adhoc-macos-test-host.test.sh'}
for name,path in source_paths.items():
 assert hashlib.sha256(raw('source/'+name)).hexdigest()==expected['candidate']['source'][path]
for name,sha in contract['helper_sha256'].items():assert expected['candidate']['source'][name]==sha
cases={'applyingAnotherStoreNeverReusesThePreviousStoresRules':('First store','Second store'),'aFreshContextReadsChangesSavedByAnotherContext':('First value','Second value')}
oracle=raw('source/DictionaryContextFreshnessTests.swift').decode();sites={int(k):v for k,v in contract['expected_baseline_assertions'].items()};assert len(sites)==2
for line,site in sites.items():assert site['test'] in cases and '#expect('+site['expression']+')' in oracle.splitlines()[line-1]
for lane in ['baseline','candidate']:
 log=raw(lane+'/tests.log').decode();desired='failed' if lane=='baseline' else 'passed';code=65 if lane=='baseline' else 0
 assert sorted(re.findall(r'\bTest (\w+)\(\) started\.',log))==sorted(cases)
 assert obj(lane+'/exit.json')['test_without_building_exit_code']==code
 for case in cases:assert re.findall(r'\bTest '+case+r'\(\) (passed|failed|skipped) after ',log)==[desired]
 summaries=re.findall(r'Test run with (\d+) tests? in (\d+) suites? (passed|failed)',log);assert len(summaries)==1 and summaries[0][0]=='2' and int(summaries[0][1])>0 and summaries[0][2]==desired
 issues=[s for s in log.splitlines() if re.search(r'\brecorded an issue\b',s)]
 assert len(issues)==(2 if lane=='baseline' else 0)
 seen=[]
 for issue in issues:
  match=re.search(r'\bTest (\w+)\(\) recorded an issue at (.+):(\d+):\d+:.*Expectation failed:',issue);assert match
  method,file,line=match[1],match[2],int(match[3]);assert PurePosixPath(file).name=='DictionaryContextFreshnessTests.swift' and line in sites and sites[line]['test']==method
  assert all(value in issue for value in cases[method]);seen.append(line)
 assert sorted(seen)==(sorted(sites) if lane=='baseline' else [])
 assert not re.search(r'\b(?:crashed|crash report|unexpected exit|Testing cancelled|Test session ended prematurely|failed to launch|fatal error:)',log,re.I)
 assert not re.search(r'^(?:[^\n]*\.swift:\d+(?::\d+)?:\s*error:|\s*(?:xcodebuild|clang):\s*error:)',log,re.I|re.M)
 verdict=obj(lane+'/result.json');assert verdict['valid'] and verdict['exit_code']==code and not verdict['errors']
 before=obj(lane+'/identity-before.json');assert before==obj(lane+'/identity-after.json') and before['bundle_identifier']=='com.negentropi.RomaJustTalk'
 assert before['app_files_sha256'] and len(before['test_bundle_sha256'])==64
 selection=obj(lane+'/selection/receipt.json');assert selection['valid'] and sorted(selection['requested'])==sorted(selection['enabled']) and len(selection['requested'])==2
 for method in cases:assert len([n for n in selection['enabled'] if n.endswith('/'+method+'()') and 'DictionaryContextFreshnessTests' in n])==1
 assert not set(selection['requested'])&set(selection['disabled'])
 sign=obj(lane+'/test-host-signature/result.json');assert sign['classification']=='verified-adhoc-macos-test-host' and sign['signature']=='adhoc' and sign['strict_deep_verification_passed'] is True
 assert sign['executable_sha256']==before['app_files_sha256']['Contents/MacOS/roma just talk']
 if sign['bundle_relative_libraries']:assert sign['library_validation_disabled'] is True
 ent=plistlib.loads(raw(lane+'/test-host-signature/entitlements.plist'));assert ent.get('com.apple.security.cs.disable-library-validation') is True
 requirement=raw(lane+'/host-requirement.txt').decode().strip();assert requirement==before['designated_requirement']
 csreq=raw(lane+'/host.csreq','native');tcc=obj(lane+'/tcc.json');assert len(tcc)==2 and {r['service'] for r in tcc}=={'kTCCServiceAccessibility','kTCCServiceMicrophone'}
 assert all(r['client']=='com.negentropi.RomaJustTalk' and r['auth_value']==2 and r['requirement']==csreq.hex().upper() for r in tcc)
 cfg=raw(lane+'/isolated.xctestrun','native');configuration=obj(lane+'/configuration.json');assert hashlib.sha256(cfg).hexdigest()==configuration['isolated_sha256']
 value=plistlib.loads(cfg)
 if 'TestConfigurations' in value:targets=[t for c in value['TestConfigurations'] for t in c['TestTargets']]
 else:targets=[v for k,v in value.items() if not k.startswith('__')]
 assert len(targets)==1;target=targets[0]
 assert target.get('BlueprintName','VoiceInkTests')=='VoiceInkTests' and target['ParallelizationEnabled'] is False
 assert target['CommandLineArguments']==configuration['command_line_arguments']
 assert target['EnvironmentVariables']['CFFIXED_USER_HOME']==configuration['isolated_user_home']
 assert target['EnvironmentVariables']['GITHUB_ACTIONS']=='true' and target['EnvironmentVariables']['RUNNER_ENVIRONMENT']=='github-hosted'
 assert 'VoiceInkTests.xctest' in target['TestBundlePath'] and 'roma just talk.app' in target['TestHostPath']
 settings=obj(lane+'/build-settings.json');settings=[s['buildSettings'] for s in settings if s.get('target')=='VoiceInk'];assert len(settings)==1
 assert 'LOCAL_BUILD' in settings[0]['SWIFT_ACTIVE_COMPILATION_CONDITIONS'].split() and all(settings[0][k]=='NO' for k in ['ENABLE_DEBUG_DYLIB','ENABLE_PREVIEWS'])
 build=raw(lane+'/build.log','native').decode();compilelines=[s for s in build.splitlines() if re.search(r'(?:SwiftCompile|CompileSwiftSources)[^\n]*DictionaryService\.swift',s)];assert compilelines and '** TEST BUILD SUCCEEDED **' in build
 save(lane+'/build-excerpt.txt',('\n'.join(compilelines+['** TEST BUILD SUCCEEDED **'])+'\n').encode());save(lane+'/isolated.xctestrun',cfg);save(lane+'/host.csreq',csreq);save(lane+'/build-settings.json',raw(lane+'/build-settings.json'))
for suffix in ['packages-before.json','static-whisper-before.json']:assert raw('baseline/'+suffix)==raw('candidate/'+suffix)
packages=obj('candidate/packages-before.json');assert len(packages['revisions'])==len(packages['clean_tracked_source_trees'])==41 and packages['canonical_lock_sha256']==contract['canonical_lock_sha256']
canonical_bytes=raw('packages/canonical.Package.resolved');assert hashlib.sha256(canonical_bytes).hexdigest()==contract['canonical_lock_sha256']==expected['candidate']['source']['VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']
canonical=json.loads(canonical_bytes)['pins'];assert len(canonical)==41 and len({p['identity'] for p in canonical})==41 and packages['revisions']=={p['identity']:p['state']['revision'] for p in canonical}
assert set(packages['clean_tracked_source_trees'])==set(packages['revisions']) and all(re.fullmatch('[0-9a-f]{40}',v) for v in packages['clean_tracked_source_trees'].values())
whisper=obj('candidate/static-whisper-before.json');assert len(whisper)>0 and all(len(v)==64 for v in whisper.values())
result=obj('result.json');assert result['classification']=='matched-red-green' and result['source_sha']==expected['candidate']['head'] and result['contract_sha256']==hashlib.sha256(raw('contract.json')).hexdigest() and result['oracle_sha256']==contract['oracle_sha256']
for lane in ['baseline','candidate']:assert result[lane]==obj(lane+'/result.json')
for i in archives['observations']['zip'].infolist():
 if not i.is_dir():save('observations/'+i.filename.removeprefix(archives['observations']['prefix']),archives['observations']['zip'].read(i.filename))
save('artifact-members.json',(json.dumps(member_receipts,indent=2)+'\n').encode());save('run-final.json',(json.dumps(run,indent=2)+'\n').encode());save('artifacts.json',(json.dumps(artifacts,indent=2)+'\n').encode())
receipt={'run_id':40602009529,'url':run['url'],'head_sha':expected['candidate']['head'],'baseline_sha':expected['baseline']['head'],'classification':'matched-native-dictionary-context-red-green','artifacts':{k:{'id':v['meta']['id'],'bytes':v['bytes'],'sha256':v['sha'],'crc_members':v['members'],'download_count':1} for k,v in archives.items()},'source_checks':{'baseline_tracked_files':len(expected['baseline']['source']),'candidate_tracked_files':len(expected['candidate']['source']),'both_full_tracked_manifests_equal_pinned_git':True,'source_after_equal_before':True,'baseline_only_untracked_injection':contract['baseline_only_injected_path'],'common_oracle_sha256':contract['oracle_sha256'],'canonical_packages':len(packages['revisions']),'static_whisper_files':len(whisper),'both_lanes_dependency_bytes_equal':True},'native_results':{'baseline':obj('baseline/result.json'),'candidate':obj('candidate/result.json')},'identity':{'each_lane_full_app_files_and_test_bundle_unchanged':True,'fresh_signed_TCC_grants_match_csreq':True,'isolated_xctestrun_bytes_verified':True,'actual_build_settings_LOCAL_BUILD':True,'raw_code_directory_flags':{lane:obj(lane+'/test-host-signature/result.json')['raw_code_directory_flags'] for lane in ['baseline','candidate']}},'limits':['Actual per-store/per-context DictionaryService cache behavior only','Synthetic normal app-host SwiftData fixtures; no physical input or ASR','No CloudKit synchronization proof','No future Undo or additional read-only import regression attributed to this head','Raw build logs and xcresults remain in original remote /data native archive']}
save('receipt.json',(json.dumps(receipt,indent=2)+'\n').encode());print(json.dumps({k:receipt[k] for k in ['classification','source_checks','artifacts']}))
