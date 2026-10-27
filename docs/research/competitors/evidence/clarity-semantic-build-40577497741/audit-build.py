import ast
import hashlib
import json
import plistlib
import re
import struct
from pathlib import Path

ROOT = Path('/data/codex/rjt/clarity-semantic-build-40577497741')
REV = '18552122392a0d161969074b1ff2361d1a9a5517'
EVIDENCE = ROOT / 'build-evidence'
PAYLOAD = ROOT / 'payload'
PACKAGE = EVIDENCE / 'generator/writing-local-cli-service-probe/package'
APP = PAYLOAD / 'ClaritySemanticProbe.app'
APP_PATHS = [
    'VoiceInk/Services/AIEnhancement/AIService.swift',
    'VoiceInk/Services/AIEnhancement/AIEnhancementService.swift',
    'VoiceInk/Services/AIEnhancement/LocalCLIService.swift',
    'VoiceInk/Services/OllamaService.swift',
    'VoiceInk/Services/APIKeyManager.swift',
    'VoiceInk/Services/KeychainService.swift',
    'VoiceInk/Services/CustomVocabularyService.swift',
    'VoiceInk/Services/ScreenCaptureService.swift',
    'VoiceInk/Services/SelectedTextService.swift',
    'VoiceInk/Models/VocabularyWord.swift',
    'VoiceInk/Notifications/AppNotifications.swift'
]

def digest(data):
    return hashlib.sha256(data).hexdigest()

def read(path):
    return json.loads(path.read_text())

def tree(path):
    return {str(item.relative_to(path)): digest(item.read_bytes()) for item in sorted(path.rglob('*')) if item.is_file()}

checks = {}
def check(name, value):
    checks[name] = bool(value)
    assert value, name

