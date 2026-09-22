import Foundation

/// Every outbound URL the app shows, in one place.
///
/// These only ever open in the browser / App Store app (`Link`); DepthWeaver
/// itself makes no network request. No donation or tip link belongs here
/// (App Review guideline 3.1.1).
enum AppLinks {
    static let appStoreID = "6764146054"

    static let website = URL(string: "https://glandais.github.io/DepthWeaver/")!
    static let support = URL(string: "https://glandais.github.io/DepthWeaver/support/")!
    static let privacy = URL(string: "https://glandais.github.io/DepthWeaver/privacy/")!
    static let sourceCode = URL(string: "https://github.com/glandais/DepthWeaverApp")!
    static let writeReview = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    static let developerApps = URL(string: "https://apps.apple.com/developer/id1891310404")!
}
