# PROTOTYPE — throwaway, not production

Question: does stream text feel like "the release result, shown early" when Roma shows its live
guesses as provisional (underlined, marked) text through a macOS input method, and commits the
final transcript once on release, instead of typing words and correcting them with Backspace?

- `RomaStreamInputMethod.swift` + `Info.plist`: a minimal IMKit input method. It passes every key
  through and only listens for Roma's distributed notifications:
  `com.negentropi.RomaStream.partial` (text = running transcript) → `setMarkedText`;
  `com.negentropi.RomaStream.commit` (text = final transcript) → `insertText`.
- App side: `defaults write com.negentropi.RomaJustTalk prototypeIMEStream -bool true`
  makes Roma post those notifications instead of live typing / pasting.
- `SelectInputSource.swift`: registers, enables and selects the input method.
