import base64,collections,hashlib,json,re,uuid,zipfile,unicodedata
from pathlib import Path
from compression import zstd
RUN=40615667402
HEAD='2454052af441717bd55f57c940d4d6a5c8f94550'
ROOT=Path('/data/rjt-writing-check-01a17bef')/str(RUN)
CASES=[
 'liveWritingUndoTextEditRejectsTerminatedProcess',
 'liveWritingUndoTextEditRestoresExactUnicodeSelection',
 'liveWritingUndoSafariPreservesClipboardWithEitherForwardPreference',
 'liveWritingUndoSafariKeepsNewClipboardGeneration',
 'liveWritingUndoRefusesTextCaretAndWindowDrift',
 'liveWritingUndoLatestOwnerAndCancellation']
PHASES={'process':CASES[:1],'remaining':CASES[1:]}
STAGES=dict(zip(CASES,[
 ['process-before','process-forward','process-terminated','replacement-process-refused'],
 ['unicode1-forward','unicode1-restored','unicode2-forward','unicode2-restored','second-undo-refused'],
 ['restore-on-forward','restore-on-restored','restore-on-clipboard','restore-off-forward','restore-off-current-copy','restore-off-restored','restore-off-clipboard'],
 ['forward','new-copy','restored','clipboard'],
 ['caret-forward','caret-refused','text-forward','text-refused','window-forward','window-refused'],
 ['first-forward','second-forward','canceled-before-attempt','latest-restored','second-undo-refused']]))
CHECKS=dict(zip(CASES,[
 ['differentApplicationInstance','terminatedProcessRejected'],['unicodeAndSelectionRestoredOnce'],
 ['bothForwardPreferencesPreserveCurrentClipboard'],['newClipboardGeneration','newerCopySurvivedBothRestorationOwners'],
 ['sameProcessDifferentWindow','driftNeverRetargetedOrMutated'],
 ['newPendingDeliveryOwnsBusyState','leaseOverlapPreservedPreviousCapability','onlyLatestRewriteWasUndoable']]))

def sha(raw):return hashlib.sha256(raw).hexdigest()
def canonical(identifier):return identifier[:-2] if identifier.endswith('()') else identifier

def parse_tree(data):
 def parse(i):
  assert data[i:i+1]==b'[';i+=1;rows=[]
  while data[i:i+1]!=b']':
   tag=chr(data[i]);i+=1
   if tag=='[':value,i=parse(i-1);rows.append(value)
   elif tag in 'KVS':
    colon=data.index(b':',i);n=int(data[i:colon]);begin=colon+1;i=begin+n;rows.append((tag,data[begin:i].decode()))
   elif tag=='T':rows.append((tag,None))
   else:raise ValueError((tag,i))
  return rows,i+1
 tree,end=parse(0);assert end==len(data);return tree

def fields(node):return {v[1]:node[i+1] for i,v in enumerate(node[:-1]) if isinstance(v,tuple) and v[0]=='K'}
def brief(node):
 if isinstance(node,tuple):return node[1]
 d=fields(node)
 if '_v' in d:return brief(d['_v'])
 if '_values' in d:return brief(d['_values'])
 if d:return {k:brief(v) for k,v in d.items() if k!='_type'}
 return [brief(x) for x in node if isinstance(x,list)]
def cases(node):
 if isinstance(node,dict):
  if 'testStatus' in node:yield node
  for value in node.values():yield from cases(value)
 elif isinstance(node,list):
  for value in node:yield from cases(value)

def units(text):
 raw=text.encode('utf-16-le');return [int.from_bytes(raw[i:i+2],'little') for i in range(0,len(raw),2)]
