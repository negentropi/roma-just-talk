import os
os.environ['OMP_NUM_THREADS']='4'
os.environ['MKL_NUM_THREADS']='4'
os.environ['OPENBLAS_NUM_THREADS']='4'
os.environ['PYTHONDONTWRITEBYTECODE']='1'
import resource
resource.setrlimit(resource.RLIMIT_AS,(8*1024**3,8*1024**3))
from pathlib import Path
from dataclasses import dataclass
from collections import OrderedDict
import argparse,hashlib,io,itertools,json,math,pickle,re,zipfile
import numpy as np
import onnx
from onnx.external_data_helper import set_external_data

ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--graph',default='visual-ctc-with-weights.onnx')
parser.add_argument('--output-dir',default='external')
parser.add_argument('--dynamic-position',action='store_true')
args=parser.parse_args()
CHECKPOINT=ROOT/'braven-large-self.pth'
CHECKPOINT_SHA='8dd3bbf4e8d6287e87e7c3d9bc65f6238b4d75b12040e10f5589e3c6e76bda8f'
with CHECKPOINT.open('rb') as checkpoint_stream:
    assert hashlib.file_digest(checkpoint_stream,'sha256').hexdigest()==CHECKPOINT_SHA
@dataclass
class StorageKind:
    name:str
    width:int
@dataclass
class StorageRef:
    key:str
    kind:StorageKind
    count:int
@dataclass
class TensorRef:
    storage:StorageRef
    offset:int
    shape:tuple
    stride:tuple

def rebuild(storage,offset,shape,stride,*unused):
    return TensorRef(storage,offset,shape,stride)
class MetadataReader(pickle.Unpickler):
    def find_class(self,module,name):
        allowed={('collections','OrderedDict'):OrderedDict,('torch','FloatStorage'):StorageKind('float32',4),('torch','LongStorage'):StorageKind('int64',8),('torch._utils','_rebuild_tensor_v2'):rebuild}
        if (module,name) not in allowed:
            raise ValueError('Unapproved pickle global')
        return allowed[(module,name)]
    def persistent_load(self,pid):
        if len(pid)!=5 or pid[0]!='storage' or not isinstance(pid[1],StorageKind) or pid[3] not in ('cpu','cuda:0'):
            raise ValueError('Unapproved storage record')
        if not re.fullmatch('[0-9]+',pid[2]):
            raise ValueError('Invalid storage key')
        return StorageRef(pid[2],pid[1],pid[4])

def contiguous(shape):
    strides=[]
    count=1
    for dimension in reversed(shape):
        strides.append(count)
        count*=dimension
    return tuple(reversed(strides))

