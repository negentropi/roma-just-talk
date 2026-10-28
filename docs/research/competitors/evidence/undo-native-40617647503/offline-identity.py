import ast,hashlib,json,uuid
from pathlib import Path
root=Path('/data/rjt-writing-check-01a17bef/40617647503')
raw=(root/'driver-5247b9b75.sh').read_bytes()
source=raw.decode().split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
ns={'repo':Path('/inert-source'),'output':root/'compact'}
for node in ast.parse(source).body:
 if isinstance(node,(ast.Import,ast.ImportFrom,ast.FunctionDef)):
  exec(compile(ast.Module(body=[node],type_ignores=[]),'<frozen-5247-driver-functions>','exec'),ns)
 elif isinstance(node,ast.Assign) and len(node.targets)==1 and isinstance(node.targets[0],ast.Name) and node.targets[0].id!='mode':
  exec(compile(ast.Module(body=[node],type_ignores=[]),'<frozen-5247-driver-constants>','exec'),ns)
result={'runtimeHead':'0b60c5e62b84da5888e343dc679eb97b8ec48ef2','offlineCheckerCommit':'5247b9b75','runtimeDriverSHA256':'7d3dc87d117055157064462dab4be06ef67ec1884b7e83d3ed8f8a857670faf4','offlineDriverSHA256':hashlib.sha256(raw).hexdigest(),'scope':'Only frozen pure validators re-evaluate actual immutable compact observations. No app execution or replacement of runtime source provenance.','phases':{}}
for phase,names in ns['phases'].items():
 directory=root/'compact'/phase
 host=json.loads((directory/'host-live.json').read_text())
 pids={item['pid'] for item in host['hosts']}
 startups=[json.loads(path.read_text()) for path in sorted((directory/'editor-observations').glob('*-fixture-startup.json'))]
 errors=ns['editor_startup_errors'](startups,names)
 observations=[];cases={}
 for path in sorted((directory/'observations').glob('*.json')):
  value=json.loads(path.read_text());case_errors=ns['observation_errors'](path.stem,value,host['executable_path'],pids)
  cases[path.stem]=case_errors;errors+=case_errors;observations+=value['observations']
 errors+=ns['editor_identity_errors'](startups,observations)
 result['phases'][phase]={'caseErrors':cases,'startupCount':len(startups),'errors':errors}
result['valid']=all(not phase['errors'] for phase in result['phases'].values())
p=root/'offline-identity-verification.json';p.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'valid':result['valid'],'path':str(p),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}))
if not result['valid']:raise SystemExit(1)