def span(location,length):return {'location':location,'length':length}
PREFIX='Before 👩🏽‍💻 '
PASSAGE='target e\u0301'
SUFFIX=' after 🧑‍🚀.\n'
ORIGINAL=PREFIX+PASSAGE+SUFFIX
ORIGINAL_RANGE=span(len(units(PREFIX)),len(units(PASSAGE)))
def rewritten(text):return PREFIX+text+SUFFIX
def caret(text):return span(len(units(PREFIX+text)),0)
def expected_editor_states(name):
 if name==CASES[0]:
  replacement='Owned process rewrite 😀'
  return {'process-before':(ORIGINAL,ORIGINAL_RANGE),'process-forward':(rewritten(replacement),caret(replacement)),
          'replacement-process-refused':(ORIGINAL,ORIGINAL_RANGE)}
 if name==CASES[1]:
  first='短い 😀';second='Longer e\u0301 👩🏽‍💻\nSecond paragraph: Roma, 台灣, 🧑‍🚀.'
  return {'unicode1-forward':(rewritten(first),caret(first)),'unicode1-restored':(ORIGINAL,ORIGINAL_RANGE),
          'unicode2-forward':(rewritten(second),caret(second)),'unicode2-restored':(ORIGINAL,ORIGINAL_RANGE),'second-undo-refused':(ORIGINAL,ORIGINAL_RANGE)}
 if name==CASES[2]:
  result={}
  for prefix in ['restore-on','restore-off']:
   replacement='Safari '+prefix+' e\u0301\n😀 literal output'
   result[prefix+'-forward']=(rewritten(replacement),caret(replacement))
   result[prefix+'-restored']=(ORIGINAL,ORIGINAL_RANGE)
  return result
 if name==CASES[3]:
  replacement='Safari replacement e\u0301 😀'
  return {'forward':(rewritten(replacement),caret(replacement)),'restored':(ORIGINAL,ORIGINAL_RANGE)}
 if name==CASES[4]:
  replacement='Drift target e\u0301 😀';user='User typed 🧪 '
  result={stage:(rewritten(replacement),caret(replacement)) for stage in ['caret-forward','text-forward','window-forward','window-refused']}
  result['caret-refused']=(rewritten(replacement),span(0,1))
  result['text-refused']=(user+rewritten(replacement),span(len(units(user)),0))
  return result
 first='first rewrite 😀';second='second, longer e\u0301 👩🏽‍💻'
 selected=span(len(units(PREFIX)),len(units(first)))
 return {'first-forward':(rewritten(first),caret(first)),'second-forward':(rewritten(second),caret(second)),
         'canceled-before-attempt':(rewritten(second),caret(second)),'latest-restored':(rewritten(first),selected),'second-undo-refused':(rewritten(first),selected)}

metadata=json.loads((ROOT/'artifacts-metadata.json').read_text())
archives={kind:zipfile.ZipFile(ROOT/filename) for kind,filename in [('observations','observations.zip'),('evidence','evidence.zip')]}
for kind,z in archives.items():
 meta=metadata[kind]
 path=Path(z.filename)
 assert path.stat().st_size==meta['size_in_bytes']
 assert hashlib.file_digest(path.open('rb'),'sha256').hexdigest()==meta['digest'].removeprefix('sha256:')
 assert z.testzip() is None

def one(kind,suffix,optional=False):
 z=archives[kind]
 if suffix in z.namelist():return suffix
 matches=[n for n in z.namelist() if n.endswith('/'+suffix)]
 if optional and not matches:return None
 assert len(matches)==1,(kind,suffix,matches)
 return matches[0]
def raw(kind,suffix):return archives[kind].read(one(kind,suffix))
def js(kind,suffix):return json.loads(raw(kind,suffix))
def member(kind,suffix):
 name=one(kind,suffix);data=archives[kind].read(name)
 return {'artifact_kind':kind,'zip_member':name,'bytes':len(data),'sha256':sha(data)}
def retain(kind,suffix,filename=None):
 data=raw(kind,suffix);path=ROOT/'small'/ (filename or suffix);path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
 return member(kind,suffix)

contract=js('observations','contract.json')
assert contract['source_sha']==HEAD and int(contract['github_run_id'])==RUN and contract['tests']==CASES and contract['phases']==PHASES
bindings=json.loads((ROOT/'source-bindings.json').read_text())
assert bindings['head_sha']==HEAD
manifest_before=js('observations','source-before.json')
assert manifest_before==json.loads((ROOT/'exact-source-manifest.json').read_text())
assert 'source-after.json' not in archives['observations'].namelist()
for path,item in bindings['paths'].items():
 assert item['exists'] and manifest_before[path]==item['sha256'],path
for path,digest in contract['oracle_sha256'].items():
 assert digest==manifest_before[path]
 assert sha(raw('observations','source/'+Path(path).name))==digest
