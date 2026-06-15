import Testing
@testable import VoiceInk

struct WordAgreementEngineTests {
    @Test func rollingPreloadCachedFinalizationRequiresFreshHypothesis() {
        let config = AgreementConfig.rollingPreload

        #expect(config.runsImmediatePassOnBufferedAudio)
        #expect(config.transcribeIntervalSeconds < AgreementConfig().transcribeIntervalSeconds)
        #expect(config.cachedFinalizationMaxLagSeconds <= 0.25)
        #expect(config.cachedFinalizationMaxLagSeconds < AgreementConfig().cachedFinalizationMaxLagSeconds)
    }
}
