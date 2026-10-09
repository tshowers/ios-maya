import SwiftUI

// MARK: - Today (3a)

struct SocialTodayView: View {
    @ObservedObject var store: SocialStore
    @Binding var path: [SocialRoute]
    @State private var editing: SocialPost?
    @State private var justApproved: Set<String> = []

    private var review: [SocialPost] {
        store.posts
            .filter { [.needs_review, .on_hold].contains($0.status) || justApproved.contains($0.id) }
            .sorted { $0.slotAt < $1.slotAt }
    }

    private var failed: [SocialPost] {
        store.posts.filter { $0.status == .posted && $0.slotDate >= SocialDates.add(store.today, -1) && !$0.failedChannels.isEmpty }
    }

    private var offStrategy: [SocialPost] {
        store.posts.filter { ($0.offStrategy ?? false) && !($0.offStrategyKept ?? false) && $0.status.isActive }
    }

    private var pendingCount: Int {
        review.filter { !justApproved.contains($0.id) }.count + failed.count + offStrategy.count
    }

    private var headline: String {
        switch pendingCount {
        case 0: return "You’re clear for today."
        case 1: return "1 post needs you today."
        default: return "\(pendingCount) posts need you today."
        }
    }

    private var nextDays: [(date: String, post: SocialPost?)] {
        (1...3).map { offset in
            let date = SocialDates.add(store.today, offset)
            return (date, store.posts.first { $0.slotDate == date && $0.status.isActive })
        }
    }

