// MicInput.swift's gate: what the mic recorded before the listening sound was heard out is never heard.

import AVFoundation
import Foundation
import Testing
@testable import EpicAudioGames

/**
 * The mic's gate (MicInput.admit, gated and dropping): a buffer recorded before the gate is dropped, one that straddles
 * it loses its frames from before it, and those from the gate on go through as they are. Android starts its recogniser
 * after the sound instead (ListenSequenceTest.kt).
 */
struct MicInputTests {
    /// A host time.
    let start: UInt64 = 1_000_000_000

    /// The host time [seconds] after [start].
    private func at(_ seconds: Double) -> UInt64 { start + AVAudioTime.hostTime(forSeconds: seconds) }

    @Test func buffersRecordedBeforeTheGateAreDropped() {
        // 1024 frames at 48 kHz are 21.3 ms.
        #expect(MicInput.admit(start: start, frames: 1_024, rate: 48_000, from: at(0.5)) == .drop)
        // Ending exactly at the gate: every frame before it.
        #expect(MicInput.admit(start: start, frames: 480, rate: 48_000, from: at(0.01)) == .drop)
    }

    @Test func aBufferStraddlingTheGateLosesItsFramesBeforeIt() {
        #expect(MicInput.admit(start: start, frames: 1_024, rate: 48_000, from: at(0.01)) == .trim(480))
        // The gate inside a frame: that frame goes too.
        #expect(MicInput.admit(start: start, frames: 1_024, rate: 48_000, from: at(0.0101)) == .trim(485))
        #expect(MicInput.admit(start: start, frames: 1_024, rate: 44_100, from: at(0.01)) == .trim(441))
        #expect(MicInput.admit(start: start, frames: 481, rate: 48_000, from: at(0.01)) == .trim(480))
    }

    @Test func buffersFromTheGateOnAreHeard() {
        #expect(MicInput.admit(start: start, frames: 1_024, rate: 48_000, from: start) == .pass)
        #expect(MicInput.admit(start: at(1), frames: 1_024, rate: 48_000, from: start) == .pass)
        // No gate (no listening sound): all of it.
        #expect(MicInput.admit(start: start, frames: 1_024, rate: 48_000, from: nil) == .pass)
    }

    /// The tap's buffers as the gate lets them through, by the host time they were recorded at: the part from the gate
    /// on is a buffer of its own, every channel's samples moved along.
    @Test func theTapHearsFromTheGateOn() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        buffer.frameLength = 1_024
        for c in 0..<2 {
            for i in 0..<1_024 { buffer.floatChannelData![c][i] = Float(c * 10_000 + i) }
        }
        let when = AVAudioTime(hostTime: start)
        #expect(MicInput.gated(buffer, when: when, from: nil) === buffer)
        #expect(MicInput.gated(buffer, when: when, from: start) === buffer)
        #expect(MicInput.gated(buffer, when: when, from: at(1)) == nil)
        let rest = try #require(MicInput.gated(buffer, when: when, from: at(0.01)))
        #expect(rest.frameLength == 544)
        #expect(rest.floatChannelData![0][0] == 480)
        #expect(rest.floatChannelData![1][0] == 10_480)
        #expect(rest.floatChannelData![1][543] == 11_023)
        // 16-bit samples, interleaved: moved along the same way.
        let pairs = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2,
                                               interleaved: true))
        let shorts = try #require(AVAudioPCMBuffer(pcmFormat: pairs, frameCapacity: 100))
        shorts.frameLength = 100
        for i in 0..<200 { shorts.int16ChannelData![0][i] = Int16(i) }
        let tail = try #require(MicInput.dropping(10, of: shorts))
        #expect(tail.frameLength == 90)
        #expect(tail.int16ChannelData![0][0] == 20)
        #expect(tail.int16ChannelData![0][179] == 199)
        #expect(MicInput.dropping(100, of: shorts) == nil)
    }
}