packages=js('observations','packages-before.json');static=js('observations','static-whisper-before.json')
assert packages['lock_sha256']==contract['lock_sha256']=='bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f'
assert len(packages['revisions'])==len(packages['source_trees'])==len(packages['recursive_gitlinks'])==41
assert packages['revisions']==json.loads((ROOT/'canonical-pins.json').read_text())
assert static and all(re.fullmatch('[a-f0-9]{64}',value) for value in static.values())
host=js('observations','identity-before.json');assert 'identity-after.json' not in archives['observations'].namelist()
assert host['app_files_sha256'] and host['test_files_sha256']
executable=host['executable_path'];app=host['app_path']
app_binary=executable.removeprefix(app+'/')
assert app_binary in host['app_files_sha256']
signature=js('observations','test-host-signature/result.json')
assert signature['classification']=='verified-adhoc-macos-test-host' and signature['strict_deep_verification_passed'] is True and signature['signature']=='adhoc'
assert signature['executable_path']==executable and signature['executable_sha256']==host['app_files_sha256'][app_binary]
assert signature['numeric_code_directory_flags']==int(signature['raw_code_directory_flags'].split('(',1)[0],16)
assert signature['bundle_relative_libraries'] and signature['library_validation_disabled'] is True
receipt={'run_id':RUN,'head_sha':HEAD,'ref':'ci/rjt-writing-undo-native-01a17bef-794fa259','artifacts':metadata,
 'artifact_bytes_sha256_and_all_zip_crc_verified':True,'source_before_matches_exact_committed_manifest':True,'global_source_after_absent_due_to_abort':True,'global_identity_after_absent_due_to_abort':True,'source_manifest_files':len(manifest_before),
 'exact_committed_source_bindings':bindings,'canonical_package_pins':41,'actual_package_revision_and_tree_receipt':member('observations','packages-before.json'),
 'static_whisper_file_count':len(static),'static_whisper_manifest':member('observations','static-whisper-before.json'),
 'signing':signature,'signed_host_designated_requirement':host['designated_requirement'],
 'debug_app_binary_sha256':host['app_files_sha256'][app_binary],
 'app_file_count':len(host['app_files_sha256']),'test_bundle_file_count':len(host['test_files_sha256']),
 'identity_file_manifest_sha256':sha(raw('observations','identity-before.json')),'phases':{},'cases':{},
 'xcresult_decoding':'Linux Python3.14 compression.zstd; complete length-prefixed aggregate/summary parsing. No native execution or Apple signature re-verification performed by auditor.',
 'limits':contract['limits']}
for suffix in ['contract.json','source-before.json','identity-before.json','packages-before.json','static-whisper-before.json','resolved-test-host-settings.json','test-host-signature/result.json','build-command.json']:
 retain('observations',suffix)
