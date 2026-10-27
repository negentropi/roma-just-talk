import hashlib, json, re, stat, sys, textwrap, zipfile
from pathlib import Path, PurePosixPath
root=Path('/data/rjt-polish-ios-40587704440')
expected=json.loads((root/'git-source-expectations.json').read_text())
head=expected['head']; artifact=json.loads((root/'artifacts.json').read_text())['artifacts']
a=[v for v in artifact if v['name']=='roma.none-profile-ios-compile-evidence']; assert len(a)==1
app=[v for v in artifact if v['name']=='roma.none-profile-ios-simulator.app']; assert len(app)==1
a=a[0]; app=app[0]; archive=root/'compile-evidence.zip'; data=archive.read_bytes(); digest=hashlib.sha256(data).hexdigest()
assert len(data)==a['size_in_bytes'] and a['digest']=='sha256:'+digest and not a['expired']
retain=root/'retained';retain.mkdir(exist_ok=True)
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 names=z.namelist(); assert len(names)==len(set(names))
 for i in z.infolist():
  p=PurePosixPath(i.filename); assert not p.is_absolute() and '..' not in p.parts
  assert not stat.S_ISLNK(i.external_attr>>16)
 def get(name):
  xs=[n for n in names if PurePosixPath(n).name==name]; assert len(xs)==1,(name,xs)
  return z.read(xs[0])
 def obj(name): return json.loads(get(name))
 assert get('source-sha.txt').decode().strip()==head
 sources=obj('source-manifest-before.json');assert sources==expected['sources']
 locks=obj('package-locks-before.json');assert set(locks)==set(expected['locks'])
 for name,v in locks.items():
  e=expected['locks'][name];assert v['sha256']==e['sha256'] and v['value']==e['value'],name
 workflow=(root/'workflow.yml').read_text();marker="cat > \"$RUNNER_TEMP/none-ios-proof/pin_contract.py\" <<'PYCODE'\n"
 assert marker in workflow
 helper=textwrap.dedent(workflow.split(marker,1)[1].split('          PYCODE\n',1)[0])
 assert get('pin_contract.py')==helper.encode()
 target='iOS/VoiceInk-ios.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved';mac='VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
 def pins(v):
  p=v['pins'];d={r['identity']:r for r in p};assert len(d)==len(p);return d
 def eq(a,b):return a['identity']==b['identity'] and a['kind']==b['kind'] and a['state']==b['state'] and a['location'].removesuffix('.git')==b['location'].removesuffix('.git')
 original=pins(locks[target]['value']);canonical=pins(locks[mac]['value']);seed=obj('seed-ios.Package.resolved');resolved=obj('resolved-ios.Package.resolved')
 assert len(original)==2 and len(canonical)==41
 for name in set(original)&set(canonical):assert eq(original[name],canonical[name])
 expectedseed=dict(locks[target]['value']);expectedseed['pins']=sorted((canonical|original).values(),key=lambda p:p['identity'])
 assert seed==expectedseed and len(pins(seed))==42
 actual=pins(resolved);allowed=canonical|original
 for name,pin in original.items():assert name in actual and eq(actual[name],pin)
 for name,pin in actual.items():assert name in allowed and eq(allowed[name],pin)
 seedreceipt=obj('package-seed-receipt.json');resolution=obj('package-resolution-receipt.json');after=obj('package-locks-after.json');integrity=obj('source-integrity.json')
 assert seedreceipt['seed_sha256']==hashlib.sha256(get('seed-ios.Package.resolved')).hexdigest()
 assert resolution['resolved_sha256']==hashlib.sha256(get('resolved-ios.Package.resolved')).hexdigest()
 assert resolution['original_pins_preserved']==2 and resolution['resolved_pins']==len(actual) and resolution['all_package_states_match_reviewed_sources'] is True
 assert set(after)==set(locks)
 for name,v in after.items():assert v==(resolution['resolved_sha256'] if name==target else locks[name]['sha256']),name
 assert integrity=={'source_sha':head,'bound_source_files':len(sources),'all_sources_unchanged':True,'allowed_generated_metadata':target,'other_locks_unchanged':True}
 log=get('build.log');text=log.decode(); lines=text.splitlines(); assert text.count('** BUILD SUCCEEDED **')==1 and '** BUILD FAILED **' not in text
 entries=[]
 for source in ['DictationProfile.swift','TranscriptionRunProcessor.swift','DictationPolish.swift']:
  for arch in ['arm64','x86_64']:
   matched=[(i+1,line) for i,line in enumerate(lines) if line.startswith('SwiftCompile normal '+arch+' /') and '/VoiceInkCore/Sources/VoiceInkCore/'+source+' ' in line and "(in target 'VoiceInkCore' from project 'VoiceInkCore')" in line]
   assert len(matched)==1,(source,arch,matched)
   entries.append({'source':source,'architecture':arch,'line':matched[0][0],'text':matched[0][1]})
 sig=get('signature-identity.txt').decode();assert 'Signature=adhoc' in sig and 'Identifier=com.negentropi.RomaJustTalk' in sig
 static=get('static-whisper.log').decode();assert re.fullmatch(r'Verified statically linked Whisper app: [1-9][0-9]* Mach-O files\n?',static)
 config=get('config-verifier.log').decode();assert 'FAIL:' not in config
 excerpt='\n'.join([e['text'] for e in entries]+[line for line in lines if '** BUILD SUCCEEDED **' in line])+'\n';(retain/'build-excerpt.txt').write_text(excerpt)
 omitted={'build.log','dependencies.log','package-resolution.log','metal-download.log'}
 members=[]
 for i in z.infolist():
  if i.is_dir():continue
  n=PurePosixPath(i.filename).name; raw=z.read(i.filename);members.append({'path':i.filename,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'retained':n not in omitted})
  if n not in omitted:(retain/n).write_bytes(raw)
 (retain/'artifact-members.json').write_text(json.dumps(members,indent=2)+'\n')
 run=json.loads((root/'run-final.json').read_text());assert run['databaseId']==40587704440 and run['headSha']==head and run['headBranch']=='ci/rjt-none-ios-check-polish-01a17bef' and run['status']=='completed' and run['conclusion']=='success'
 assert len(run['jobs'])==1 and run['jobs'][0]['conclusion']=='success'
 assert all(s['conclusion'] in ['success','skipped'] for s in run['jobs'][0]['steps'])
 required={'Bind source and dependency locks','Resolve the direct iOS project and validate package metadata','Verify existing iOS configuration contracts','Prepare and verify static Whisper dependencies','Compile the iOS Simulator app and shared Core','Verify the built app and unchanged sources','Upload compile evidence','Upload the verified Simulator app'}
 for name in required: assert sum(s['name']==name and s['conclusion']=='success' for s in run['jobs'][0]['steps'])==1,name
 (retain/'run-final.json').write_text(json.dumps(run,indent=2)+'\n')
 receipt={'run_id':40587704440,'url':run['url'],'head_sha':head,'classification':'ios-simulator-compile-and-static-package-passed','artifact':{'id':a['id'],'bytes':len(data),'sha256':digest,'crc_members':len(members),'download_count':1,'remote_archive':str(archive)},'simulator_app_artifact':{k:app[k] for k in ['id','name','size_in_bytes','digest']},'simulator_app_downloaded':False,'source_checks':{'bound_sources':len(sources),'source_hashes_match_git':True,'original_lock_files':len(locks),'all_original_lock_values_match_git':True,'all_sources_unchanged':True,'allowed_generated_metadata':target,'artifact_pin_contract_equals_pinned_workflow':True},'dependencies':{'original_pins_preserved':len(original),'canonical_mac_pins':len(canonical),'seed_pins':42,'resolved_pins':len(actual),'all_states_and_repositories_match_reviewed_sources':True,'repository_equivalence':'Optional terminal .git suffix only','resolved_sha256':resolution['resolved_sha256']},'build':{'configuration':'Debug','destination':'generic/platform=iOS Simulator','architectures':['arm64','x86_64'],'actual_core_compile_entries':entries,'succeeded_markers':1,'raw_log_bytes':len(log),'raw_log_sha256':hashlib.sha256(log).hexdigest(),'signed_app':'Ad-hoc; deep strict verification completed successfully','executable_sha256_receipt':get('executable-sha256.txt').decode().strip(),'inner_app_archive_sha256_receipt':get('app-archive-sha256.txt').decode().strip()},'limits':['Compilation and static package validation only','No Simulator launch, native runtime tests, microphone, keyboard, device, or iOS Light/Clarity feature proof','Actual Simulator app archive not downloaded; its artifact and inner digest are metadata/CI receipts only','No full runtime dependency checkout/tree census retained by this workflow']}
 (retain/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print(json.dumps({'classification':receipt['classification'],'sources':len(sources),'locks':len(locks),'pins':len(actual),'members':len(members),'compile_entries':len(entries),'artifact_bytes':len(data),'artifact_sha256':digest,'retained':str(retain)}))
