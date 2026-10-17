import Foundation
@testable import RomaCore

final class LocalOnboardingModelChoiceTests: XCTestCase {
    func testRegionOnlySuggestsBilingualInChineseSpeakingRegions() {
        for country in ["TW", "CN", "HK", "MO", "SG", " tw "] {
            var selection = RomaLocalOnboardingModelSelection()
            selection.applyRegionSuggestion(countryCode: country)
            XCTAssertEqual(selection.choice, .chineseAndEnglish)
        }
        for country in [nil, "", "US", "GB", "DE", "XX", "zh-TW"] {
            var selection = RomaLocalOnboardingModelSelection()
            selection.applyRegionSuggestion(countryCode: country)
            XCTAssertEqual(selection.choice, .englishOnly)
        }
    }

    func testManualOptOutWinsAgainstLateRegionResponse() {
        var selection = RomaLocalOnboardingModelSelection()
        selection.choose(.englishOnly)
        selection.applyRegionSuggestion(countryCode: "TW")
        XCTAssertEqual(selection.choice, .englishOnly)

        selection.choose(.chineseAndEnglish)
        selection.applyRegionSuggestion(countryCode: "US")
        XCTAssertEqual(selection.choice, .chineseAndEnglish)
    }

    func testExistingModelAndAcceptedDownloadCannotBeChangedByRegion() {
        var existing = RomaLocalOnboardingModelSelection(existingModelChoice: .englishOnly, hasExistingModel: true)
        existing.applyRegionSuggestion(countryCode: "TW")
        XCTAssertEqual(existing.choice, .englishOnly)

        var otherModel = RomaLocalOnboardingModelSelection(hasExistingModel: true)
        otherModel.applyRegionSuggestion(countryCode: "TW")
        XCTAssertEqual(otherModel.choice, .englishOnly)

        var accepted = RomaLocalOnboardingModelSelection()
        accepted.preserveCurrentChoice()
        accepted.applyRegionSuggestion(countryCode: "TW")
        XCTAssertEqual(accepted.choice, .englishOnly)
    }

    func testCurrentModelWinsOverAnOlderOnboardingPreference() {
        var selection = RomaLocalOnboardingModelSelection(
            explicitChoice: .chineseAndEnglish,
            existingModelChoice: .englishOnly,
            hasExistingModel: true
        )
        selection.applyRegionSuggestion(countryCode: "TW")
        XCTAssertEqual(selection.choice, .englishOnly)
    }

    func testExplicitChoiceSurvivesRelaunchAndMalformedPreferenceIsIgnored() {
        let suite = "RomaCore.LocalOnboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(RomaLocalOnboardingModelPreference.choice(in: defaults))
        RomaLocalOnboardingModelPreference.save(.englishOnly, in: defaults)
        var relaunched = RomaLocalOnboardingModelSelection(
            explicitChoice: RomaLocalOnboardingModelPreference.choice(in: defaults)
        )
        relaunched.applyRegionSuggestion(countryCode: "TW")
        XCTAssertEqual(relaunched.choice, .englishOnly)
        defaults.set("not-a-choice", forKey: "macOSOnboardingLocalModelChoice")
        XCTAssertNil(RomaLocalOnboardingModelPreference.choice(in: defaults))
    }

    func testRegionDecoderRejectsInvalidOrMissingCountry() {
        XCTAssertEqual(RomaOnboardingRegionLookup.countryCode(from: Data(#"{"countryCode":"TW"}"#.utf8)), "TW")
        for body in [#"{"countryCode":null}"#, #"{"countryCode":"tw"}"#, #"{"countryCode":"臺灣"}"#, #"{"countryCode":"TWN"}"#, "{}", "<html>error</html>"] {
            XCTAssertNil(RomaOnboardingRegionLookup.countryCode(from: Data(body.utf8)))
        }
    }

    func testRegisteredDefaultDoesNotStartDownloadBeforeLocalChoice() {
        let suite = "RomaCore.LocalOnboarding.Startup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let priorRegistration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        defer {
            defaults.removePersistentDomain(forName: suite)
            defaults.setVolatileDomain(priorRegistration, forName: UserDefaults.registrationDomain)
        }
        defaults.register(defaults: [RomaUserDefaultsKey.currentTranscriptionModel: "parakeet-tdt-0.6b-v2"])
        XCTAssertEqual(RomaCurrentTranscriptionModelPreference.modelName(from: defaults), "parakeet-tdt-0.6b-v2")
        let registered = RomaLocalOnboardingModelPreference.persistedModelName(in: defaults, domainName: suite)
        XCTAssertNil(registered)
        XCTAssertFalse(RomaLocalOnboardingModelPreference.shouldDownloadModelAtStartup(hasCompletedOnboarding: false, persistedModelName: registered))
        XCTAssertTrue(RomaLocalOnboardingModelPreference.shouldDownloadModelAtStartup(hasCompletedOnboarding: true, persistedModelName: registered))

        RomaCurrentTranscriptionModelPreference.saveModelName("selected-local-model", to: defaults)
        let selected = RomaLocalOnboardingModelPreference.persistedModelName(in: defaults, domainName: suite)
        XCTAssertEqual(selected, "selected-local-model")
        XCTAssertTrue(RomaLocalOnboardingModelPreference.shouldDownloadModelAtStartup(hasCompletedOnboarding: false, persistedModelName: selected))
    }

    func testRegisteredEnglishLanguageIsNotAnExplicitLanguagePreference() {
        let suite = "RomaCore.LocalOnboarding.Language.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let registration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        defer {
            defaults.removePersistentDomain(forName: suite)
            defaults.setVolatileDomain(registration, forName: UserDefaults.registrationDomain)
        }
        defaults.register(defaults: [RomaUserDefaultsKey.selectedTranscriptionLanguage: "en"])
        XCTAssertEqual(RomaTranscriptionLanguagePreference.storedLanguage(from: defaults), "en")
        XCTAssertNil(RomaLocalOnboardingModelPreference.persistedLanguage(in: defaults, domainName: suite))
        RomaTranscriptionLanguagePreference.saveSelectedLanguage("en", to: defaults)
        XCTAssertEqual(RomaLocalOnboardingModelPreference.persistedLanguage(in: defaults, domainName: suite), "en")
    }

    func testRegionRequestUsesBoundedGETAndIgnoresHTTPFailure() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OnboardingRegionURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        for statusCode in [200, 503] {
            OnboardingRegionURLProtocol.statusCode = statusCode
            let country = await RomaOnboardingRegionLookup.countryCode(session: session)
            XCTAssertEqual(country, statusCode == 200 ? "TW" : nil)
        }
    }
}

private final class OnboardingRegionURLProtocol: URLProtocol {
    static var statusCode = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url, RomaOnboardingRegionLookup.endpoint)
        XCTAssertEqual(request.timeoutInterval, 2)
        XCTAssertNil(request.httpBody)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"countryCode":"TW"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