for path in contract['oracle_sha256']:retain('observations','source/'+Path(path).name)
launches=[];all_records=[]
SUCCESS={CASES[0],CASES[1],CASES[4]}
for phase,names in PHASES.items():
 directory=phase+'/'
 expected_ids=['VoiceInkTests/VoiceInkTests/'+name for name in names]
 selection=js('observations',directory+'selection/receipt.json')
 assert selection['valid'] is True and len(selection['enabled'])==len(names)
 assert sorted(map(canonical,selection['enabled']))==sorted(expected_ids)
 assert sorted(selection['enabled'])==sorted(selection['requested']) and not set(map(canonical,selection['disabled'])).intersection(expected_ids)
 for scope in ['discovery','selection']:
  enum=js('observations',directory+scope+'/selected-tests.json')
  assert not enum.get('errors')
  assert not re.search(r'\bTest \w+\(\) started\.',raw('observations',directory+scope+'/enumeration.log').decode(errors='replace'))
  enabled=[row['identifier'] for value in enum['values'] for row in value['enabledTests']]
  disabled=[row['identifier'] for value in enum['values'] for row in value.get('disabledTests',[])]
  for expected in expected_ids:
   assert sum(canonical(item)==expected for item in enabled)==1 and expected not in map(canonical,disabled)
  if scope=='selection':assert sorted(map(canonical,enabled))==sorted(expected_ids)
  assert js('observations',directory+scope+'/exit.json')['enumeration_exit_code']==0
 live=js('observations',directory+'host-live.json');closed=js('observations',directory+'host-closed.json')
 assert live['executable_path']==closed['executable_path']==executable and len(live['hosts'])==1
 assert live['hosts']==closed['observed_host_launches']
 launch=live['hosts'][0];pid=launch['pid'];launches.append(launch)
 assert launch['observed_live'] is True and executable in launch['mapped_text_paths'] and launch['executable_path']==executable
 assert closed['host_pids']==[pid] and all(closed[k] is True for k in ['valid','all_observed_hosts_exited','exact_executable_census_empty','exact_executable_has_no_open_descriptors'])
 assert js('observations',directory+'identity-before.json')==js('observations',directory+'identity-after.json')==host
 before=js('observations',directory+'tcc-before.json');after=js('observations',directory+'tcc-after.json')
 assert before==after and len(before)==2
 requirement=raw('evidence',directory+'host.csreq').hex().upper()
 assert {item['service'] for item in before}=={'kTCCServiceAccessibility','kTCCServiceMicrophone'}
 assert all(item['client']=='com.negentropi.RomaJustTalk' and item['client_type']==0 and item['auth_value']==2 and item['requirement']==requirement for item in before)
 enum_launches={}
 for scope in ['discovery','selection']:
  assert js('observations',directory+scope+'/tcc-before.json')==js('observations',directory+scope+'/tcc-after.json')==before
  elive=js('observations',directory+scope+'/host-live.json');eclosed=js('observations',directory+scope+'/host-closed.json')
  assert len(elive['hosts'])<=1 and elive['hosts']==eclosed['observed_host_launches']
  assert elive['executable_path']==eclosed['executable_path']==executable
  assert eclosed['host_pids']==sorted(item['pid'] for item in elive['hosts'])
  assert all(eclosed[k] is True for k in ['valid','all_observed_hosts_exited','exact_executable_census_empty','exact_executable_has_no_open_descriptors'])
  assert all(item['observed_live'] is True and executable in item['mapped_text_paths'] for item in elive['hosts'])
  enum_launches[scope]=elive['hosts']
 log=raw('observations',directory+'tests.log').decode(errors='replace');code=js('observations',directory+'exit.json')['test_without_building_exit_code'];assert code==(0 if phase=='process' else 65)
 starts=re.findall(r'\bTest (\w+)\(\) started\.',log);assert sorted(starts)==sorted(names)
 assert not re.search(r'\bTest \w+\(\) skipped\b|Test session ended prematurely|Testing cancel(?:led|ed)|failed to launch|fatal error:|crashed',log,re.I)
 assert all(re.findall(r'\bTest '+name+r'\(\) (passed|failed|skipped) after ',log)==['passed' if name in SUCCESS else 'failed'] for name in names)
 summaries=re.findall(r'Test run with (\d+) tests? in (\d+) suites? (passed|failed)',log)
 assert len(summaries)==1 and summaries[0][0]==str(len(names)) and int(summaries[0][1])>0 and summaries[0][2]==('passed' if phase=='process' else 'failed')
 z=archives['evidence'];aggregates=[]
 for info in z.infolist():
  if '/'+phase+'/Native.xcresult/Data/' not in '/'+info.filename or '/data.' not in info.filename or info.file_size>2_000_000:continue
  data=z.read(info.filename)
  if data.startswith(bytes.fromhex('28b52ffd')):data=zstd.decompress(data)
  if data.startswith(b'[T[K2:_nV26:ActionTestPlanRunSummaries]'):aggregates.append((info.filename,data,brief(parse_tree(data))))
 assert len(aggregates)==1,(phase,len(aggregates))
 aggregate_name,aggregate_bytes,aggregate=aggregates[0]
 records=[{'identifier':row['identifier'],'status':row['testStatus']} for row in cases(aggregate)]
 assert len(records)==len(names)
 for row in records:
  method=canonical(row['identifier']).split('/')[-1]
  assert row['status']==('Success' if method in SUCCESS else 'Failure')
 assert len({canonical(row['identifier']) for row in records})==len(names)
 for name in names:
  assert sum(canonical(row['identifier']) in {'VoiceInkTests/'+name,'VoiceInkTests/VoiceInkTests/'+name} for row in records)==1
 all_records.extend(records)
 receipt['phases'][phase]={'selection':selection,'actual_xcresult_records':records,'counts':dict(collections.Counter(row['status'] for row in records)),
  'aggregate_member':aggregate_name,'aggregate_decoded_sha256':sha(aggregate_bytes),'test_log':member('observations',directory+'tests.log'),
  'native_execution_launch':launch,'native_execution_host_closed':closed,'enumeration_host_launches':enum_launches,
  'fresh_signed_tcc_rows_before_after_equal':True,'tcc_rows':before,'csreq_sha256':sha(bytes.fromhex(requirement)),'raw_summary':summaries}
 for suffix in ['host-live.json','host-closed.json','identity-before.json','identity-after.json','tcc-before.json','tcc-after.json','configuration.json','exit.json','result.json','selection/receipt.json','discovery/selected-tests.json','selection/selected-tests.json','tests.log']:
  retain('observations',directory+suffix)
 for scope in ['discovery','selection']:
  for suffix in ['host-live.json','host-closed.json','exit.json','tcc-before.json','tcc-after.json','enumeration.log']:
   retain('observations',directory+scope+'/'+suffix)
 for name in names:
  suffix=directory+'observations/'+name+'.json';value=js('observations',suffix)
  assert value['schemaVersion']==1 and value['caseName']==name and value['completed'] is (name in SUCCESS)
  assert value['hostPID']==pid and value['hostExecutablePath']==executable
  required={'completedStages','exactTextObservations','exactRangeObservations','expectedEditorRoutes',*CHECKS[name]}
  if name in SUCCESS:
   assert required.issubset(value['checks']) and all(item is True for item in value['checks'].values())
   assert value['extra']['latestForwardAttempts']==value['extra']['latestForwardConfirmations']==1
  else:
   assert value['checks']=={'expectedEditorRoutes':True}
   assert value['extra']['latestForwardAttempts']==1 and value['extra']['latestForwardConfirmations']==0
  assert all(value['runtimeBounds'].get(key) is item for key,item in {'controllerAPI':True,'productMenuOrShortcut':False,'syntheticProvider':False,'ASR':False}.items())
  diagnostic_rows=value['extra']['deliveryDiagnostics']
  expected_pairs=2 if name==CASES[1] or name==CASES[5] else 3 if name==CASES[4] else 1
  assert len(diagnostic_rows)==2*expected_pairs
  for index in range(expected_pairs):
   before_diag,after_diag=diagnostic_rows[index*2:index*2+2]
   assert before_diag['phase']=='before-capture' and after_diag['phase']=='after-delivery'
   assert before_diag['token']==after_diag['token'] and before_diag['pid']==after_diag['pid']
   assert before_diag['attemptCallbacks']==before_diag['confirmationCallbacks']==0
   assert after_diag['attemptCallbacks']==1
   assert after_diag['outcome']==('attemptedUnconfirmed' if name not in SUCCESS and index==expected_pairs-1 else 'confirmed')
   assert after_diag['confirmationCallbacks']==(0 if after_diag['outcome']=='attemptedUnconfirmed' else 1)
   for diagnostic in [before_diag,after_diag]:
    assert all(diagnostic[key] is True for key in ['currentApplicationInstanceMatches','sameFrontmostApplication','windowPresent','sameEditorWindow','tokenWindowTitle','ownsRetainedSurface','sameGlobalFocusedEditor','sameApplicationFocusedEditor','sameFocusedWindow','globalFocusedElementReturned','globalFocusIsAXElement'])
    assert diagnostic['applicationTerminated'] is False and diagnostic['frontmostPID']==diagnostic['pid']
    assert diagnostic['usesSystemPaste'] is (name in CASES[2:4]+CASES[5:])
    assert all(code==(-25212 if key=='documentURL' and diagnostic['usesSystemPaste'] else 0) for key,code in diagnostic['AXErrors'].items())
    assert diagnostic['observedUTF16'] and all(type(unit) is int and 0<=unit<=65535 for unit in diagnostic['observedUTF16'])
    selected=diagnostic['range'];assert 0<=selected['location']<=len(diagnostic['observedUTF16']) and 0<=selected['length']<=len(diagnostic['observedUTF16'])-selected['location']
    assert diagnostic['selectedUTF16']==diagnostic['observedUTF16'][selected['location']:selected['location']+selected['length']]
   if after_diag['outcome']=='confirmed':
    assert after_diag['undoReceiptPresent'] is True and after_diag['observedUTF16']==after_diag['expectedFullUTF16']
   else:
    error=after_diag['failure'];assert error['description']=='replacementUnconfirmed' and error['type']=='VoiceInk.WritingTarget.Failure'
    expected_bytes=b''.join(unit.to_bytes(2,'little') for unit in after_diag['expectedFullUTF16'])
    expected_text=expected_bytes.decode('utf-16-le')
    assert after_diag['observedUTF16']!=after_diag['expectedFullUTF16']
    assert after_diag['observedUTF16']==units(unicodedata.normalize('NFC',expected_text))
    assert len(after_diag['expectedFullUTF16'])-len(after_diag['observedUTF16'])==1
    assert after_diag['range']==span(len(units(PREFIX))+len(units(unicodedata.normalize('NFC',b''.join(unit.to_bytes(2,'little') for unit in after_diag['outputUTF16']).decode('utf-16-le')))),0)
    assert before_diag['observedUTF16']!=after_diag['observedUTF16']

  stages=value['observations']
  expected_stages=STAGES[name] if name in SUCCESS else ['first-forward'] if name==CASES[5] else []
  assert [item['name'] for item in stages]==expected_stages
  text_count=range_count=clipboard_count=0
  for item in stages:
   if 'expectedUTF16' in item:
    expected,observed=item['expectedUTF16'],item['observedUTF16']
    assert expected==observed and expected and all(type(unit) is int and 0<=unit<=65535 for unit in observed)
    source_text,source_range=expected_editor_states(name)[item['name']]
    assert expected==units(source_text) and item['sourceUTF16']==units(ORIGINAL) and item['range']==source_range
    assert item['range']==item['expectedRange'] and set(item['range'])=={'location','length'}
    assert all(type(v) is int and v>=0 for v in item['range'].values()) and sum(item['range'].values())<=len(observed)
    assert item['sameWindow'] is True and item['windowPresent'] is True
    route=name in CASES[2:4]+CASES[5:]
    assert item['usesSystemPaste'] is route and item['expectedUsesSystemPaste'] is route
    assert item['bundleIdentifier']==('com.apple.Safari' if route else 'com.apple.TextEdit')
    assert item['expectsFocused'] is (item['name']!='window-refused')
    if item['expectsFocused']:assert item['sameProcess'] is True and item['sameFocusedEditor'] is True
    else:assert item['sameFocusedEditor'] is False
    text_count+=1;range_count+=1
   elif 'clipboardExpected' in item:
    assert item['clipboardExpected']==item['clipboardObserved'] and len(item['clipboardExpected'])==2
    assert item['readBeforeCount']==item['readAfterCount']
    names_observed=[];payloads=[]
    for group in item['clipboardObserved']:
     types=[]
     for representation in group['types']:
      decoded=base64.b64decode(representation['dataBase64'],validate=True);assert decoded
      if representation['type']=='com.negentropi.undo-native.binary':assert decoded==bytes([0,255,12,0,128])
      payloads.append((representation['type'],decoded))
      types.append(representation['type'])
     assert sorted(set(types))==types;names_observed.append(types)
    assert names_observed==[sorted(['public.utf8-plain-text','com.negentropi.undo-native.binary']),['com.negentropi.undo-native.second']]
    payload=dict(payloads)
    text=payload['public.utf8-plain-text'].decode('utf-8')
    discriminator=payload['com.negentropi.undo-native.second'].decode('utf-8')
    if name==CASES[2]:
     wanted_text='Forward C e\u0301 🧪' if item['name']=='restore-on-clipboard' else 'New current C after forward 🧑‍🚀'
     wanted_discriminator='restore-on' if item['name']=='restore-on-clipboard' else 'restore-off-current'
     assert text==wanted_text and discriminator==wanted_discriminator
    else:
     assert name==CASES[3] and text.startswith("User's new clipboard ") and discriminator=='new-generation'
     assert str(uuid.UUID(text.removeprefix("User's new clipboard "))).upper()==text.removeprefix("User's new clipboard ")

    clipboard_count+=1
   else:
    assert item['name']=='process-terminated' and item['isTerminated'] is True and item['undoAvailable'] is False
  assert text_count>0 if name in SUCCESS or name==CASES[5] else text_count==0
  assert clipboard_count==0
  if name==CASES[0]:
   termination=value['extra']['processTermination']
   assert termination['terminationAccepted'] is True
   before_termination=termination['before'];after_termination=termination['after']
   assert before_termination['applicationTerminated'] is False
   assert before_termination['bundleApplicationCount']==1 and before_termination['previousWindowCount']==0
   assert before_termination['windowReadAXError']==0 and before_termination['windowReadIsArray'] is True
   assert before_termination['windowCount']==before_termination['tokenWindowCount']==1
   assert all(before_termination[key] is True for key in ['currentApplicationInstanceMatches','exactWindowPresent','previousWindowsPreserved','ownedDocumentURLMatches','ownsFocusedWindow'])
   assert before_termination['confirmedSavedUTF16']==units(rewritten('Owned process rewrite 😀'))
   assert before_termination['actions']=={'saveCommandRequests':1}
   assert after_termination['applicationTerminated'] is True
   assert after_termination['actions']=={'saveCommandRequests':1,'terminationRequests':1}
   assert after_termination['confirmedSavedUTF16']==before_termination['confirmedSavedUTF16']
   by_stage={item['name']:item for item in stages}
   assert by_stage['process-before']['pid']==by_stage['process-forward']['pid']==by_stage['process-terminated']['pid']
   assert by_stage['process-before']['token']==by_stage['process-forward']['token']==by_stage['process-terminated']['token']!=by_stage['replacement-process-refused']['token']
  receipt['cases'][name]={'receipt':member('observations',suffix),'completed':value['completed'],'status':'Success' if name in SUCCESS else 'Failure','hostPID':pid,'actual_stages':[item['name'] for item in stages],
   'checks':value['checks'],'exact_full_utf16_observations':text_count,'exact_selected_range_observations':range_count,'exact_all_format_clipboard_observations':clipboard_count,
   'extra':value['extra'],'runtime_bounds':value['runtimeBounds']}
  retain('observations',suffix)
