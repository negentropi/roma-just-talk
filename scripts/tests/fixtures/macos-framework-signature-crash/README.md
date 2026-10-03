# Framework loader reports

`sonoma-prior-minimum.ips` is an unmodified report from a disposable Apple Silicon
VM on macOS 14.2.1/23C71. Safari downloaded Actions artifact9677730504 from
run33150346572, sourceeedfbeaf4b18e05229a4a336e9ab19de303d8548. Finder's ordinary
Open was blocked by Gatekeeper. The separate context Open and explicit per-app
Open trial crashed before welcome.

Report SHA256 is `b382d4f5f359a7b667ad8e2475cfa71d26c052cac7ce9f02097d3693e60f8852`.
Guest before/after markers were `2026-10-03T05:50:22Z` and
`2026-10-03T05:52:19Z`. The report was absent before and present after. Its app
and rejected Whisper UUIDs match the immutable downloaded artifact. All124
bundle files and links matched the preserved manifest before and after.

Sonoma omits `fatalDyldError`. Report metadata is20.27s after process creation,
but only0.56s after crash capture. Apple defines these as different timestamps.
[Apple JSON crash format](https://developer.apple.com/documentation/xcode/interpreting-the-json-format-of-a-crash-report)

The older `whisper.ips` and `mediaremote-adapter.ips` are synthetic classifier
fixtures derived from the reported Tahoe failures. They do not establish a
fresh runtime reproduction. Passing this classifier never proves candidate
launch, artifact freshness, or normal notarized Open.
