import Foundation

public enum VoiceInkLanguageCatalog {
    public static let autoDetectCode = "auto"
    public static let autoDetectName = "Auto-detect"

    private static let whisperLanguageCodes: Set<String> = [
        "auto",
        "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo",
        "br", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "es",
        "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw",
        "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja",
        "jw", "ka", "kk", "km", "kn", "ko", "la", "lb", "ln", "lo",
        "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt",
        "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt",
        "ro", "ru", "sa", "sd", "si", "sk", "sl", "sn", "so", "sq",
        "sr", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl",
        "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "yue", "zh"
    ]

    private static let fluidAudioLanguageCodes: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr",
        "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro",
        "ru", "sk", "sl", "sv", "uk"
    ]

    // Apple Native Speech languages in BCP-47 format.
    // Queried from SpeechTranscriber.supportedLocales on macOS 26.4.
    public static let nativeApple: [String: String] = [
        "de-DE": "German (Germany)",
        "de-AT": "German (Austria)",
        "de-CH": "German (Switzerland)",
        "en-AU": "English (Australia)",
        "en-CA": "English (Canada)",
        "en-GB": "English (United Kingdom)",
        "en-IE": "English (Ireland)",
        "en-IN": "English (India)",
        "en-NZ": "English (New Zealand)",
        "en-SG": "English (Singapore)",
        "en-US": "English (United States)",
        "en-ZA": "English (South Africa)",
        "es-CL": "Spanish (Chile)",
        "es-ES": "Spanish (Spain)",
        "es-MX": "Spanish (Mexico)",
        "es-US": "Spanish (United States)",
        "fr-BE": "French (Belgium)",
        "fr-CA": "French (Canada)",
        "fr-CH": "French (Switzerland)",
        "fr-FR": "French (France)",
        "it-CH": "Italian (Switzerland)",
        "it-IT": "Italian (Italy)",
        "ja-JP": "Japanese (Japan)",
        "ko-KR": "Korean (South Korea)",
        "pt-BR": "Portuguese (Brazil)",
        "pt-PT": "Portuguese (Portugal)",
        "yue-CN": "Cantonese (China mainland)",
        "zh-CN": "Chinese (China mainland)",
        "zh-HK": "Chinese (Hong Kong)",
        "zh-TW": "Chinese (Taiwan)"
    ]

    public static let all: [String: String] = [
        "auto": "Auto-detect",
        "af": "Afrikaans",
        "am": "Amharic",
        "ar": "Arabic",
        "as": "Assamese",
        "az": "Azerbaijani",
        "ba": "Bashkir",
        "be": "Belarusian",
        "bg": "Bulgarian",
        "bn": "Bengali",
        "bo": "Tibetan",
        "br": "Breton",
        "bs": "Bosnian",
        "ca": "Catalan",
        "cs": "Czech",
        "cy": "Welsh",
        "da": "Danish",
        "de": "German",
        "de_ch": "Swiss German",
        "el": "Greek",
        "en": "English",
        "en_au": "Australian English",
        "en_uk": "British English",
        "en_us": "US English",
        "es": "Spanish",
        "et": "Estonian",
        "eu": "Basque",
        "fa": "Persian",
        "fi": "Finnish",
        "fil": "Filipino",
        "fo": "Faroese",
        "fr": "French",
        "ga": "Irish",
        "gl": "Galician",
        "gu": "Gujarati",
        "ha": "Hausa",
        "haw": "Hawaiian",
        "he": "Hebrew",
        "hi": "Hindi",
        "hr": "Croatian",
        "ht": "Haitian Creole",
        "hu": "Hungarian",
        "hy": "Armenian",
        "id": "Indonesian",
        "ig": "Igbo",
        "is": "Icelandic",
        "it": "Italian",
        "ja": "Japanese",
        "jw": "Javanese",
        "ka": "Georgian",
        "kk": "Kazakh",
        "km": "Khmer",
        "kn": "Kannada",
        "ko": "Korean",
        "ku": "Kurdish",
        "ky": "Kyrgyz",
        "la": "Latin",
        "lb": "Luxembourgish",
        "ln": "Lingala",
        "lo": "Lao",
        "lt": "Lithuanian",
        "lv": "Latvian",
        "mg": "Malagasy",
        "mi": "Maori",
        "mk": "Macedonian",
        "ml": "Malayalam",
        "mn": "Mongolian",
        "mr": "Marathi",
        "ms": "Malay",
        "mt": "Maltese",
        "my": "Myanmar",
        "ne": "Nepali",
        "nl": "Dutch",
        "nn": "Norwegian Nynorsk",
        "no": "Norwegian",
        "oc": "Occitan",
        "or": "Odia",
        "pa": "Punjabi",
        "pl": "Polish",
        "ps": "Pashto",
        "pt": "Portuguese",
        "ro": "Romanian",
        "ru": "Russian",
        "sa": "Sanskrit",
        "sd": "Sindhi",
        "si": "Sinhala",
        "sk": "Slovak",
        "sl": "Slovenian",
        "sn": "Shona",
        "so": "Somali",
        "sq": "Albanian",
        "sr": "Serbian",
        "su": "Sundanese",
        "sv": "Swedish",
        "sw": "Swahili",
        "ta": "Tamil",
        "te": "Telugu",
        "tg": "Tajik",
        "th": "Thai",
        "tk": "Turkmen",
        "tl": "Tagalog",
        "tr": "Turkish",
        "tt": "Tatar",
        "uk": "Ukrainian",
        "ur": "Urdu",
        "uz": "Uzbek",
        "vi": "Vietnamese",
        "wo": "Wolof",
        "xh": "Xhosa",
        "yi": "Yiddish",
        "yo": "Yoruba",
        "yue": "Cantonese",
        "zh": "Chinese",
        "zu": "Zulu"
    ]

    public static let englishOnly = ["en": "English"]

    static func languages<S: Sequence>(matching codes: S) -> [String: String] where S.Element == String {
        let codeSet = Set(codes)
        return all.filter { codeSet.contains($0.key) }
    }

    public static func whisperLanguages(isMultilingual: Bool = true) -> [String: String] {
        isMultilingual ? languages(matching: whisperLanguageCodes) : englishOnly
    }

    public static func fluidAudioLanguages(isMultilingual: Bool = true) -> [String: String] {
        guard isMultilingual else {
            return englishOnly
        }

        var filtered = languages(matching: fluidAudioLanguageCodes)
        filtered[autoDetectCode] = autoDetectName
        return filtered
    }

    public static func languages(
        for provider: VoiceInkTranscriptionModelProvider,
        isMultilingual: Bool = true
    ) -> [String: String] {
        guard isMultilingual else {
            return englishOnly
        }

        guard let codes = provider.languageCodes else {
            return all
        }

        var filtered = languages(matching: codes)
        if provider.includesAutoDetect {
            filtered[autoDetectCode] = autoDetectName
        }
        return filtered
    }
}