# Independently inspect the new helper's owned-surface cleanup, not merely the
# unchanged driver's older schema classifier.
helper_cleanup={};helper_startups={}
for archive_name in archives['observations'].namelist():
 if '/editor-observations/' not in '/'+archive_name or not archive_name.endswith('.json'):continue
 payload=json.loads(archives['observations'].read(archive_name))
 if archive_name.endswith('-fixture-startup.json'):
  assert payload['finalStage']=='ready' and payload.get('failure') is None
  helper_startups[payload['token']]={'phase':'process' if '/process/' in '/'+archive_name else 'remaining','payload':payload,'member':archive_name}
 elif '-cleanup-' in archive_name:
  assert payload.get('failure') is None
  helper_cleanup.setdefault(payload['token'],{})[payload['checkpoint']]={'payload':payload,'member':archive_name}
assert len(helper_startups)==len(helper_cleanup)==8
assert sum(row['phase']=='process' for row in helper_startups.values())==2
assert sum(row['payload']['bundleIdentifier']=='com.apple.TextEdit' for row in helper_startups.values())==5
assert sum(row['payload']['bundleIdentifier']=='com.apple.Safari' for row in helper_startups.values())==3
process_value=js('observations','process/observations/'+CASES[0]+'.json')
process_token=process_value['observations'][0]['token']
all_case_payloads=[js('observations',phase+'/observations/'+name+'.json') for phase,names in PHASES.items() for name in names]
last_text={}
for payload in all_case_payloads:
 for item in payload['observations']:
  if 'observedUTF16' in item:last_text[item['token']]=item['observedUTF16']
