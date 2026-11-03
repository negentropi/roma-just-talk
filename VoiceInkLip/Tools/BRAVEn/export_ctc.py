import os
os.environ['OMP_NUM_THREADS']='4'
os.environ['MKL_NUM_THREADS']='4'
os.environ['OPENBLAS_NUM_THREADS']='4'
os.environ['PYTHONDONTWRITEBYTECODE']='1'
import resource
resource.setrlimit(resource.RLIMIT_AS,(8*1024**3,8*1024**3))
from pathlib import Path
import itertools,json,math,sys
import numpy as np
import torch
from omegaconf import OmegaConf
ROOT=Path(__file__).resolve().parent
BASE=ROOT.parent
sys.path.insert(0,str(BASE/'upstream'))
from espnet.nets.pytorch_backend.e2e_asr_transformer import E2E
from utils import UNIGRAM1000_LIST

torch.set_num_threads(4)
torch.set_num_interop_threads(1)
torch.manual_seed(42)
class DynamicRelativePosition(torch.nn.Module):
 def __init__(self,original):
  super().__init__();self.d_model=original.d_model;self.xscale=original.xscale;self.dropout=original.dropout
 def forward(self,x):
  time=x.size(1)
  position=torch.arange(time-1,-time,-1,dtype=torch.float32,device=x.device).unsqueeze(1)
  div_term=torch.exp(torch.arange(0,self.d_model,2,dtype=torch.float32,device=x.device)*-(math.log(10000.0)/self.d_model))
  angles=position*div_term
  positional=torch.stack((torch.sin(angles),torch.cos(angles)),dim=-1).flatten(-2).unsqueeze(0)
  return self.dropout(x*self.xscale),self.dropout(positional)
class VisualCTC(torch.nn.Module):
 def __init__(self,model):
  super().__init__();self.encoder=model.encoder;self.ctc=model.ctc
 def forward(self,mouth):
  features,_=self.encoder(mouth,None)
  return self.ctc.log_softmax(features)

def decode(logits):
 ids=[i for i,_ in itertools.groupby(logits.argmax(-1).reshape(-1).tolist()) if i not in (0,len(UNIGRAM1000_LIST)-1)]
 return ''.join(UNIGRAM1000_LIST[i] for i in ids).replace('▁',' ').strip(),ids

backbone=OmegaConf.load(BASE/'upstream/conf/model/visual_backbone/resnet_transformer_large.yaml')
cfg=OmegaConf.create({'model':{'visual_backbone':backbone}});OmegaConf.resolve(cfg)
model=E2E(len(UNIGRAM1000_LIST),cfg.model.visual_backbone)
weights=torch.load(ROOT/'braven-large-self.pth',map_location='cpu',weights_only=True,mmap=True)
model.load_state_dict(weights,strict=True);del weights
wrapper=VisualCTC(model).eval();del model
(ROOT/'tokens.json').write_text(json.dumps(UNIGRAM1000_LIST,ensure_ascii=False,indent=2)+'\n')
sample=torch.load(ROOT/'a-intact-tensor.pt',weights_only=True)
with torch.inference_mode():
 dynamic_sample=sample.repeat(1,2,1,1)[:,:73].contiguous()
 torch.save(dynamic_sample,ROOT/'dynamic-73-tensor.pt')
 torch.save(wrapper(dynamic_sample),ROOT/'dynamic-73-pytorch-logits.pt')
 original_pe=wrapper.encoder.embed[1]
 wrapper.encoder.embed[1]=DynamicRelativePosition(original_pe)
 del original_pe
 wrapper.eval()
 cases=['a-intact','a-frozen','b-intact','b-frozen','c-intact','c-frozen','dynamic-73']
 results=[]
 for case in cases:
  video=torch.load(ROOT/f'{case}-tensor.pt',weights_only=True)
  original=torch.load(ROOT/f'{case}-pytorch-logits.pt',weights_only=True).numpy()
  observed=wrapper(video).numpy()
  text,ids=decode(observed);original_text,original_ids=decode(original)
  row={'case':case,'max_abs_error':float(np.max(np.abs(original-observed))),'allclose_rtol1e-4_atol1e-4':bool(np.allclose(original,observed,rtol=1e-4,atol=1e-4)),'original_text':original_text,'dynamic_text':text,'ids_match':ids==original_ids}
  results.append(row);print(json.dumps(row),flush=True)
  assert row['allclose_rtol1e-4_atol1e-4'] and row['ids_match']
 (ROOT/'dynamic-pe-torch-parity.json').write_text(json.dumps(results,indent=2)+'\n')
 path=ROOT/'visual-ctc-with-weights.onnx'
 torch.onnx.export(wrapper,(sample,),str(path),input_names=['mouth'],output_names=['log_probs'],dynamic_axes={'mouth':{1:'time'},'log_probs':{1:'time'}},opset_version=17,do_constant_folding=False,dynamo=False)
print(json.dumps({'exported_bytes':path.stat().st_size,'visual_parameters':sum(p.numel() for p in wrapper.parameters()),'peak_rss_kib':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}),flush=True)
import onnx
onnx.checker.check_model(str(path))
print('onnx_checker_pass',flush=True)