    var body: some View {
        ScrollView {
            if store.publishingPaused {
                SocialNoChannelsView(store: store)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        SocialKicker(text: SocialDates.format(store.today, "EEE, MMM d"))
                        Text(headline).font(.system(size: 30, weight: .bold)).kerning(-0.8).foregroundStyle(SocialTheme.text)
                    }

                    if !store.unconnectedChannels.isEmpty {
                        SocialNotice(tint: "yellow", text: "\(store.unconnectedChannels.map(\.name).joined(separator: ", ")) can’t post. Their posts are skipped until you connect.") {
                            Button("Open Strategy") { path = [] }.font(.system(size: 14, weight: .bold))
                        }
                    }
                    if store.overview?.pendingStrategy != nil {
                        SocialNotice(tint: "blue", text: "I’m suggesting changes to your strategy. Review them on Strategy.") { EmptyView() }
                    }

                    ForEach(failed) { post in failedCard(post) }
                    ForEach(offStrategy) { post in offStrategyCard(post) }
                    ForEach(review) { post in
                        if justApproved.contains(post.id) { approvedRow(post) } else { card(post) }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SocialKicker(text: "Going out next")
                        ForEach(nextDays, id: \.date) { day in
                            HStack(alignment: .top, spacing: 16) {
                                Text(SocialDates.format(day.date, "EEE d")).font(.system(size: 16, weight: .bold)).frame(width: 60, alignment: .leading)
                                if let post = day.post {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(post.title).font(.system(size: 16)).foregroundStyle(SocialTheme.text)
                                        if post.pinned { HStack(spacing: 6) { Text("Pinned").font(.system(size: 12, weight: .bold)).foregroundStyle(SocialTheme.tint("violet").fg); SocialHelpButton.pinned } }
                                    }
                                } else {
                                    Text("Nothing goes out. A held post kept this slot.").font(.system(size: 14, weight: .semibold)).foregroundStyle(SocialTheme.tint("yellow").fg)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .refreshable { await store.load() }
        .task { await store.loadPosts() }
        .sheet(item: $editing) { post in
            SocialEditPostView(store: store, post: post) { saved in
                justApproved.insert(saved.id)
                editing = nil
            }
        }
    }

    private func card(_ post: SocialPost) -> some View {
        let pillar = store.pillar(post.pillar)
        let isBusy = store.busyPostId == post.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SocialChip(text: pillar.name, colors: SocialTheme.tint(pillar.tint))
                if post.isHeldTwice { SocialChip(text: "Held twice", colors: SocialTheme.tint("pink")) }
                Text(SocialDates.slot(post, today: store.today)).font(.system(size: 14)).foregroundStyle(SocialTheme.muted)
            }
            SocialPostImage(image: post.image, height: 130)
            if (post.rewriteCount ?? 0) > 0, post.status == .needs_review {
                note("You held the first draft. This is my rewrite.")
            } else if post.isHeldTwice {
                note("You held my rewrite too. I’ll stop rewriting until you tell me what to change.")
            }
            Text(post.title).font(.system(size: 20, weight: .bold)).foregroundStyle(SocialTheme.text)
            Text(post.body).font(.system(size: 15)).foregroundStyle(SocialTheme.muted)
            if post.status == .needs_review, let at = post.autoApproveAt {
                HStack(spacing: 6) {
                    Text("Auto-approves at \(SocialDates.clock(at, timeZone: store.timeZone)) unless you hold it\((post.rewriteCount ?? 0) > 0 ? " again" : "").")
                        .font(.system(size: 13)).foregroundStyle(SocialTheme.muted)
                    SocialHelpButton.autoApprove(hours: store.hours)
                }
            }
            Button("Approve") { Task { await approve(post) } }
                .buttonStyle(SocialPillButtonStyle(kind: .primary, height: 50))
                .disabled(isBusy)
            if post.isHeldTwice {
                Button("Edit it yourself") { editing = post }.buttonStyle(SocialPillButtonStyle(kind: .onCard))
                Button("Drop this post") { Task { await store.drop(post) } }.buttonStyle(SocialPillButtonStyle(kind: .onCard)).disabled(isBusy)
                Text("Drop: the posts behind it move up a day.").font(.system(size: 12)).foregroundStyle(SocialTheme.muted).frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 10) {
                    Button("Edit") { editing = post }.buttonStyle(SocialPillButtonStyle(kind: .onCard))
                    HStack(spacing: 6) {
                        Button(post.status == .on_hold ? "Held" : "Hold") { Task { await store.hold(post) } }
                            .buttonStyle(SocialPillButtonStyle(kind: .onCard))
                            .disabled(isBusy || post.status == .on_hold)
                        SocialHelpButton.hold
                    }
                }
            }
        }
        .padding(18)
        .background(SocialTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(post.status == .on_hold ? SocialTheme.pink : .clear, lineWidth: 2))
    }

    /// 2n on a phone.
    private func failedCard(_ post: SocialPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SocialChip(text: "Failed on \(post.failedChannels.map { store.channelNames[$0.channel] ?? $0.channel }.joined(separator: ", "))", colors: SocialTheme.tint("pink"))
            Text(post.title).font(.system(size: 19, weight: .bold))
            ForEach(post.channelResults ?? [], id: \.channel) { row in
                HStack {
                    Image(systemName: row.status == "failed" ? "exclamationmark.circle" : row.status == "posted" ? "checkmark" : "clock")
                    Text(store.channelNames[row.channel] ?? row.channel).font(.system(size: 15, weight: .bold))
                    Spacer()
                    Text(row.status == "failed" ? (row.error?.isEmpty == false ? row.error! : "Didn’t take it") : row.status.capitalized).font(.system(size: 13))
                }
                .foregroundStyle(row.status == "failed" ? SocialTheme.tint("pink").fg : SocialTheme.text)
            }
            ForEach(post.failedChannels, id: \.channel) { row in
                let name = store.channelNames[row.channel] ?? row.channel
                if store.isConnected(row.channel) {
                    Button("Retry \(name) now") { Task { await store.retry(post, channel: row.channel) } }.buttonStyle(SocialPillButtonStyle(kind: .primary, height: 46))
                } else {
                    SocialChannelRow(store: store, channel: SocialChannel(key: row.channel, name: name, role: "", perWeek: 0))
                }
                Button("Skip \(name)") { Task { await store.skip(post, channel: row.channel) } }.buttonStyle(SocialPillButtonStyle(kind: .onCard))
            }
        }
        .padding(18)
        .background(SocialTheme.surface, in: RoundedRectangle(cornerRadius: 28))
    }

