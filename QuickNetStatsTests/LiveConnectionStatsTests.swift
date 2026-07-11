//
//  LiveConnectionStatsTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("LiveConnectionStats")
struct LiveConnectionStatsTests {

    // MARK: - SNR

    @Test("snrDB is rssi minus noise when both are present")
    func snrComputed() {
        let stats = LiveConnectionStats(rssiDBm: -52, noiseDBm: -95)
        #expect(stats.snrDB == 43)
    }

    @Test("snrDB is nil when rssi is missing")
    func snrNilWithoutRssi() {
        let stats = LiveConnectionStats(noiseDBm: -95)
        #expect(stats.snrDB == nil)
    }

    @Test("snrDB is nil when noise is missing")
    func snrNilWithoutNoise() {
        let stats = LiveConnectionStats(rssiDBm: -52)
        #expect(stats.snrDB == nil)
    }

    // MARK: - Text formatting

    @Test("RF text fields format with units")
    func rfText() {
        let stats = LiveConnectionStats(rssiDBm: -52, noiseDBm: -95, txRateMbps: 866)
        #expect(stats.rssiText == "-52 dBm")
        #expect(stats.noiseText == "-95 dBm")
        #expect(stats.snrText == "43 dB")
        #expect(stats.txRateText == "866 Mbps")
    }

    @Test("RF text fields are nil when values are missing")
    func rfTextNil() {
        let stats = LiveConnectionStats()
        #expect(stats.rssiText == nil)
        #expect(stats.noiseText == nil)
        #expect(stats.snrText == nil)
        #expect(stats.txRateText == nil)
        #expect(stats.downloadText == nil)
        #expect(stats.uploadText == nil)
    }

    @Test("download/upload text use the byte-rate formatter")
    func throughputText() {
        let stats = LiveConnectionStats(downloadBytesPerSec: 1_200_000, uploadBytesPerSec: 340_000)
        #expect(stats.downloadText == "1.2 MB/s")
        #expect(stats.uploadText == "340.0 KB/s")
    }

    // MARK: - Parameterized rate text (units)

    @Test("downloadText(in:) keeps the native byte format and converts to bits")
    func downloadTextUnits() {
        let stats = LiveConnectionStats(downloadBytesPerSec: 1_200_000)
        #expect(stats.downloadText(in: .bytesPerSecond) == "1.2 MB/s")
        #expect(stats.downloadText(in: .bitsPerSecond) == "9.6 Mbps")
    }

    @Test("uploadText(in:) keeps the native byte format and converts to bits")
    func uploadTextUnits() {
        let stats = LiveConnectionStats(uploadBytesPerSec: 340_000)
        #expect(stats.uploadText(in: .bytesPerSecond) == "340.0 KB/s")
        #expect(stats.uploadText(in: .bitsPerSecond) == "2.72 Mbps")
    }

    @Test("txRateText(in:) keeps the native bit format and converts to bytes")
    func txRateTextUnits() {
        let stats = LiveConnectionStats(txRateMbps: 210)
        #expect(stats.txRateText(in: .bitsPerSecond) == "210 Mbps")
        #expect(stats.txRateText(in: .bytesPerSecond) == "26.25 MB/s")
    }

    @Test("parameterized text funcs stay nil when their value is missing")
    func parameterizedTextNil() {
        let stats = LiveConnectionStats()
        #expect(stats.downloadText(in: .bitsPerSecond) == nil)
        #expect(stats.uploadText(in: .bytesPerSecond) == nil)
        #expect(stats.txRateText(in: .bitsPerSecond) == nil)
    }

    @Test("existing computed text properties stay in their native unit")
    func nativeComputedPropertiesUnchanged() {
        let stats = LiveConnectionStats(
            downloadBytesPerSec: 340_000,
            uploadBytesPerSec: 340_000,
            txRateMbps: 210
        )
        #expect(stats.downloadText == "340.0 KB/s")
        #expect(stats.uploadText == "340.0 KB/s")
        #expect(stats.txRateText == "210 Mbps")
    }

    // MARK: - Packet / error / drop rates

    @Test("countRateText rounds to a whole integer and appends /s", arguments: [
        (0.0, "0/s"),
        (0.4, "0/s"),
        (0.6, "1/s"),
        (1_234.0, "1234/s"),
        (1_234.7, "1235/s")
    ])
    func countRateTextRounds(input: Double, expected: String) {
        #expect(LiveConnectionStats.countRateText(input) == expected)
    }

    @Test("packet/error/drop text fields use the integer-rate formatter")
    func counterText() {
        let stats = LiveConnectionStats(
            downloadPacketsPerSec: 1_234,
            uploadPacketsPerSec: 56,
            errorsPerSec: 0,
            dropsPerSec: 2
        )
        #expect(stats.downloadPacketsText == "1234/s")
        #expect(stats.uploadPacketsText == "56/s")
        #expect(stats.errorsText == "0/s")
        #expect(stats.dropsText == "2/s")
    }

    @Test("packet/error/drop text fields are nil when values are missing")
    func counterTextNil() {
        let stats = LiveConnectionStats()
        #expect(stats.downloadPacketsText == nil)
        #expect(stats.uploadPacketsText == nil)
        #expect(stats.errorsText == nil)
        #expect(stats.dropsText == nil)
    }

    // MARK: - rateText boundaries

    @Test("rateText formats bytes per second across magnitude boundaries", arguments: [
        (999.0, "999 B/s"),
        (1_000.0, "1.0 KB/s"),
        (999_999.0, "1000.0 KB/s"),
        (1_000_000.0, "1.0 MB/s"),
        (1_500_000_000.0, "1.5 GB/s")
    ])
    func rateTextBoundaries(input: Double, expected: String) {
        #expect(LiveConnectionStats.rateText(input) == expected)
    }

    // MARK: - Mocks

    @Test("mockLiveWifi has all fields populated")
    func mockWifiPopulated() {
        let mock = LiveConnectionStats.mockLiveWifi
        #expect(mock.downloadBytesPerSec != nil)
        #expect(mock.uploadBytesPerSec != nil)
        #expect(mock.downloadPacketsPerSec != nil)
        #expect(mock.uploadPacketsPerSec != nil)
        #expect(mock.errorsPerSec != nil)
        #expect(mock.dropsPerSec != nil)
        #expect(mock.rssiDBm != nil)
        #expect(mock.noiseDBm != nil)
        #expect(mock.txRateMbps != nil)
        #expect(mock.snrDB != nil)
    }

    @Test("mockLiveWired has throughput and counters but no RF")
    func mockWiredPopulated() {
        let mock = LiveConnectionStats.mockLiveWired
        #expect(mock.downloadBytesPerSec != nil)
        #expect(mock.uploadBytesPerSec != nil)
        #expect(mock.downloadPacketsPerSec != nil)
        #expect(mock.uploadPacketsPerSec != nil)
        #expect(mock.rssiDBm == nil)
        #expect(mock.noiseDBm == nil)
        #expect(mock.txRateMbps == nil)
    }
}
