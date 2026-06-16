//
//  RiffWaveUtils.swift
//  VoiceInk-ios
//
//  Simple WAV file decoding utilities for Whisper
//  Adapted from whisper.swiftui demo
//

import Foundation
import VoiceInkCore

/// Decode WAV file to float samples for Whisper transcription
func decodeWaveFile(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    
    // Basic WAV header validation
    guard let floats = VoiceInkPCM16Audio.floatSamples(fromWAVData: data) else {
        throw NSError(domain: "RiffWaveUtils", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid WAV file - too small"])
    }
    
    return floats
}