cleanup_receipt={}
for token,details in helper_cleanup.items():
 startup=helper_startups[token]['payload'];kind=startup['bundleIdentifier']
 if token==process_token:
  assert set(details)=={'before-termination','terminated'}
  before=details['before-termination']['payload'];after=details['terminated']['payload']
  assert before['actions']=={'saveCommandRequests':1} and after['actions']=={'saveCommandRequests':1,'terminationRequests':1}
  assert before['confirmedSavedUTF16']==after['confirmedSavedUTF16']==units(rewritten('Owned process rewrite 😀'))
  assert before['bundleApplicationCount']==1 and before['previousWindowCount']==0 and before['windowCount']==before['tokenWindowCount']==1
  assert before['applicationTerminated'] is False and after['applicationTerminated'] is True
  assert before['windowReadAXError']==0 and before['windowReadIsArray'] is True
  assert all(before[k] is True for k in ['currentApplicationInstanceMatches','exactWindowPresent','previousWindowsPreserved','ownedDocumentURLMatches','ownsFocusedWindow'])
  assert before['processIdentifier']==after['processIdentifier']==process_value['observations'][0]['pid']
  cleanup_receipt[token]={'kind':kind,'route':'one exact retained NSRunningApplication termination after saved bytes; no close command',
   'before':before,'after':after,'raw_members':[details['before-termination']['member'],details['terminated']['member']]}
 else:
  assert set(details)=={'before-close','closed'}
  before=details['before-close']['payload'];after=details['closed']['payload']
  assert before['applicationTerminated'] is False and before['windowReadAXError']==0 and before['windowReadIsArray'] is True
  assert before['tokenWindowCount']==1 and before['windowCount']>=1
  assert all(before[k] is True for k in ['currentApplicationInstanceMatches','exactWindowPresent','previousWindowsPreserved','ownsFocusedWindow'])
  if kind=='com.apple.TextEdit':
   assert before['ownedDocumentURLMatches'] is True
   assert before['actions']=={'saveCommandRequests':1} and after['actions']=={'saveCommandRequests':1,'closeCommandRequests':1}
   expected_final=last_text.get(token,units(ORIGINAL))
   assert before['confirmedSavedUTF16']==after['confirmedSavedUTF16']==expected_final
  else:
   assert kind=='com.apple.Safari' and before['actions']=={} and after['actions']=={'closeCommandRequests':1}
   assert before['confirmedSavedUTF16'] is None and after['confirmedSavedUTF16'] is None
  assert before['processIdentifier']==after['processIdentifier']
  assert before['previousWindowCount']==after['previousWindowCount']
  if after['applicationTerminated']:
   assert after['previousWindowCount']==0
  else:
   assert after['windowReadAXError']==0 and after['windowReadIsArray'] is True and after['tokenWindowCount']==0
   assert after['previousWindowsPreserved'] is True
   if after['exactWindowPresent']:
    assert kind=='com.apple.Safari' and after['previousWindowCount']>0
  cleanup_receipt[token]={'kind':kind,'route':'one CmdW after owned focus; exact saved bytes for TextEdit; previous Safari windows preserved',
   'before':before,'after':after,'raw_members':[details['before-close']['member'],details['closed']['member']]}
 for item in details.values():retain('observations',item['member'])
