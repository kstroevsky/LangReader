import Foundation

package enum ReadAloudPlaybackPhase: Equatable {
    case idle
    case loading
    case playing
    case paused

    package var isActive: Bool {
        self != .idle
    }

    package var isLoading: Bool {
        self == .loading
    }

    package var isPaused: Bool {
        self == .paused
    }
}

package enum ReadAloudPlaybackEvent: Equatable {
    case startLoading
    case playbackStarted
    case pause
    case resume
    case stop
}