    /// 2h on a phone.
    private func offStrategyCard(_ post: SocialPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                SocialChip(text: "Off-strategy", colors: SocialTheme.tint("pink"))
                SocialHelpButton.offStrategy
                Text(SocialDates.slot(post, today: store.today)).font(.system(size: 14)).foregroundStyle(SocialTheme.muted)
            }
            Text(post.title).font(.system(size: 19, weight: .bold))
            Text(post.body).font(.system(size: 15)).foregroundStyle(SocialTheme.muted)
            note("\(post.offStrategyNote ?? "This no longer fits the strategy.") Here’s an edit that fits.")
            if let edit = post.offStrategyEdit {
                Text(edit.body).font(.system(size: 15)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(SocialTheme.bg, in: RoundedRectangle(cornerRadius: 18))
                Button("Use my edit") { Task { await store.offStrategy(post, action: "use-edit") } }.buttonStyle(SocialPillButtonStyle(kind: .primary, height: 50))
            }
            HStack(spacing: 10) {
                Button("Keep yours") { Task { await store.offStrategy(post, action: "keep") } }.buttonStyle(SocialPillButtonStyle(kind: .onCard))
                Button("Edit") { editing = post }.buttonStyle(SocialPillButtonStyle(kind: .onCard))
            }
        }
        .padding(18)
        .background(SocialTheme.surface, in: RoundedRectangle(cornerRadius: 28))
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) { MayaAvatar(size: 22); Text(text).font(.system(size: 14, weight: .bold)) }
            .foregroundStyle(SocialTheme.tint("pink").fg)
    }

    private func approvedRow(_ post: SocialPost) -> some View {
        let green = SocialTheme.tint("green")
        return HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).frame(width: 28, height: 28).background(SocialTheme.bg, in: Circle())
            (Text("Approved. ").bold() + Text("\(post.title) goes out \(SocialDates.slot(post, today: store.today).replacingOccurrences(of: "Today", with: "today")).")).font(.system(size: 15))
            Spacer()
            Button("Undo") {
                Task {
                    await store.undoApprove(post)
                    justApproved.remove(post.id)
                }
            }
            .buttonStyle(SocialPillButtonStyle(kind: .onCard, height: 36)).frame(width: 80)
        }
        .padding(16)
        .background(green.bg, in: RoundedRectangle(cornerRadius: 28))
        .foregroundStyle(green.fg)
    }

    private func approve(_ post: SocialPost) async {
        await store.approve(post)
        if store.posts.first(where: { $0.id == post.id })?.status == .approved { justApproved.insert(post.id) }
    }
}

/// 2c on a phone: nothing connected, so nothing posts.
struct SocialNoChannelsView: View {
    @ObservedObject var store: SocialStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MayaAvatar(size: 64)
            Text("Connect a channel and I’ll start posting.").font(.system(size: 30, weight: .bold)).kerning(-0.8)
            Text("Your strategy is approved and I’ve planned three weeks. Nothing can go out until a channel is connected, so auto-approve is paused and nothing moves on the calendar.")
                .font(.system(size: 16)).foregroundStyle(SocialTheme.muted)
            ForEach(store.strategy?.channels ?? [], id: \.key) { channel in
                SocialChannelRow(store: store, channel: channel)
            }
            SocialNotice(tint: "yellow", text: "Paused. When you connect one, I restart from today; nothing that was skipped is posted late.") { EmptyView() }
        }
        .padding(20)
    }
}

// MARK: - Calendar (3b)

struct SocialCalendarView: View {
    @ObservedObject var store: SocialStore
    @Binding var path: [SocialRoute]
    enum Mode: String, CaseIterable { case week = "Week", month = "Month", queue = "Queue" }
    @State private var mode: Mode = .week
    @State private var selected: SocialPost?