receipt['owned_editor_fixture_count']=8
receipt['native_termination_fixture_count']=1
receipt['normal_single_cmdw_cleanup_count']=7
safari=[row for row in cleanup_receipt.values() if row['kind']=='com.apple.Safari']
receipt['safari_cleanup_scope']={'fixtures':len(safari),'with_nonempty_previous_windows':sum(row['before']['previousWindowCount']>0 for row in safari),'shared_retained_window_observed_after_close':sum(row['after']['exactWindowPresent'] is True for row in safari),'nonempty_previous_window_preservation_proof':any(row['before']['previousWindowCount']>0 and row['after']['previousWindowsPreserved'] is True for row in safari),'limits':'A true preservation flag with zero prior windows proves only the empty-prior-window scenario.'}
receipt['helper_cleanup_evidence']=cleanup_receipt
receipt['helper_cleanup_limits']='Raw helpers prove owned surface closure/previous-window preservation. Fixture folder removal occurs after closed receipt; no separate post-removal filesystem receipt. Diagnostic document strings are canonical resource representations after typed ownership validation, not raw AX URL spellings.'

assert launches[0]!=launches[1] and len(all_records)==6
assert 'result.json' not in archives['observations'].namelist() and 'complete-result.json' not in archives['observations'].namelist()
assert js('observations','process/result.json')['valid'] is True
assert js('observations','remaining/result.json')['valid'] is False
receipt['original_and_replacement_literals_independently_recomputed_from_frozen_oracle']=True
receipt['clipboard_generation_limit']='No clipboard-observation stage reached; no Safari clipboard preservation or newer-generation survival proof.'
receipt['classification']='mixed-native-3-passed-3-safari-normalized-unconfirmed';receipt['actual_native_case_counts']={'total':6,'passed':3,'failed':3,'skipped':0}
receipt['positive_scope']=['Retained exclusive TextEdit process terminated once after exact save; replacement process cannot reuse old authority.','Two exact Unicode rewrites restored original full text and selection once.','Caret, text and same-process window drift refused Undo without mutating captured text.','All8ownedfixtures safely cleaned:1retainedprocess termination+7singleCmdW; Safari prior-window counts reported explicitly.']
receipt['unresolved_safari_scope']={'actual_observation':'All3failed forwards changed the owned Safari text, returned attemptedUnconfirmed(replacementUnconfirmed), and readback differed solely by NFC composition of requested decomposed e+acute into U+00E9. Caret one UTF16 unit shorter; allfocus/currentapp/window/value/range reads good.', 'confirmed_scope':'Latest first ASCII+emoji rewrite confirmed; second NFD rewrite normalized and remained unconfirmed.', 'safety':'Exact UTF16 authority was withheld; no retry or Undo reached. Canonical equivalence is not exact text authority.', 'native_AX_result':'AXPress return value remains unexposed by the product API; callback count is not its return status.', 'timing_scope':'Fixture removed prior global timeout setter; this is a different diagnostic timing boundary, not proof that the setter caused earlier Safari focus failures.', 'attachments':'Decoded separately; no attachment claim before exact xcresult inspection.'}
receipt['separate_execution_host_launches']=True
receipt['whole_utf16_observations']=sum(row['exact_full_utf16_observations'] for row in receipt['cases'].values())
receipt['clipboard_observations']=sum(row['exact_all_format_clipboard_observations'] for row in receipt['cases'].values())
output=ROOT/'verification.json';output.write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'path':str(output),'bytes':output.stat().st_size,'sha256':sha(output.read_bytes()),'counts':receipt['actual_native_case_counts'],
 'whole_utf16_observations':receipt['whole_utf16_observations'],'clipboard_observations':receipt['clipboard_observations'],
 'source_manifest_files':len(manifest_before),'app_binary_sha256':receipt['debug_app_binary_sha256'],
 'host_pids':[item['pid'] for item in launches],'enumeration_host_pids':{phase:{scope:[item['pid'] for item in rows] for scope,rows in detail['enumeration_host_launches'].items()} for phase,detail in receipt['phases'].items()}},indent=2))
