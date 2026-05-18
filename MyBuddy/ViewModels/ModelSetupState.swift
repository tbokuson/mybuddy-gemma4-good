import Foundation

enum ModelSetupState: Equatable {
    case checking
    case setupRequired(ModelSetupRequirement)
    case downloading(ModelSetupRequirement, ModelDownloadProgressSnapshot?)
    case failed(ModelSetupRequirement, String)
    case ready

    var requirement: ModelSetupRequirement? {
        switch self {
        case .setupRequired(let requirement),
             .downloading(let requirement, _),
             .failed(let requirement, _):
            return requirement
        case .checking, .ready:
            return nil
        }
    }

    var progress: ModelDownloadProgressSnapshot? {
        switch self {
        case .downloading(_, let progress):
            return progress
        case .checking, .setupRequired, .failed, .ready:
            return nil
        }
    }

    var errorMessage: String? {
        switch self {
        case .failed(_, let message):
            return message
        case .checking, .setupRequired, .downloading, .ready:
            return nil
        }
    }
}