    private var days: [String] {
        switch mode {
        case .week: return (0..<7).map { SocialDates.add(store.today, $0) }
        case .queue: return (-1..<8).map { SocialDates.add(store.today, $0) }
        case .month:
            let first = String(store.today.prefix(8)) + "01"
            return (0..<31).map { SocialDates.add(first, $0) }.filter { $0.prefix(7) == first.prefix(7) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(SocialDates.format(store.today, "MMMM")).font(.system(size: 24, weight: .bold))
                    Spacer()
                    Picker("View", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).frame(width: 210)
                }
                ForEach(days, id: \.self) { date in row(date) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable { await store.loadPosts(force: true) }
        .task { await store.loadPosts() }
        .sheet(item: $selected) { post in
            SocialPostSheet(store: store, post: post) { selected = nil }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
    }

    @ViewBuilder
    private func row(_ date: String) -> some View {
        let post = store.posts.first { $0.slotDate == date && $0.status != .expired && $0.status != .dropped } ?? store.posts.first { $0.slotDate == date }
        let isToday = date == store.today
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(SocialDates.format(date, "EEE")).font(.system(size: 12, weight: .bold))
                Text(SocialDates.format(date, "d")).font(.system(size: 18, weight: .bold))
            }
            .frame(width: 46, height: 46)
            .background(isToday ? SocialTheme.text : .clear, in: Circle())
            .foregroundStyle(isToday ? SocialTheme.bg : SocialTheme.text)

            if let post {
                Button { selected = post } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.title).font(.system(size: 16, weight: .bold)).foregroundStyle(SocialTheme.text).multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            let chip = chip(for: post)
                            SocialChip(text: chip.label, colors: chip.colors)
                            if post.pinned { Text("Pinned").font(.system(size: 12, weight: .bold)).foregroundStyle(SocialTheme.tint("violet").fg) }
                            Text(SocialDates.wallClock(post.time)).font(.system(size: 13)).foregroundStyle(SocialTheme.muted)
                        }
                        if post.movedBackDays > 0, post.status.isActive {
                            Text("Moved back \(post.movedBackDays) day\(post.movedBackDays == 1 ? "" : "s")").font(.system(size: 12, weight: .bold)).foregroundStyle(SocialTheme.tint("yellow").fg)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SocialTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(post.status == .on_hold ? SocialTheme.pink : .clear, lineWidth: 2))
                    .opacity(date < store.today && post.failedChannels.isEmpty ? 0.6 : 1)
                }
                .buttonStyle(.plain)
            } else if let through = store.overview?.plannedThrough, date <= through {
                Text(date < store.today ? "Nothing went out. The held post kept this slot." : "Nothing goes out. The held post kept this slot.")
                    .font(.system(size: 14, weight: .bold)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(SocialTheme.tint("yellow").bg, in: RoundedRectangle(cornerRadius: 20)).foregroundStyle(SocialTheme.tint("yellow").fg)
            } else {
                Text(store.overview?.nextPlanDate.map { "Maya plans this on \(SocialDates.format($0, "MMM d"))" } ?? "Not planned yet")
                    .font(.system(size: 14)).foregroundStyle(SocialTheme.muted).padding(.vertical, 14)
                Spacer()
            }
        }
    }

    private func chip(for post: SocialPost) -> (label: String, colors: (bg: Color, fg: Color)) {
        if store.publishingPaused, post.status.isActive { return ("Paused", SocialTheme.tint("yellow")) }
        if post.status == .posted, !post.failedChannels.isEmpty { return ("Failed", SocialTheme.tint("pink")) }
        if post.offStrategy == true { return (post.offStrategyKept == true ? "Kept" : "Off-strategy", SocialTheme.tint("pink")) }
        if post.isHeldTwice { return ("Held twice", SocialTheme.tint("pink")) }
        return (post.status.label, SocialTheme.status(post.status))
    }
}

// MARK: - Post sheet (3j)

/// A post from the calendar: what it says depends on where it stands (2j).
struct SocialPostSheet: View {
    @ObservedObject var store: SocialStore
    let post: SocialPost
    let onDone: () -> Void
    @State private var editing = false
    @State private var title = ""

    var body: some View {
        let current = store.posts.first { $0.id == post.id } ?? post
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        SocialChip(text: current.status.label, colors: SocialTheme.status(current.status))
                        SocialChip(text: store.pillar(current.pillar).name, colors: SocialTheme.tint(store.pillar(current.pillar).tint))
                        if current.pinned { SocialHelpButton.pinned }
                    }
                    (Text(SocialDates.slot(current, today: store.today)).bold() + Text(" · \(store.channelList(current.channels))").foregroundColor(SocialTheme.muted))
                        .font(.system(size: 15))
                    Text(current.title).font(.system(size: 22, weight: .bold))
                    if current.status == .on_hold {
                        HStack(spacing: 8) { MayaAvatar(size: 22); Text(current.isHeldTwice ? "Held twice. I’ve stopped rewriting it." : "You held this. I’m writing a new version.").font(.system(size: 14, weight: .bold)) }
                            .foregroundStyle(SocialTheme.tint("pink").fg)
                    }
                    if current.status == .planned {
                        TextField("Title", text: $title).padding(.horizontal, 16).frame(height: 46).background(SocialTheme.surface, in: Capsule())
                        Text("Title only. I write the copy and image three days ahead.").font(.system(size: 14)).foregroundStyle(SocialTheme.muted)
                    } else if !current.body.isEmpty {
                        Text(current.body).font(.system(size: 15)).foregroundStyle(SocialTheme.muted)
                    }
                    SocialPostImage(image: current.image)
                    if current.status == .posted {
                        ForEach(current.channelResults ?? [], id: \.channel) { row in
                            HStack {
                                Image(systemName: row.status == "failed" ? "exclamationmark.circle" : "checkmark")
                                Text(store.channelNames[row.channel] ?? row.channel).font(.system(size: 15, weight: .bold))
                                Spacer()
                                if row.status == "failed" {
                                    Button("Retry") { Task { await store.retry(current, channel: row.channel) } }.font(.system(size: 14, weight: .bold))
                                } else if let link = row.url.flatMap(URL.init(string:)) {
                                    Link("View", destination: link).font(.system(size: 14, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 16).frame(height: 46)
                            .background(row.status == "failed" ? SocialTheme.tint("pink").bg : SocialTheme.surface, in: Capsule())
                            .foregroundStyle(row.status == "failed" ? SocialTheme.tint("pink").fg : SocialTheme.text)
                        }
                    }
                    if current.status == .on_hold {
                        Text("It keeps \(SocialDates.format(current.slotDate, "EEEE"))’s slot. If it’s still held then, \(store.behind(current)) unpinned posts move back a day.")
                            .font(.system(size: 14)).foregroundStyle(SocialTheme.muted)
                    }
                }
            }
            actions(current)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { title = current.title }
        .sheet(isPresented: $editing) {
            SocialEditPostView(store: store, post: current) { _ in editing = false; onDone() }
        }
    }