expected = read(ROOT / 'expected-source-hashes.json')
contract = read(EVIDENCE / 'source-contract.json')
build = read(EVIDENCE / 'build-receipt.json')
original = read(EVIDENCE / 'generator/writing-local-cli-service-probe/source-contract.json')
check('sourceHead', expected['sourceSHA'] == contract['sourceSHA'] == build['sourceSHA'] == original['source_sha'] == REV)
check('all173CommittedInputs', len(expected['sourceInputs']) == 173 and expected['sourceInputs'] == contract['sourceInputs'])
check('elevenAppSources', original['app_sources'] == {path: expected['sourceInputs'][path] for path in APP_PATHS})
check('actualElevenAppBytes', all(digest((PACKAGE / 'Sources/WritingLocalCLIProbe' / Path(path).name).read_bytes()) == expected['sourceInputs'][path] for path in APP_PATHS))
check('exactGeneratedSources', tree(PACKAGE / 'Sources') == contract['generatedSources'] and len(contract['generatedSources']) == 12)
dependencies = {path: sha for path, sha in expected['sourceInputs'].items() if path.startswith(('VoiceInkCore/', 'VoiceInkNVIDIA/'))}
check('realCoreNVIDIASourceCensus', contract['generatedDependencies'] == dependencies)
check('constructorAndService', contract['requestConstructorSourceSHA256'] == expected['sourceInputs']['VoiceInkCore/Sources/VoiceInkCore/DictationPolish.swift'] and contract['serviceSourceSHA256'] == expected['sourceInputs']['VoiceInk/Services/AIEnhancement/AIEnhancementService.swift'])
check('immutableGeneratorContract', digest((EVIDENCE / 'generator/writing-local-cli-service-probe/source-contract.json').read_bytes()) == contract['generatorContractSHA256'] and digest((PAYLOAD / 'generator-source-contract.json').read_bytes()) == contract['generatorContractSHA256'])
check('packageManifest', digest((PACKAGE / 'Package.swift').read_bytes()) == contract['packageManifestSHA256'])
check('all41Canonical22NVIDIAIdentities', len(expected['canonicalPins']) == 41 and len(expected['nvidiaPins']) == 22 and set(expected['nvidiaPins']).issubset(expected['canonicalPins']))
inner_lock_differences = {name: {'nvidiaLockState': pin['state'], 'appCanonicalState': expected['canonicalPins'][name]['state']} for name, pin in expected['nvidiaPins'].items() if pin['state'] != expected['canonicalPins'][name]['state']}
identities = set(expected['nvidiaPins']) | {'llmkit', 'selectedtextkit', 'axswift', 'keysender'}
retained = {name: expected['canonicalPins'][name] for name in sorted(identities)}
check('exact26CanonicalPins', len(retained) == 26 and retained == contract['expectedPins'] == original['expected_pins'])
resolved = {pin['identity']: pin for pin in read(PACKAGE / 'Package.resolved')['pins']}
check('actualResolvedPins', resolved == retained and read(EVIDENCE / 'resolved-pin-receipt.json')['expectedPins'] == retained and read(EVIDENCE / 'resolved-pin-receipt.json')['valid'] is True)
before = read(EVIDENCE / 'checkouts-before-build.json')
after = read(EVIDENCE / 'checkouts-after-build.json')
check('actual26CleanCheckouts', before == after and set(before) == identities and all(row == {'revision': retained[name]['state']['revision'], 'trackedClean': True} for name, row in before.items()))
check('actualCheckoutReceipts', digest((EVIDENCE / 'checkouts-before-build.json').read_bytes()) == build['checkoutsBeforeBuildSHA256'] and digest((EVIDENCE / 'checkouts-after-build.json').read_bytes()) == build['checkoutsAfterBuildSHA256'])
check('sourceBuildReceipt', digest((EVIDENCE / 'source-contract.json').read_bytes()) == build['sourceContractSHA256'])
check('signedPayloadContracts', (PAYLOAD / 'source-contract.json').read_bytes() == (EVIDENCE / 'source-contract.json').read_bytes() and (PAYLOAD / 'build-receipt.json').read_bytes() == (EVIDENCE / 'build-receipt.json').read_bytes())
runner = (PAYLOAD / 'run-clarity-semantic-probe.sh').read_bytes()
check('packagedRunnerCommittedBytes', digest(runner) == contract['runnerSHA256'] == expected['sourceInputs']['scripts/run-clarity-semantic-probe.sh'])
python = re.search(rb"<<'PY'\n(.*)\nPY\s*$", runner, re.S).group(1).decode()
module = ast.parse(python)
template = next(ast.literal_eval(node.value) for node in module.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'DRIVER' for target in node.targets))
adapted = template.replace('__SOURCE_SHA__', REV).replace('__BUNDLE_ID__', contract['bundleIdentifier']).replace('__INPUT_SHA256__', contract['inputSHA256']).encode()
check('actualAdaptedDriverBytes', adapted == (PACKAGE / 'Sources/WritingLocalCLIProbe/Probe.swift').read_bytes() and digest(adapted) == contract['driverSHA256'])
inputs = (PAYLOAD / 'clarity-inputs.json').read_bytes()
check('nineInputsAndSeparateRubric', digest(inputs) == contract['inputSHA256'] == expected['sourceInputs']['docs/research/competitors/fixtures/clarity-inputs.json'] and [row['id'] for row in json.loads(inputs)] == expected['inputCaseIDs'] and len(expected['inputCaseIDs']) == 9 and contract['rubricSHA256'] == expected['sourceInputs']['docs/research/competitors/fixtures/clarity-private-rubric.json'] and contract['rubricIncludedInArtifact'] is False and not any('rubric' in str(path.relative_to(PAYLOAD)).lower() for path in PAYLOAD.rglob('*')))
check('all27ScheduledCases', contract['expectedCases'] == [case + '-' + style for case in expected['inputCaseIDs'] for style in ['natural', 'casual', 'formal']])
check('entireSignedBundleBytes', tree(APP) == build['bundleManifest'])
executable = (APP / 'Contents/MacOS/ClaritySemanticProbe').read_bytes()
check('binaryBytes', digest(executable) == build['binarySHA256'])
magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack('<8I', executable[:32])
check('nativeArm64MachO', magic == 0xfeedfacf and cpu == 0x0100000c and filetype == 2)
offset = 32
signatures = []
for _ in range(ncmds):
    command, size = struct.unpack('<2I', executable[offset:offset + 8])
    assert size >= 8
    if command == 0x1d:
        data_offset, data_size = struct.unpack('<2I', executable[offset + 8:offset + 16])
        signatures.append((data_offset, data_size))
    offset += size
