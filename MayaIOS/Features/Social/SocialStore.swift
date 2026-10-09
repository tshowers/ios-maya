import Foundation
import SwiftUI

/// Where the signed-in person stands with Maya Social
/// (design_handoff_maya_social_entry, "Access and routing").
enum SocialAccess: Equatable {
    case loading
    case firstRun
    case noStrategy
    case ready
    case failed(String)
}

/// Maya Social's state for the Social tabs: the overview (settings,
/// profile, strategy) and the posts around today, plus the owner's actions.
@MainActor
final class SocialStore: ObservableObject {
    @Published private(set) var overview: SocialOverview?
    @Published private(set) var posts: [SocialPost] = []
    @Published private(set) var access: SocialAccess = .loading
    @Published var busyPostId: String?
    @Published var errorMessage: String?
    /// "Not now" on the first-run screen lasts until the app restarts.
    @Published var skippedFirstRun = false

    let api: SocialAPIClient
    private var postsLoadedFor = ""

    init(api: SocialAPIClient) {
        self.api = api
    }

    var strategy: SocialStrategy? { overview?.strategy }
    var today: String { overview?.today ?? SocialDates.key(Date(), timeZone: .current) }
    var timeZone: TimeZone { TimeZone(identifier: overview?.timeZone ?? "") ?? .current }
    var hours: Int { overview?.autoApproveHours ?? 6 }
    var channelNames: [String: String] { overview?.channels ?? [:] }

    var unconnectedChannels: [SocialChannel] {
        guard let strategy, let connected = overview?.connectedChannels else { return [] }
        return strategy.channels.filter { !connected.contains($0.key) }
    }

    func pillar(_ key: String) -> Pillar {
        strategy?.pillars.first { $0.key == key }
            ?? Pillar(key: key, name: key, share: 0, description: "", maxOneIn: 0, tint: "blue")
    }

    func channelList(_ keys: [String]) -> String {
        let total = strategy?.channels.count ?? 0
        if total > 2, keys.count == total { return "All \(total) channels" }
        return keys.map { channelNames[$0] ?? $0 }.joined(separator: ", ")
    }

    /// Signed out or a different account: forget everything.
    func reset() {
        overview = nil
        posts = []
        postsLoadedFor = ""
        access = .loading
        skippedFirstRun = false
    }

    // MARK: Loading

    func load() async {
        do {
            let overview = try await api.overview()
            apply(overview)
            if overview.strategy != nil { await loadPosts(force: true) }
        } catch {
            access = .failed(error.localizedDescription)
        }
    }

    func apply(_ overview: SocialOverview) {
        self.overview = overview
        if overview.onboardedAt == nil, !skippedFirstRun {
            access = .firstRun
        } else if overview.strategy == nil {
            access = .noStrategy
        } else {
            access = .ready
        }
    }

