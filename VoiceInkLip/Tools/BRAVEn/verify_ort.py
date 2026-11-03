import os
os.environ['OMP_NUM_THREADS']='4'
os.environ['MKL_NUM_THREADS']='4'
os.environ['OPENBLAS_NUM_THREADS']='4'
os.environ['PYTHONDONTWRITEBYTECODE']='1'
import resource
resource.setrlimit(resource.RLIMIT_AS,(8*1024**3,8*1024**3))
from pathlib import Path
import argparse,hashlib,itertools,json,time
import numpy as np
import torch
import onnx
import onnxruntime as ort
ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--disable-optimization',action='store_true')
args=parser.parse_args()
OUT=ROOT/'external'
torch.set_num_threads(4)
torch.set_num_interop_threads(1)
options=ort.SessionOptions()
options.intra_op_num_threads=4
options.inter_op_num_threads=1
if args.disable_optimization:
 options.graph_optimization_level=ort.GraphOptimizationLevel.ORT_DISABLE_ALL
start=time.monotonic()
session=ort.InferenceSession(str(OUT/'visual-ctc.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
load_seconds=time.monotonic()-start
print(json.dumps({'session_load_seconds':load_seconds}),flush=True)
tokens=json.loads((OUT/'tokens.json').read_text())
results=[]
for case in ['a-intact','a-frozen','b-intact','b-frozen','c-intact','c-frozen','dynamic-73']:
 video=torch.load(ROOT/f'{case}-tensor.pt',weights_only=True).numpy()
 expected=torch.load(ROOT/f'{case}-pytorch-logits.pt',weights_only=True).numpy()
 start=time.monotonic()
 actual=session.run(['log_probs'],{'mouth':video})[0]
 elapsed=time.monotonic()-start
 ids=[k for k,_ in itertools.groupby(actual.argmax(-1).reshape(-1).tolist()) if k not in (0,len(tokens)-1)]
 expected_ids=[k for k,_ in itertools.groupby(expected.argmax(-1).reshape(-1).tolist()) if k not in (0,len(tokens)-1)]
 error=np.abs(expected-actual)
 worst=np.unravel_index(int(error.argmax()),error.shape)
 posterior_error=np.abs(np.exp(expected)-np.exp(actual))
 row={'max_probability_abs_error':float(posterior_error.max()),'probability_allclose_atol1e-6_rtol1e-4':bool(np.allclose(np.exp(expected),np.exp(actual),rtol=1e-4,atol=1e-6)),'worst_logprob_index':list(map(int,worst)),'worst_logprob_expected':float(expected[worst]),'worst_logprob_actual':float(actual[worst]),'worst_token':tokens[worst[-1]],'optimization':'disabled' if args.disable_optimization else 'all','frame_argmax_match':bool(np.array_equal(expected.argmax(-1),actual.argmax(-1))),'case':case,'shape':list(actual.shape),'max_abs_error':float(np.max(np.abs(expected-actual))),'mean_abs_error':float(np.mean(np.abs(expected-actual))),'allclose_rtol1e-4_atol1e-4':bool(np.allclose(expected,actual,rtol=1e-4,atol=1e-4)),'decoded_ids_match':ids==expected_ids,'transcript':''.join(tokens[k] for k in ids).replace('▁',' ').strip(),'inference_seconds':elapsed,'peak_rss_kib':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}
 results.append(row);print(json.dumps(row),flush=True)
 (OUT/('parity-no-optimization.json' if args.disable_optimization else 'parity-results.json')).write_text(json.dumps(results,indent=2)+'\n')
 assert row['decoded_ids_match']
manifest=json.loads((OUT/'manifest.json').read_text())
model=onnx.load(str(OUT/'visual-ctc.onnx'),load_external_data=False)
raw_fields=['raw_data','float_data','int32_data','string_data','int64_data','double_data','uint64_data']
assert all(x.data_location==onnx.TensorProto.EXTERNAL and all(not getattr(x,f) for f in raw_fields) for x in model.graph.initializer)
assert len(model.graph.initializer)==len(manifest['initializers'])
receipt={'initializer_count':len(model.graph.initializer),'all_initializers_external':True,'inline_initializer_bytes':0,'external_storage_bytes':manifest['external_storage_bytes'],'largest_fixed_constant_bytes':max(x['bytes'] for x in manifest['constant_tensors']),'dynamic_position_encoding':True,'graph_sha256':manifest['graph_sha256'],'graph_bytes':manifest['graph_bytes'],'onnx':onnx.__version__,'onnxruntime':ort.__version__,'torch':torch.__version__,'cpu_threads':4,'address_space_limit_gib':8,'session_load_seconds':load_seconds,'peak_rss_kib':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}
(OUT/('zero-learned-weight-proof-no-optimization.json' if args.disable_optimization else 'zero-learned-weight-proof.json')).write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt),flush=True)
