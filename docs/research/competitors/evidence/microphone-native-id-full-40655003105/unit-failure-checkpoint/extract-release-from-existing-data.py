import hashlib,json,pathlib,re,zipfile
r=pathlib.Path('/data/rjt-full-mac-40655003105');base=pathlib.Path('/data/rjt-writing-check-01a17bef/40655003105')
m=json.loads((r/'core-package-results.json').read_text());m['release_artifact_members']=m.pop('release_artifact_absence')
live=(base/'live-details/details.json').read_bytes();assert len(live)==4281
assert hashlib.sha256(live).hexdigest()=='165d31b6e623576e27315bb579f7fb8356af66fe466901865ec2aa257566791b'
d=json.loads(live);assert len(d['case_details'])==len({c['identifier'] for c in d['case_details']})==6
assert all(c['status']=='Success' and not [i for i in c['failure_summaries'] if i.get('message')] for c in d['case_details'])
(r/'native-six-results.json').write_bytes(live)
with zipfile.ZipFile(base/'evidence.zip') as z:
 members=['_temp/writing-release-build.log']+[n for n in z.namelist() if n.endswith(('writing-check-evidence/app-sha256.txt','writing-check-evidence/source-sha.txt'))]
 members += ['_temp/writing-feature-regression/'+s for s in ['result.json','baseline-result.json','candidate-result.json','baseline-tests.log','candidate-tests.log']]
 native_prefix='_temp/writing-proof-snapshot/onboarding-test-evidence/writing-target-live/'
 members += [native_prefix+s for s in ['result.json','tests.log','identity-before.txt','identity-after.txt']]
 for name in members:
  b=z.read(name);p=r/'raw'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b);m['archive_members'][name]={'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
 log=z.read('_temp/writing-release-build.log').decode()
 for required in ['-configuration Release','ENABLE_CODE_COVERAGE=NO','** BUILD SUCCEEDED **','Verified statically linked Whisper app: 8 Mach-O files','Verified ad-hoc Library Validation contract: @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter']:assert required in log,required
 duplicate=[n for n in z.namelist() if n.endswith('writing-check-evidence/release-build.log')]
 assert len(duplicate)==1 and z.read(duplicate[0])==z.read('_temp/writing-release-build.log')
 hash_member=next(n for n in members if n.endswith('app-sha256.txt'));text=z.read(hash_member).decode()
 assert re.fullmatch(r'[a-f0-9]{64}  .+roma\.just\.talk\.app\.zip\n',text);appsha=text.split()[0]
 release={'run_id':40655003105,'head_sha':'0184f9a1552d281cd6b416446b92e091b6bdad29','make_log_member':'_temp/writing-release-build.log','make_log_bytes':len(log.encode()),'make_log_sha256':hashlib.sha256(log.encode()).hexdigest(),'identical_duplicate_make_log_member':duplicate[0],'app_hash_member':hash_member,'recorded_app_zip_sha256':appsha,'xcodebuild_release':True,'coverage_disabled':True,'build_succeeded':True,'static_whisper_macho_count':8,'library_validation_contract':'@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter','postmake_checks_evidence':'Exact workflow source plus successful Release step metadata; stdout not separately retained; no independent packaged-binary inspection'}
 (r/'release-results.json').write_text(json.dumps(release,indent=2)+'\n')
(r/'core-package-results.json').write_text(json.dumps(m,indent=2)+'\n')
print(json.dumps({'native_successes':6,'release':release},indent=2))