    /// Yesterday through two months out: enough for Today, the week and
    /// counting what's behind a held post.
    func loadPosts(force: Bool = false) async {
        let from = SocialDates.add(today, -1)
        guard force || postsLoadedFor != from else { return }
        do {
            posts = try await api.posts(from: from, to: SocialDates.add(today, 60))
            postsLoadedFor = from
            SocialReviewReminders.schedule(for: posts, timeZone: timeZone)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func posts(from: String, to: String) async -> [SocialPost] {
        (try? await api.posts(from: from, to: to)) ?? []
    }

    // MARK: Post actions

    func approve(_ post: SocialPost) async { await act(post) { try await self.api.approve(post.id) } }
    func undoApprove(_ post: SocialPost) async { await act(post) { try await self.api.undoApprove(post.id) } }
    func hold(_ post: SocialPost) async { await act(post) { try await self.api.hold(post.id) } }

    func replace(_ saved: SocialPost) {
        if let index = posts.firstIndex(where: { $0.id == saved.id }) { posts[index] = saved } else { posts.append(saved) }
    }

    private func act(_ post: SocialPost, _ call: @escaping () async throws -> SocialPost) async {
        busyPostId = post.id
        defer { busyPostId = nil }
        do {
            replace(try await call())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Unpinned posts after this one: what moves back if it's held through its slot.
    func behind(_ post: SocialPost) -> Int {
        posts.filter { !$0.pinned && $0.slotDate > post.slotDate && $0.status.isActive }.count
    }
}

// MARK: - Look

/// The Find family tokens (taliferro-ui/styles/tokens.css) the Maya Social
/// design uses, in light and dark.
enum SocialTheme {
    static let bg = Color(light: 0xFFFFFF, dark: 0x0C0E13)
    static let surface = Color(light: 0xF2F3F6, dark: 0x171A22)
    static let surface2 = Color(light: 0xE4E7ED, dark: 0x242936)
    static let text = Color(light: 0x0F1115, dark: 0xF2F4F8)
    static let muted = Color(light: 0x5A6170, dark: 0x9AA2B2)
    static let blue = Color(light: 0x2F6BFF, dark: 0x3D7BFF)
    static let blueInk = Color(light: 0x1F55E0, dark: 0x86AEFF)
    static let pink = Color(light: 0xFF4FA8, dark: 0xFF6BB8)

    /// Tint background and foreground: green, blue, violet, yellow, pink.
    static func tint(_ name: String) -> (bg: Color, fg: Color) {
        switch name {
        case "green": return (Color(light: 0xE0F6E6, dark: 0x0E2C19), Color(light: 0x17703A, dark: 0x80E2A4))
        case "violet": return (Color(light: 0xEFE5FF, dark: 0x2A1847), Color(light: 0x6427C9, dark: 0xCDAAFF))
        case "yellow": return (Color(light: 0xFFF4C2, dark: 0x2F2906), Color(light: 0x6E5700, dark: 0xFFE56A))
        case "pink": return (Color(light: 0xFFE3F1, dark: 0x3A1029), Color(light: 0xA8105A, dark: 0xFF92C9))
        default: return (Color(light: 0xE3ECFF, dark: 0x15254A), Color(light: 0x1D4FD6, dark: 0xA3C1FF))
        }
    }

    static func status(_ status: PostStatus) -> (bg: Color, fg: Color) {
        switch status {
        case .posted, .approved: return tint("green")
        case .needs_review: return tint("blue")
        case .on_hold: return tint("pink")
        case .expired: return tint("yellow")
        case .drafted: return (surface2, text)
        case .planned: return (bg, muted)
        }
    }
}

private extension Color {
    init(light: Int, dark: Int) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Dates

/// Calendar days are "YYYY-MM-DD" in the owner's time zone.
enum SocialDates {
    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func date(_ key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return utcCalendar().date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date()
    }

    static func key(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func add(_ key: String, _ days: Int) -> String {
        let next = utcCalendar().date(byAdding: .day, value: days, to: date(key)) ?? date(key)
        return self.key(next, timeZone: TimeZone(identifier: "UTC")!)
    }

    static func format(_ key: String, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = pattern
        return formatter.string(from: date(key))
    }

    /// "Thu, Oct 8"
    static func short(_ key: String) -> String { format(key, "EEE, MMM d") }

    static func instant(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    /// "4:00 PM" for an instant in the owner's zone.
    static func clock(_ iso: String?, timeZone: TimeZone) -> String {
        guard let date = instant(iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// "4:00 PM" for a post's HH:MM.
    static func wallClock(_ time: String) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? 9
        let minute = parts.count > 1 ? parts[1] : 0
        return String(format: "%d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, minute, hour < 12 ? "AM" : "PM")
    }

    /// "Today at 4:00 PM" / "Fri, Oct 9 at 9:00 AM"
    static func slot(_ post: SocialPost, today: String) -> String {
        "\(post.slotDate == today ? "Today" : short(post.slotDate)) at \(wallClock(post.time))"
    }
}
