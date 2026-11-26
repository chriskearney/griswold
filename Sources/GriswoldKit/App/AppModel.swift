import AppKit
import Combine
import Foundation
import ServiceManagement

public struct UpdateInfo: Decodable, Equatable {
    public let version: String
    public let url: String
    public let notes: String?
}

public enum UpdateChecker {
    static let feed = URL(string: "https://chonkbase.net/griswold/version.json")!
    public static let homepage = URL(string: "https://chonkbase.net/griswold/")!

    public static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    /// Compares dotted version numbers numerically ("1.10.0" is newer than "1.9.2").
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// Asks the website whether a newer build exists. Sends nothing about the user.
    static func check(completion: @escaping (UpdateInfo?) -> Void) {
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Griswold/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            var result: UpdateInfo?
            if let data, (response as? HTTPURLResponse)?.statusCode == 200,
               let info = try? JSONDecoder().decode(UpdateInfo.self, from: data),
               isNewer(info.version, than: currentVersion) {
                result = info
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// What the menus and settings window talk to.
public final class AppModel: ObservableObject {
    public let settings: Settings
    public let manager: OverlayManager
    @Published public var launchAtLogin = false
    @Published public var loginError: String?
    @Published public var update: UpdateInfo?
    @Published public var updateStatus: String?
    var openSettings: () -> Void = {}
    var closePopover: () -> Void = {}

    private static let lastCheckKey = "updates.lastCheck"

    public init(settings: Settings, manager: OverlayManager) {
        self.settings = settings
        self.manager = manager
        launchAtLogin = LoginItem.isEnabled
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item. Move Griswold to Applications and try again."
        }
        launchAtLogin = LoginItem.isEnabled
    }

    public func surprise(_ kind: SurpriseKind? = nil) {
        if !settings.config.enabled { settings.config.enabled = true }
        manager.surprise(kind)
    }

    /// Checks at most once a day unless the user asked.
    public func checkForUpdates(userInitiated: Bool) {
        let defaults = UserDefaults.standard
        if !userInitiated {
            guard settings.config.checkForUpdates else { return }
            let last = defaults.double(forKey: AppModel.lastCheckKey)
            guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        }
        defaults.set(Date().timeIntervalSince1970, forKey: AppModel.lastCheckKey)
        if userInitiated { updateStatus = "Checking…" }
        UpdateChecker.check { [weak self] info in
            guard let self else { return }
            self.update = info
            if userInitiated {
                self.updateStatus = info == nil ? "You're up to date." : "Version \(info!.version) is available."
            }
        }
    }

    public func openDownloadPage() {
        let target = update.flatMap { URL(string: $0.url) } ?? UpdateChecker.homepage
        NSWorkspace.shared.open(target)
    }

    /// "29 days until Christmas", and friends.
    public static func countdown(from date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return "" }
        if month == 12, day == 25 { return "Merry Christmas!" }
        if month == 12, day == 24 { return "It's Christmas Eve" }
        if month == 12, day > 25 { return "Happy holidays" }
        guard
            let today = calendar.date(from: DateComponents(year: year, month: month, day: day)),
            let christmas = calendar.date(from: DateComponents(year: year, month: 12, day: 25)),
            let days = calendar.dateComponents([.day], from: today, to: christmas).day
        else { return "" }
        return days == 1 ? "1 day until Christmas" : "\(days) days until Christmas"
    }
}
