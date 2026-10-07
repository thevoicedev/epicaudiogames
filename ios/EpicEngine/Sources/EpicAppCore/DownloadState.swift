// Store.kt's downloading map, and its full-disk check (outOfSpace): a pack's download as its store row shows it.

import Foundation

/**
 * A pack's download as its row in the store sheet shows it. iOS downloads in a background URLSession, which waits
 * instead of failing when it can't use the network. A download the player didn't ask for (at launch, or as the app
 * comes back) doesn't use cellular or Low Data Mode: on those it waits for Wi-Fi (L10), until "Download now" lets it.
 */
public enum DownloadState: Equatable, Sendable {
    /// How far it has got (0 to 1).
    case downloading(Double)
    case waitingForWiFi
    /// No network at all: it carries on when there is one.
    case waitingForNetwork
    /// The zip is being checked and unpacked.
    case installing

    /// The network as a download sees it (NWPath's status, isExpensive and isConstrained).
    public struct Network: Equatable, Sendable {
        public var connected: Bool
        /// Cellular, or a phone's hotspot.
        public var expensive: Bool
        /// Low Data Mode.
        public var constrained: Bool

        public init(connected: Bool, expensive: Bool, constrained: Bool) {
            self.connected = connected
            self.expensive = expensive
            self.constrained = constrained
        }

        /// Before the first look at the network: taken as Wi-Fi.
        public static let unknown = Network(connected: true, expensive: false, constrained: false)
    }

    /// A download of [size] bytes with [received] so far, on [network]; [cellular]: it may use an expensive or
    /// constrained network.
    public static func of(received: Int64, size: Int64, cellular: Bool, installing: Bool, network: Network)
        -> DownloadState {
        if installing { return .installing }
        if !network.connected { return .waitingForNetwork }
        if !cellular && (network.expensive || network.constrained) { return .waitingForWiFi }
        return .downloading(size > 0 ? min(max(Double(received) / Double(size), 0), 1) : 0)
    }

    /// The progress bar's value, while downloading.
    public var progress: Double? {
        if case .downloading(let p) = self { return p }
        return nil
    }
}

/// Telling a full disk apart from the network's troubles (Store.kt's outOfSpace).
public enum DiskSpace {
    /// Whether [error] is the disk being full (ENOSPC, Foundation's out of space, URLSession's can't write), or has
    /// that as an underlying error.
    public static func isFull(_ error: any Error) -> Bool {
        var next: NSError? = error as NSError
        var depth = 0
        while let e = next, depth < 8 {
            switch (e.domain, e.code) {
            case (NSPOSIXErrorDomain, Int(ENOSPC)), (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError),
                 (NSURLErrorDomain, NSURLErrorCannotWriteToFile):
                return true
            default:
                next = e.userInfo[NSUnderlyingErrorKey] as? NSError
                depth += 1
            }
        }
        return false
    }
}
