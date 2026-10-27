# Candidate stopped at unit-test compilation

[Run 40557828988](https://github.com/negentropi/roma-just-talk/actions/runs/40557828988), exact head `33ddff0ce3aa3c671805df5859bdc504ac0f1875`. Baseline produced the valid intended foreground failure at line 353. **Zero candidate UI cases ran.**

The candidate UI build compiles the scheme's unit-test target too. `VoiceInkTests/DictationStoreSeedLiveTests.swift:53` nests one Swift Testing `#require` inside another, producing `recursive expansion of macro 'require(_:_:sourceLocation:)'`. The subsequent unsigned-app diagnostic is build-failure aftermath. No candidate sheet, control, persistence or draft behavior was exercised.

`analyze-result.py` reproduces the classification from the original comparison result and candidate driver log. `owning-source-excerpt.txt` pins the nested macro at immutable head33dd. The UI oracle remains `d6980c…`; `source-bindings.json` proves app-product roots unchanged from273.

The failed workflow log was fetched once. Selected ZIP members were read with HTTP Range and their CRCs checked by Python zipfile: 385,476 bytes fetched from a 106,132,451-byte artifact. The API artifact digest is retained separately; the whole archive was not downloaded or hash-verified. No duplicate full artifact download, source edit or runtime claim.
