// DownloadState.swift: a pack's download as the store sheet shows it, and a full disk told apart (Store.kt's).

import Foundation
import Testing

@testable import EpicAppCore

struct DownloadStateTests {
    private let wifi = DownloadState.Network(connected: true, expensive: false, constrained: false)
    private let cellular = DownloadState.Network(connected: true, expensive: true, constrained: false)
    private let lowData = DownloadState.Network(connected: true, expensive: false, constrained: true)
    private let none = DownloadState.Network(connected: false, expensive: false, constrained: false)

    @Test func progressIsTheBytesOverTheCatalogsSize() {
        #expect(DownloadState.of(received: 50, size: 200, cellular: false, installing: false, network: wifi)
            == .downloading(0.25))
        #expect(DownloadState.of(received: 500, size: 200, cellular: true, installing: false, network: wifi)
            == .downloading(1))
        #expect(DownloadState.of(received: 5, size: 0, cellular: true, installing: false, network: wifi)
            == .downloading(0))
        #expect(DownloadState.downloading(0.5).progress == 0.5)
        #expect(DownloadState.waitingForWiFi.progress == nil)
    }

    /// L10: a download the player didn't ask for waits for Wi-Fi on cellular and in Low Data Mode; one they asked
    /// for doesn't. With no network at all, any download waits.
    @Test func whatADownloadWaitsFor() {
        for network in [cellular, lowData] {
            #expect(DownloadState.of(received: 0, size: 9, cellular: false, installing: false, network: network)
                == .waitingForWiFi)
            #expect(DownloadState.of(received: 0, size: 9, cellular: true, installing: false, network: network)
                == .downloading(0))
        }
        #expect(DownloadState.of(received: 3, size: 9, cellular: true, installing: false, network: none)
            == .waitingForNetwork)
        #expect(DownloadState.of(received: 9, size: 9, cellular: false, installing: true, network: none)
            == .installing)
        #expect(DownloadState.Network.unknown == wifi)
    }

    @Test func aFullDiskIsToldApartFromTheNetwork() {
        #expect(DiskSpace.isFull(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
        #expect(DiskSpace.isFull(CocoaError(.fileWriteOutOfSpace)))
        #expect(DiskSpace.isFull(URLError(.cannotWriteToFile)))
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])
        #expect(DiskSpace.isFull(wrapped))
        #expect(!DiskSpace.isFull(URLError(.notConnectedToInternet)))
        #expect(!DiskSpace.isFull(PackError("the download's checksum isn't the pack's")))
    }
}