public enum VoiceInkTranscriptionLanguageSupport {
    private static let assemblyAIRealtimeLanguageCodes = ["en", "es", "de", "fr", "pt", "it"]

    private static let assemblyAIBatchLanguageCodes = [
        "en", "en_au", "en_uk", "en_us", "es", "fr", "de", "it", "pt", "nl",
        "hi", "ja", "zh", "fi", "ko", "pl", "ru", "tr", "uk", "vi", "af",
        "sq", "am", "ar", "hy", "as", "az", "ba", "eu", "be", "bn", "bs",
        "br", "bg", "my", "ca", "hr", "cs", "da", "et", "fo", "gl", "ka",
        "el", "gu", "ht", "ha", "haw", "he", "hu", "is", "id", "jw", "kn",
        "kk", "km", "lo", "la", "lv", "ln", "lt", "lb", "mk", "mg", "ms",
        "ml", "mt", "mi", "mr", "mn", "ne", "no", "nn", "oc", "pa", "ps",
        "fa", "ro", "sa", "sr", "sn", "sd", "si", "sk", "sl", "so", "su",
        "sw", "sv", "de_ch", "tl", "tg", "ta", "tt", "te", "th", "bo",
        "tk", "ur", "uz", "cy", "yi", "yo"
    ]

    public static func assemblyAILanguages(usesRealtime: Bool) -> [String: String] {
        let codes = usesRealtime ? assemblyAIRealtimeLanguageCodes : assemblyAIBatchLanguageCodes
        var filtered = VoiceInkLanguageCatalog.languages(matching: codes)
        filtered[VoiceInkLanguageCatalog.autoDetectCode] = VoiceInkLanguageCatalog.autoDetectName
        return filtered
    }

    public static func validLanguageOrFallback(
        _ language: String?,
        languages: [String: String],
        prefersNativeAppleEnglish: Bool = false
    ) -> String {
        if let language, languages[language] != nil {
            return language
        }

        if prefersNativeAppleEnglish, languages["en-US"] != nil {
            return "en-US"
        }

        if languages[VoiceInkLanguageCatalog.autoDetectCode] != nil {
            return VoiceInkLanguageCatalog.autoDetectCode
        }

        if languages["en"] != nil {
            return "en"
        }

        return languages.keys.sorted { lhs, rhs in
            languages[lhs, default: lhs] < languages[rhs, default: rhs]
        }.first ?? "en"
    }
}
