# Actual writing-service proof

Source `f870a0b04238f338b52855b081b49087cc8966fa`. [Remote run 40496074931](https://github.com/negentropi/roma-just-talk/actions/runs/40496074931) compiled eleven unchanged app files and their real dependencies. It passed four deterministic service checks through `AIService`, `AIEnhancementService` and `LocalCLIService`.

The checks covered the captured command after preferences changed, exact prompt delivery through stdin and environment, controlled nonzero exit, and empty output. Ordinary enhancement remained off. Package pins, source hashes and executable identity were checked. The [receipt](receipt.json) records the artifact and binary digests.

The same signed probe then ran quietly on the host with its own volatile preferences and the existing installed Claude CLI authentication. Three synthetic requests passed through the real services. GPT-6.1 Sol independently compared the outputs with their source inputs.

| Case | Observed output |
| --- | --- |
| Japanese to English | Let's meet at the south exit of Taipei Station at 3 p.m. tomorrow. The confirmation code is RJT-482. |
| English to Traditional Chinese | 明天下午3點在台北車站南出口跟我碰面。確認碼是 RJT-482。 |
| Concise selected-text edit | Mina, the Atlas project review has moved to Friday at 10:30 at Taipei Main Station; please use ticket RJT-482 when you reply. |

The [deterministic](deterministic.json) and [semantic](semantic.json) observations retain actual outputs and bounded checks. No credential values were transferred to CI or retained in this evidence. The CLI child uses its normal authentication and shell startup. The selected Local CLI route does not load RJT provider credentials.

These results establish this service boundary and these three language cases. They do not establish recording, ASR, editor delivery, physical shortcuts, general language quality or instruction-injection robustness. The CLI default was used without a model override; text output did not expose the served model identity.
