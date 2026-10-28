import collections,hashlib,json,pathlib,re,zipfile
root=pathlib.Path('/data/rjt-full-mac-40647571351');base=pathlib.Path('/data/rjt-writing-check-01a17bef/40647571351')
manifest=json.loads((root/'rjt-full-mac-40647571351-preflight.json').read_text());selection=json.loads((root/'rjt-full396-selection.json').read_text())
p=base/'unit-details/details.json';b=p.read_bytes();assert len(b)==4899031 and hashlib.sha256(b).hexdigest()=='e7b472ed6db2e65f79f92ac2821844aa79e751d7e70df1542eb6697202183739';d=json.loads(b);rows=d['case_details'];byid=collections.defaultdict(list)
for c in rows:byid[c['identifier']].append(c)
def get(name):
 a=byid[name];assert len(a)==1;(c,)=a;assert c['status']=='Success' and not [i for i in c['failure_summaries'] if i.get('message')];return {k:c[k] for k in ['identifier','status','summary_reference','summary_member','decoded_summary_sha256','failure_summaries']}
selected=[get(n) for n in selection['selected_44']];correction={k:[get(n) for n in names] for k,names in selection['correction_29'].items()};assert len(selected)==44 and sum(map(len,correction.values()))==29
states={n:{r['status'] for r in a} for n,a in byid.items()};assert all(len(s)==1 for s in states.values());families={}
for fam in ['OnboardingRegionViewTests/','SwiftTesting']:families[fam]=dict(collections.Counter(next(iter(s)) for n,s in states.items() if n.startswith('OnboardingRegionViewTests/')==(fam=='OnboardingRegionViewTests/')))
result={'run_id':40647571351,'head_sha':manifest['head_sha'],'decoded_file_bytes':len(b),'decoded_file_sha256':hashlib.sha256(b).hexdigest(),'aggregate_member':d['aggregate_member'],'all_record_count':len(rows),'all_record_statuses':dict(collections.Counter(c['status'] for c in rows)),'all_unique_identifiers':len(byid),'unique_identifier_statuses_by_family':families,'all_issue_message_count':sum(bool(i.get('message')) for c in rows for i in c['failure_summaries']),'selected_44':selected,'correction_29':correction,'overlap':len(set(selection['selected_44']) & {n for a in selection['correction_29'].values() for n in a})}
(root/'unit-results.json').write_text(json.dumps(result,indent=2)+'\n')
members=['_temp/writing-proof-snapshot/source-sha.txt','_temp/writing-proof-snapshot/verification-mode.json','_temp/writing-feature-regression/contract.txt','_temp/writing-package-proof/candidate-strict-resolve.json','_temp/writing-package-proof/candidate-strict-resolve.log','_temp/writing-package-proof/canonical-graph-contract.json','_temp/writing-package-proof/canonical.Package.resolved','_temp/writing-core-checks.log','_temp/writing-dependency-setup.log']
member_records={}
with zipfile.ZipFile(base/'evidence.zip') as z:
 for name in members:
  data=z.read(name);target=root/'raw'/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data);member_records[name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
 core=z.read('_temp/writing-core-checks.log').decode();passes=re.findall(r'^PASS (.+)$',core,re.M);assert passes==manifest['core_registry'];assert not re.search(r'^FAIL ',core,re.M);assert re.findall(r'^Executed (\d+) VoiceInkCore checks\.$',core,re.M)==['1758']
 lock=z.read('_temp/writing-package-proof/canonical.Package.resolved');assert hashlib.sha256(lock).hexdigest()==manifest['canonical_package_lock_sha256'];pins=json.loads(lock)['pins'];assert pins==manifest['canonical_package_pins'] and len(pins)==41
 resolve=json.loads(z.read('_temp/writing-package-proof/candidate-strict-resolve.json'));assert resolve=={'exit_code':0,'canonical_lock_unchanged':True}
 mode=json.loads(z.read('_temp/writing-proof-snapshot/verification-mode.json'));assert mode=={'sourceSHA':manifest['head_sha'],'mode':'full','fullGateRequired':True};assert z.read('_temp/writing-proof-snapshot/source-sha.txt').decode().strip()==manifest['head_sha']
 absence={'release_build_logs':[n for n in z.namelist() if n.endswith('writing-release-build.log') or n.endswith('release-build.log')],'release_app_hashes':[n for n in z.namelist() if n.endswith('app-sha256.txt')]};assert not any(absence.values())
summary={'run_id':40647571351,'head_sha':manifest['head_sha'],'core_exact_registry_pass_count':len(passes),'canonical_pin_count':len(pins),'canonical_lock_sha256':hashlib.sha256(lock).hexdigest(),'strict_resolution':resolve,'verification_mode':mode,'archive_members':member_records,'release_artifact_absence':absence}
(root/'core-package-results.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({'focusedSuccess':len(selected),'correctionSuccess':sum(map(len,correction.values())),'counts':families,'core':len(passes),'pins':len(pins),'mode':mode,'release':absence},indent=2))