check('embeddedCodeSignature', len(signatures) == 1 and signatures[0][1] > 0 and sum(signatures[0]) <= len(executable))
info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
signature = (EVIDENCE / 'signature.txt').read_text()
check('uniqueSignedIdentity', info['CFBundleIdentifier'] == contract['bundleIdentifier'] == build['bundleIdentifier'] and info['CFBundleExecutable'] == 'ClaritySemanticProbe' and ('Identifier=' + contract['bundleIdentifier']) in signature and 'Signature=adhoc' in signature)
check('signatureToolchainBytes', digest((EVIDENCE / 'signature.txt').read_bytes()) == build['signatureSHA256'] and digest((EVIDENCE / 'toolchain.log').read_bytes()) == build['toolchainSHA256'] and (PAYLOAD / 'signature.txt').read_bytes() == (EVIDENCE / 'signature.txt').read_bytes() and (PAYLOAD / 'toolchain.log').read_bytes() == (EVIDENCE / 'toolchain.log').read_bytes())
log = (EVIDENCE / 'build.log').read_text()
check('actualNativeCompileLink', all(marker in log for marker in ['Compiling VoiceInkNVIDIA ', 'Compiling VoiceInkCore ', 'Compiling WritingLocalCLIProbe AIEnhancementService.swift', 'Linking WritingLocalCLIProbe', "Build of product 'WritingLocalCLIProbe' complete!"]) and not re.search(r'(^|\n).*\berror:', log))
check('zeroSemanticCallsInBuild', build['semanticCallsExecuted'] == 0 and all(command[:3] in [['xcrun', 'swift', 'package'], ['xcrun', 'swift', 'build']] for command in build['commands']) and not (EVIDENCE / 'results.json').exists() and not (PAYLOAD / 'results.json').exists())
result = {
    'valid': True, 'runID': 40577497741, 'runURL': 'https://github.com/negentropi/roma-just-talk/actions/runs/40577497741',
    'sourceSHA': REV, 'checks': checks, 'sourceInputCount': len(expected['sourceInputs']),
    'appSourceCount': len(APP_PATHS), 'generatedCoreNVIDIAFileCount': len(dependencies), 'canonicalPinCount': 41, 'nvidiaPinCount': 22, 'actualServicePinCount': len(retained),
    'bundleIdentifier': contract['bundleIdentifier'], 'binarySHA256': build['binarySHA256'],
    'signedTarSHA256': digest((ROOT / 'signed-probe/signed-probe.tar.gz').read_bytes()),
    'sourceContractSHA256': build['sourceContractSHA256'], 'requestConstructorSourceSHA256': contract['requestConstructorSourceSHA256'], 'serviceSourceSHA256': contract['serviceSourceSHA256'],
    'semanticCallsExecuted': 0,
    'lockSelection': 'NVIDIA22 supplies identities; app canonical41 supplies the exact26 retained pins. Both original lockfile bytes remain frozen.',
    'innerNVIDIALockStateDifferences': inner_lock_differences,
    'signatureProof': 'CI codesign --verify --deep --strict passed. Independent Linux audit confirms exact signed bundle bytes and embedded signature. Fresh Mac verification remains required before execution.',
    'toolchain': (EVIDENCE / 'toolchain.log').read_text().splitlines(),
    'scope': 'Native remote build/signing and frozen source/dependency/artifact identity only. No semantic/provider/authentication execution, pipeline/UI, microphone or editor-delivery proof.'
}
(ROOT / 'audit.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
print(json.dumps({key: result[key] for key in ['valid', 'sourceSHA', 'sourceInputCount', 'appSourceCount', 'generatedCoreNVIDIAFileCount', 'actualServicePinCount', 'bundleIdentifier', 'binarySHA256', 'semanticCallsExecuted']}))