OUT=ROOT/args.output_dir
(OUT/'storages').mkdir(parents=True,exist_ok=True)
model=onnx.load(str(ROOT/args.graph),load_external_data=False)
manifest={'format_version':1,'checkpoint_url':'https://drive.usercontent.google.com/download?id=1bU-bFxEiXNXNoOLKaAz6_9j7XuE7f_6r&export=download&confirm=t','publisher_page':'https://drive.google.com/file/d/1bU-bFxEiXNXNoOLKaAz6_9j7XuE7f_6r/view?usp=sharing','checkpoint_sha256':CHECKPOINT_SHA,'checkpoint_bytes':CHECKPOINT.stat().st_size,'source_repository':'https://github.com/ahaliassos/raven','source_revision':'9fd9a3743c41ba93532258b340d123c20fe25432','initializers':[],'storages':{}}
with zipfile.ZipFile(CHECKPOINT) as archive:
    metadata=MetadataReader(io.BytesIO(archive.read('archive/data.pkl'))).load()
    assert isinstance(metadata,dict)
    for initializer in model.graph.initializer:
        ref=metadata[initializer.name]
        assert tuple(initializer.dims)==ref.shape,(initializer.name,'shape')
        assert ref.stride==contiguous(ref.shape),(initializer.name,'noncontiguous')
        assert initializer.data_type==onnx.TensorProto.FLOAT and ref.storage.kind.name=='float32'
        source='archive/data/'+ref.storage.key
        info=archive.getinfo(source)
        assert info.compress_type==zipfile.ZIP_STORED
        assert info.file_size==ref.storage.count*ref.storage.kind.width
        storage=archive.read(source)
        offset=ref.offset*ref.storage.kind.width
        length=math.prod(ref.shape)*ref.storage.kind.width
        assert offset>=0 and length>0 and offset+length<=len(storage)
        required=storage[offset:offset+length]
        actual=onnx.numpy_helper.to_array(initializer).tobytes()
        assert actual==required,(initializer.name,'export changed bytes')
        location='storages/'+ref.storage.key+'.bin'
        if location not in manifest['storages']:
            (OUT/location).write_bytes(storage)
            manifest['storages'][location]={'zip_entry':source,'bytes':len(storage),'sha256':hashlib.sha256(storage).hexdigest()}
        manifest['initializers'].append({'name':initializer.name,'source_key':initializer.name,'location':location,'offset':offset,'length':length,'shape':list(ref.shape),'sha256':hashlib.sha256(required).hexdigest()})
        set_external_data(initializer,location=location,offset=offset,length=length)
        for field in ['raw_data','float_data','int32_data','string_data','int64_data','double_data','uint64_data']:
            initializer.ClearField(field)
assert all(x.data_location==onnx.TensorProto.EXTERNAL and not x.raw_data for x in model.graph.initializer)
path=OUT/'visual-ctc.onnx'
onnx.save_model(model,str(path))
manifest['graph_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
manifest['graph_bytes']=path.stat().st_size
manifest['initializer_count']=len(model.graph.initializer)
manifest['external_storage_bytes']=sum(s['bytes'] for s in manifest['storages'].values())
manifest['constant_tensors']=[{'node':node.name,'shape':list(attr.t.dims),'type':attr.t.data_type,'bytes':len(attr.t.raw_data)} for node in model.graph.node for attr in node.attribute if node.op_type=='Constant' and attr.type==onnx.AttributeProto.TENSOR]
manifest['model_io']={'input':{'name':'mouth','type':'float32','shape':[1,'time',88,88]},'output':{'name':'log_probs','type':'float32','shape':[1,'time',1049]}}
manifest['preprocessing']={'frames_per_second':25,'mouth_crop':96,'center_crop':88,'mean':.421,'std':.165,'grayscale_rgb':[.2989,.587,.114]}
manifest['decode']={'type':'ctc_greedy','blank_id':0,'eos_id':1048,'collapse_consecutive_repeats_before_removing_blank':True,'word_separator':'▁'}
manifest['dynamic_position_encoding']=True
manifest['model_label']='BRAVEn Large, high-resource LRS3+Vox2-en+AVS with self-training'
manifest['graph_source_sha256']=hashlib.sha256((ROOT/args.graph).read_bytes()).hexdigest()
manifest['export_script_sha256']=hashlib.sha256((ROOT/'export_ctc.py').read_bytes()).hexdigest()
manifest['tokens_sha256']=hashlib.sha256((ROOT/'tokens.json').read_bytes()).hexdigest()
manifest['rights']={'project_license':'MIT','copyright':'2023 ahaliassos','vendored_code':'Apache-2.0 headers retained upstream','weight_license_statement':'No separate statement or conflicting restriction found; application of project MIT to linked checkpoint is an inference.','no_weight_redistribution':'Bundle graph, manifest and tokens only. Fetch original publisher checkpoint on user opt-in and extract only whitelisted storage entries after SHA256 verification.'}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(OUT/'tokens.json').write_bytes((ROOT/'tokens.json').read_bytes())
onnx.checker.check_model(str(path))
print(json.dumps({k:v for k,v in manifest.items() if k not in ('initializers','storages','constant_tensors')}),flush=True)
print('externalization_complete',flush=True)