    @ViewBuilder
    private func actions(_ current: SocialPost) -> some View {
        VStack(spacing: 8) {
            switch current.status {
            case .needs_review, .drafted:
                Button(current.status == .drafted ? "Approve early" : "Approve") { Task { await store.approve(current); onDone() } }.buttonStyle(SocialPillButtonStyle(kind: .primary, height: 50))
                HStack(spacing: 8) {
                    Button("Edit") { editing = true }.buttonStyle(SocialPillButtonStyle())
                    if current.pinned {
                        Button("Unpin") { Task { await store.unpin(current); onDone() } }.buttonStyle(SocialPillButtonStyle())
                    } else {
                        Button("Hold") { Task { await store.hold(current); onDone() } }.buttonStyle(SocialPillButtonStyle())
                    }
                }
            case .on_hold:
                if !current.body.isEmpty {
                    Button(current.isHeldTwice ? "Approve" : "Approve this version") { Task { await store.approve(current); onDone() } }.buttonStyle(SocialPillButtonStyle(kind: .primary, height: 50))
                    Button("Edit it yourself") { editing = true }.buttonStyle(SocialPillButtonStyle())
                }
                if current.isHeldTwice {
                    Button("Drop this post") { Task { await store.drop(current); onDone() } }.buttonStyle(SocialPillButtonStyle())
                }
            case .approved:
                HStack(spacing: 8) {
                    Button("Edit") { editing = true }.buttonStyle(SocialPillButtonStyle())
                    Button("Undo approval") { Task { await store.undoApprove(current); onDone() } }.buttonStyle(SocialPillButtonStyle())
                }
            case .planned:
                Button("Save title") { Task { await store.editTitle(current, title: title); onDone() } }
                    .buttonStyle(SocialPillButtonStyle(kind: .primary, height: 50))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || title == current.title)
                if current.pinned { Button("Unpin") { Task { await store.unpin(current); onDone() } }.buttonStyle(SocialPillButtonStyle()) }
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Edit

struct SocialEditPostView: View {
    @ObservedObject var store: SocialStore
    let post: SocialPost
    let onSaved: (SocialPost) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var check: PostCheck?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("Title", text: $title) }
                Section("Post") { TextEditor(text: $text).frame(minHeight: 180) }
                if let check, !check.aligned {
                    Section("This edit doesn’t fit yet") {
                        ForEach(check.reasons, id: \.self) { Text($0) }
                        if let version = check.version {
                            Text(version.body).foregroundStyle(SocialTheme.muted)
                            Button("Use Maya’s version") {
                                title = version.title.isEmpty ? title : version.title
                                text = version.body
                                self.check = nil
                            }
                        }
                    }
                    .foregroundStyle(SocialTheme.tint("pink").fg)
                }
                Section {
                    Text("Saving approves it for \(SocialDates.slot(post, today: store.today).replacingOccurrences(of: "Today", with: "today")). Cancel keeps Maya’s draft and its auto-approve time.")
                        .font(.footnote).foregroundStyle(SocialTheme.muted)
                }
            }
            .navigationTitle("Edit post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button("Save and approve") { Task { await save() } }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { title = post.title; text = post.body }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await store.api.edit(post.id, title: title, body: text)
            store.replace(saved)
            onSaved(saved)
        } catch let error as SocialAPIError {
            if let blocked = error.check { check = blocked } else { store.errorMessage = error.localizedDescription }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
