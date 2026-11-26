import Foundation

enum Launch {
    static let freePeriod = false
    static let proProduct = "com.hgsldswk.before3pm.pro"
    static let trialProduct = "com.hgsldswk.before3pm.trial"

    static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var isUITesting: Bool {
        #if DEBUG
        return arguments.contains("-ui-testing")
        #else
        return false
        #endif
    }
    static var isFree: Bool {
        freePeriod && !(isUITesting && arguments.contains(where: {
            ["-paid-mode", "-paywall", "-expired"].contains($0)
        }))
    }

    static func value(_ flag: String, in args: [String] = arguments) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
