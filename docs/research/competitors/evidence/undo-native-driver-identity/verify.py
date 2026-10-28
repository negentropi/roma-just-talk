import argparse,ast,contextlib,copy,hashlib,io,json,subprocess,tempfile,uuid
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',required=True);a=p.parse_args()
repo=Path.cwd();driver='scripts/run-writing-undo-native-check.sh';old_head='0b60c5e62'
old_bytes=subprocess.check_output(['git','show',old_head+':'+driver]);new_bytes=(repo/driver).read_bytes()
old_sha=subprocess.check_output(['git','rev-parse',old_head]).decode().strip()
def digest(raw):return hashlib.sha256(raw).hexdigest()
def load(raw):
 source=raw.decode().split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
 ns={'repo':repo,'output':Path('/inert-evidence')}
 for node in ast.parse(source).body:
  if isinstance(node,(ast.Import,ast.ImportFrom,ast.FunctionDef)):
   exec(compile(ast.Module(body=[node],type_ignores=[]),'<actual-driver-functions>','exec'),ns)
  elif isinstance(node,ast.Assign) and len(node.targets)==1 and isinstance(node.targets[0],ast.Name) and node.targets[0].id!='mode':
   exec(compile(ast.Module(body=[node],type_ignores=[]),'<actual-driver-constants>','exec'),ns)
 return ns
old,new=load(old_bytes),load(new_bytes);captured={}
original=old['observation_errors']
def capture(name,value,*args):
 errors=original(name,value,*args)
 if not errors:captured.setdefault(name,copy.deepcopy(value))
 return errors
old['observation_errors']=capture
with contextlib.redirect_stdout(io.StringIO()):old['self_test']()
old['observation_errors']=original
assert len(captured)==7
negative=old['negative_case'];valid=captured[negative]
assert not original(negative,valid,'/fixture/app',{42}) and not new['observation_errors'](negative,valid,'/fixture/app',{42})
results=[]
for label,field,index,replacement in [('negative-stage-pid','pid',1,101),('negative-stage-token','token',2,'RJT-Writing-Live-00000000-0000-0000-0000-000000000009')]:
 value=copy.deepcopy(valid);value['observations'][index][field]=replacement
 before=old['observation_errors'](negative,value,'/fixture/app',{42});after=new['observation_errors'](negative,value,'/fixture/app',{42})
 assert before==[] and after,(label,before,after)
 results.append({'case':label,'old_accepts_invalid':True,'candidate_accepts_invalid':False,'candidate_errors':after})

def phase_fixture(root):
 names=old['cases'][1:];rows=[];values=[]
 for index,name in enumerate(names):
  value=copy.deepcopy(captured[name]);token='RJT-Writing-Live-'+str(uuid.UUID(int=index+1));pid=100+index
  bundle='com.apple.TextEdit' if name in [old['cases'][1],old['cases'][4]] else 'com.apple.Safari'
  for observation in value['observations']:
   if 'token' in observation:observation.update(token=token,pid=pid)
  if name==negative:
   for diagnostic in value['extra']['deliveryDiagnostics']:diagnostic.update(token=token,pid=pid)
  rows.append({'checkpoint':'fixture-startup','token':token,'bundleIdentifier':bundle,'processIdentifier':pid,'finalStage':'ready','failure':None})
  values.append(value)
 # The other drift window is separately owned but has no case observation.
 rows.append({'checkpoint':'fixture-startup','token':'RJT-Writing-Live-'+str(uuid.UUID(int=20)),'bundleIdentifier':'com.apple.TextEdit','processIdentifier':104,'finalStage':'ready','failure':None})
 def write(name,value):
  path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value))
 write('exit.json',{'test_without_building_exit_code':0})
 (root/'tests.log').write_text('\n'.join('Test '+name+'() started.\nTest '+name+'() passed after 1 second.' for name in names)+'\nTest run with 6 tests in 1 suite passed')
 (root/'host.csreq').write_bytes(b'inert-csreq')
 write('tcc-before.json',[]);write('tcc-after.json',[])
 identifiers=['VoiceInkTests/VoiceInkTests/'+name+'()' for name in names]
 write('selection/receipt.json',{'valid':True,'enabled':identifiers,'requested':identifiers,'disabled':[]})
 for scope in ['discovery','selection']:
  write(scope+'/exit.json',{'enumeration_exit_code':0});write(scope+'/tcc-before.json',[]);write(scope+'/tcc-after.json',[])
  (root/scope/'enumeration.log').write_text('Inert enumeration, no tests executed.\n')
 for value in values:write('observations/'+value['caseName']+'.json',value)
 for index,row in enumerate(rows):write('editor-observations/'+str(index)+'-fixture-startup.json',row)
 return rows

def actual_phase(ns,root):
 # Only OS host closure and TCC are inert boundaries. The exact original/candidate
 # phase_result, observation validators, startup census and JSON reads execute.
 saved={key:ns[key] for key in ['closed_launches','validate_tcc']}
 ns['closed_launches']=lambda directory,host,execution:[{'pid':42,'executable_path':'/fixture/app'}] if execution else []
 ns['validate_tcc']=lambda rows,requirement:True
 try:return ns['phase_result'](root,ns['cases'][1:],{'executable_path':'/fixture/app'})
 finally:ns.update(saved)

for label in ['startup-observation-pid','startup-observation-bundle','unobserved-startup-uuid']:
 with tempfile.TemporaryDirectory(prefix='rjt-native-identity-proof-') as temporary:
  root=Path(temporary);rows=phase_fixture(root)
  assert actual_phase(old,root)['valid'] is True and actual_phase(new,root)['valid'] is True
  if label=='startup-observation-pid':rows[0]['processIdentifier']+=1000
  elif label=='startup-observation-bundle':
   rows[0]['bundleIdentifier'],rows[1]['bundleIdentifier']=rows[1]['bundleIdentifier'],rows[0]['bundleIdentifier']
  else:rows[-1]['token']='RJT-Writing-Live-invalid-uuid'
  for index,row in enumerate(rows):(root/'editor-observations'/f'{index}-fixture-startup.json').write_text(json.dumps(row))
  before=actual_phase(old,root);after=actual_phase(new,root)
  assert before['valid'] is True and after['valid'] is False,(label,before,after)
  results.append({'case':label,'old_accepts_invalid':True,'candidate_accepts_invalid':False,'candidate_errors':after['errors']})
receipt={'classification':'pure-native-driver-identity-regression-verified','baseline_commit':old_sha,'driver_path':driver,
 'baseline_driver_sha256':digest(old_bytes),'candidate_driver_sha256':digest(new_bytes),'valid_protocol_controls_pass_in_both':True,
 'counterexamples':results,'counterexample_count':len(results),
 'boundary':'Actual old/candidate pure validators and phase_result execute on isolated JSON files. Host closure and TCC checks are inert stubs solely to isolate editor identity binding.',
 'limits':['No app build or launch, Accessibility operation, pasteboard access, native result or provider call.','This fixes verification false acceptance only; it does not change or rerun the immutable seven-case app artifact.']}
out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'path':str(out),'bytes':out.stat().st_size,'sha256':digest(out.read_bytes()),'counterexamples':len(results),'baseline_all_accept_invalid':True,'candidate_all_reject_invalid':True,'candidate_driver_sha256':digest(new_bytes)},indent=2))
