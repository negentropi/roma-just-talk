import collections,hashlib,json,pathlib
r=pathlib.Path('/data/rjt-full-mac-40619909088');p=pathlib.Path('/data/rjt-writing-check-01a17bef/40619909088/unit-details/details.json');raw=p.read_bytes();d=json.loads(raw);rows=d['case_details'];m=json.loads((r/'source-registry.json').read_text());old44=json.loads((r/'selected-unit-results.json').read_text());old29=json.loads((r/'correction-group-results.json').read_text())
assert len(raw)==4902220 and hashlib.sha256(raw).hexdigest()=='88e73bc370634a623c344d728301e1b1176a253b95d55aeba0f05aeebbf0aff6'
byid=collections.defaultdict(list)
for x in rows:byid[x['identifier']].append(x)
def get(name):
 a=byid[name];assert len(a)==1,(name,len(a));x=a[0];assert x['status']=='Success' and not [i for i in x['failure_summaries'] if i.get('message')];return {k:x[k] for k in ['identifier','status','summary_reference','summary_member','decoded_summary_sha256','failure_summaries']}
selected=[get(x['identifier']) for x in old44['case_details']];correction={k:[get(x['identifier']) for x in v] for k,v in old29['groups'].items()}
assert len(selected)==44 and sum(map(len,correction.values()))==29
assert len(set(x['identifier'] for x in selected)&set(x['identifier'] for v in correction.values() for x in v))==7
ids={k:{x['status'] for x in v} for k,v in byid.items()};assert all(len(s)==1 for s in ids.values());families={}
for f in ['OnboardingRegionViewTests/','SwiftTesting']:families[f]=dict(collections.Counter(next(iter(v)) for k,v in ids.items() if k.startswith('OnboardingRegionViewTests/')==(f=='OnboardingRegionViewTests/')))
prior_details=json.loads(pathlib.Path('/data/rjt-writing-check-01a17bef/40613521362/unit-details/details.json').read_text())
prior_ids={x['identifier'] for x in prior_details['case_details']}
added=set(ids)-prior_ids;assert len(added)==1;newskip=next(iter(added));assert ids[newskip]=={'Skipped'}
report={'run_id':40619909088,'head_sha':m['head_sha'],'scope':'Selected concrete records from sole-artifact decoded unit xcresult; complete raw record counts independently derived','decoded_file_bytes':len(raw),'decoded_file_sha256':hashlib.sha256(raw).hexdigest(),'aggregate_member':d['aggregate_member'],'all_record_count':len(rows),'all_record_statuses':dict(collections.Counter(x['status'] for x in rows)),'all_unique_identifiers':len(ids),'unique_identifier_statuses_by_family':families,'all_issue_message_count':sum(bool(i.get('message')) for x in rows for i in x['failure_summaries']),'added_gated_case':{'identifier':newskip,'records':len(byid[newskip]),'statuses':list(ids[newskip]),'case_details':byid[newskip]},'selected_44':selected,'correction_29':correction,'overlap':7,'prior_green_run':40613521362,'prior_green_selected_case_identifiers':[x['identifier'] for x in old44['case_details']]}
(r/'unit-results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k not in ['selected_44','correction_29','prior_green_selected_case_identifiers','added_gated_case']},indent=2));print('added',newskip)
