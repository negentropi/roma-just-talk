from pathlib import Path,PurePosixPath
import hashlib,json,re,stat,zipfile
root=Path('/data/rjt-dictionary-context-40595186584');retained=root/'invalid-retained';retained.mkdir(exist_ok=True)
run=json.loads((root/'run-final.json').read_text());assert run['databaseId']==40595186584 and run['headSha']=='a5601328e66d6949b5de052b81112ffadaeb1d1c' and run['status']=='completed' and run['conclusion']=='cancelled'
metadata=json.loads((root/'artifacts.json').read_text())['artifacts'];expected=json.loads((root/'git-expectations.json').read_text());archives={};members=[]
for kind,name in [('observations','roma.dictionary-context-observations'),('native','roma.dictionary-context-native-evidence')]:
 a=[v for v in metadata if v['name']==name];assert len(a)==1;a=a[0];data=(root/(kind+'.zip')).read_bytes();sha=hashlib.sha256(data).hexdigest();assert len(data)==a['size_in_bytes'] and a['digest']=='sha256:'+sha
 z=zipfile.ZipFile(root/(kind+'.zip'));assert z.testzip() is None;names=z.namelist();assert len(names)==len(set(names))
 for i in z.infolist():
  path=PurePosixPath(i.filename);assert not path.is_absolute() and '..' not in path.parts and not stat.S_ISLNK(i.external_attr>>16)
  if not i.is_dir():members.append({'archive':kind,'path':i.filename,'bytes':i.file_size,'sha256':hashlib.sha256(z.read(i.filename)).hexdigest()})
 archives[kind]={'zip':z,'id':a['id'],'bytes':len(data),'sha256':sha,'crc_members':len(names),'download_count':1}
z=archives['observations']['zip'];assert 'contract.json' in z.namelist()
for lane in ['baseline','candidate']:assert json.loads(z.read(lane+'-source.json'))==expected[lane]['source']
contract=json.loads(z.read('contract.json'));assert contract['source_sha']==expected['candidate']['head'] and contract['baseline_reference_sha']==expected['baseline']['head']
assert contract['oracle_sha256']=='bd935877aca19d689f0c6ca0a99d4cfda2def35548c1040f66217d58fe36579f'
common=z.read('source/DictionaryContextFreshnessTests.swift');assert hashlib.sha256(common).hexdigest()==contract['oracle_sha256']
assert b'        private static func deleteOwnedSetupEntry' in common and b'try #require(DictionaryService.removeWordReplacement(entry, context: context) == nil)' in common
preserved=json.loads(z.read('baseline/source-preservation.json'));assert preserved['all_pinned_tracked_sources_unchanged'] is True and preserved['injected_only_common_oracle'] is True
for lane in ['baseline','candidate']:
 assert not any(n.startswith(lane+'/') and n.endswith(('tests.log','identity-before.json','isolated.xctestrun','selection/receipt.json')) for n in z.namelist())
for i in z.infolist():
 if not i.is_dir():
  out=retained/'observations'/i.filename;out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(z.read(i.filename))
n=archives['native']['zip'];baseline=n.read('dictionary-context-proof/baseline/build.log');candidate=n.read('dictionary-context-proof/candidate/build.log');lines=baseline.decode().splitlines()
errors=[s for s in lines if ' error:' in s];assert len(errors)==11 and all("call to main actor-isolated static method 'removeWordReplacement(_:context:)' in a synchronous nonisolated context" in e for e in errors)
assert not re.search(r'\bTest \w+\(\) started\.',baseline.decode()+candidate.decode())
first=next(i for i,s in enumerate(lines) if ' error:' in s)
(retained/'baseline-compiler-excerpt.txt').write_text('\n'.join(lines[max(0,first-3):first+19])+'\n')
for name in ['run-final.json','artifacts.json']:(retained/name).write_bytes((root/name).read_bytes())
(retained/'artifact-members.json').write_text(json.dumps(members,indent=2)+'\n')
receipt={'run_id':40595186584,'url':run['url'],'head_sha':run['headSha'],'conclusion':'cancelled','classification':'invalid-pretest-actor-isolation-compile-failure','baseline_reference_sha':contract['baseline_reference_sha'],'baseline':{'build_failed':True,'repeated_diagnostics':11,'unique_diagnostic':"call to main actor-isolated static method 'removeWordReplacement(_:context:)' in a synchronous nonisolated context",'actual_common_oracle_sha256':contract['oracle_sha256'],'tracked_baseline_source_equals_git':True,'only_common_oracle_added':True,'native_tests_started':0},'candidate':{'build_cancelled':True,'native_tests_started':0},'artifacts':{k:{key:v[key] for key in ['id','bytes','sha256','crc_members','download_count']} for k,v in archives.items()},'failed_log_request':{'fetch_count':1,'bytes':(root/'failed.log').stat().st_size,'note':'gh --log-failed returned an empty stream for this cancelled run; actual baseline compiler diagnostics were read from the small native evidence archive.'},'raw_build_logs':{'baseline':{'bytes':len(baseline),'sha256':hashlib.sha256(baseline).hexdigest()},'candidate':{'bytes':len(candidate),'sha256':hashlib.sha256(candidate).hexdigest()}},'fix_preparation':{'head':'641dcc6de3341acdffe41fe62f45e074bec749ef','common_oracle_sha256':'3e76e3c168c50c73b028ba564746981cb0a82e5f0371d3a60174cde76b41cd33','change':'Mark setup helper @MainActor and materialize removalAlert before #require; two actual test bodies unchanged. Native retry remains separate.'},'limits':['Zero native tests; neither red bug reproduction nor green candidate proof','Compilation error belongs to the test setup helper, not DictionaryService runtime behavior','No CloudKit synchronization proof','No future Undo or read-only import test attributed to this head']}
(retained/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'classification':receipt['classification'],'native_tests':0,'baseline_errors':len(errors),'artifacts':receipt['artifacts']}))
