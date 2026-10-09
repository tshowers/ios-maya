import SwiftUI

// MARK: - Today (1l)

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

    private var pending: [SocialPost] { review.filter { !justApproved.contains($0.id) } }

    private var headline: String {
        switch pending.count {
        case 0: return "You’re clear for today."
        case 1: return "1 post needs you today."
        default: return "\(pending.count) posts need you today."
        }
    }

    private var nextDays: [(date: String, post: SocialPost?)] {
        (1...3).map { offset in
            let date = SocialDates.add(store.today, offset)
            return (date, store.posts.first { $0.slotDate == date && $0.status != .expired })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    SocialKicker(text: SocialDates.format(store.today, "EEE, MMM d"))
                    Text(headline).font(.system(size: 30, weight: .bold)).kerning(-0.8).foregroundStyle(SocialTheme.text)
                }

                if !store.unconnectedChannels.isEmpty {
                    SocialNotice(tint: "yellow", text: "\(store.unconnectedChannels.map(\.name).joined(separator: ", ")) \(store.unconnectedChannels.count == 1 ? "isn’t" : "aren’t") connected. Those posts can’t go out until you connect.") {
                        Button("Connect") { path = [.profile] }.buttonStyle(SocialPillButtonStyle(kind: .onCard, height: 38)).frame(maxWidth: 160)
                    }
                }
                if store.overview?.pendingStrategy != nil {
                    SocialNotice(tint: "blue", text: "I’m suggesting changes to your strategy. Review them on Strategy.") { EmptyView() }
                }

                ForEach(review) { post in
                    if justApproved.contains(post.id) {
                        approvedRow(post)
                    } else {
                        card(post)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SocialKicker(text: "Going out next")
                    ForEach(nextDays, id: \.date) { day in
                        HStack(alignment: .top, spacing: 16) {
                            Text(SocialDates.format(day.date, "EEE d")).font(.system(size: 17, weight: .bold)).frame(width: 64, alignment: .leading)
                            if let post = day.post {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(post.title).font(.system(size: 17)).foregroundStyle(SocialTheme.text)
                                    HStack(spacing: 6) {
                                        if post.pinned { Text("Pinned").font(.system(size: 12, weight: .bold)).foregroundStyle(SocialTheme.tint("violet").fg); SocialHelpButton.pinned }
                                        if post.movedBackDays > 0 { Text("Moved back \(post.movedBackDays) day\(post.movedBackDays == 1 ? "" : "s")").font(.system(size: 12, weight: .bold)).foregroundStyle(SocialTheme.tint("yellow").fg) }
                                    }
                                }
                            } else {
                                Text("Nothing goes out. A held post kept this slot.").font(.system(size: 15, weight: .semibold)).foregroundStyle(SocialTheme.tint("yellow").fg)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .refreshable { await store.load() }
        .task { await store.loadPosts() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { path = [.newPost] } label: { Image(systemName: "plus").font(.system(size: 18, weight: .bold)) }
                    .accessibilityLabel("New post")
            }
        }
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
                Text(SocialDates.slot(post, today: store.today)).font(.system(size: 15)).foregroundStyle(SocialTheme.muted)
            }
            if (post.rewriteCount ?? 0) > 0, post.status == .needs_review {
                HStack(spacing: 8) { MayaAvatar(size: 22); Text("You held the first draft. This is my rewrite.").font(.system(size: 14, weight: .bold)) }
                    .foregroundStyle(SocialTheme.tint("pink").fg)
            }
            Text(post.title).font(.system(size: 21, weight: .bold)).foregroundStyle(SocialTheme.text)
            Text(post.body).font(.system(size: 16)).foregroundStyle(SocialTheme.muted)
            Text(store.channelList(post.channels)).font(.system(size: 13, weight: .semibold)).foregroundStyle(SocialTheme.muted)
            if post.status == .needs_review, let at = post.autoApproveAt {
                HStack(spacing: 6) {
                    Text("Auto-approves at \(SocialDates.clock(at, timeZone: store.timeZone)) unless you hold it\((post.rewriteCount ?? 0) > 0 ? " again" : "").")
                        .font(.system(size: 14)).foregroundStyle(SocialTheme.muted)
                    SocialHelpButton.autoApprove(hours: store.hours)
                }
            } else if post.status == .on_hold {
                Text("On hold. If its slot arrives still held, nothing goes out that day.").font(.system(size: 14, weight: .semibold)).foregroundStyle(SocialTheme.tint("pink").fg)
            }
            Button("Approve") { Task { await approve(post) } }
                .buttonStyle(SocialPillButtonStyle(kind: .primary, height: 50))
                .disabled(isBusy)
            HStack(spacing: 10) {
                Button("Edit") { editing = post }.buttonStyle(SocialPillButtonStyle(kind: .onCard))
                HStack(spacing: 6) {
                    Button(post.status == .on_hold ? "Held" : "Hold") { Task { await store.hold(post) } }
                        .buttonStyle(SocialPillButtonStyle(kind: .onCard))
                        .disabled(isBusy || post.status == .on_hold)
                    SocialHelpButton.hold
                }
            }
            if (post.rewriteCount ?? 0) > 0, post.status == .needs_review {
                Text("If you hold it again, it keeps \(SocialDates.format(post.slotDate, "EEEE"))’s slot and the \(store.behind(post)) unpinned posts behind it move back a day.")
                    .font(.system(size: 13)).foregroundStyle(SocialTheme.muted)
            }
        }
        .padding(20)
        .background(SocialTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(post.status == .on_hold ? SocialTheme.pink : .clear, lineWidth: 2))
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

// MARK: - Calendar (1m)

struct SocialCalendarView: View {
    @ObservedObject var store: SocialStore
    @Binding var path: [SocialRoute]
    @State private var month = false
    @State private var weekStart = ""
    @State private var selected: SocialPost?

    private var days: [String] {
        if month {
            let first = String(store.today.prefix(8)) + "01"
            return (0..<31).map { SocialDates.add(first, $0) }.filter { $0.prefix(7) == first.prefix(7) }
        }
        let start = weekStart.isEmpty ? store.today : weekStart
        return (0..<7).map { SocialDates.add(start, $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(SocialDates.format(days.first ?? store.today, "MMMM")).font(.system(size: 26, weight: .bold))
                    Spacer()
                    Picker("View", selection: $month) { Text("Week").tag(false); Text("Month").tag(true) }
                        .pickerStyle(.segmented).frame(width: 170)
                }
                if !month {
                    HStack(spacing: 6) {
                        ForEach(days, id: \.self) { date in
                            let post = store.posts.first { $0.slotDate == date }
                            let isToday = date == store.today
                            VStack(spacing: 6) {
                                Text(SocialDates.format(date, "EEEEE")).font(.system(size: 12, weight: .bold))
                                Text(SocialDates.format(date, "d")).font(.system(size: 17, weight: .bold))
                                Circle().fill(dot(post)).frame(width: 7, height: 7)
                            }
                            .frame(maxWidth: .infinity, minHeight: 74)
                            .background(isToday ? SocialTheme.text : SocialTheme.surface, in: Capsule())
                            .foregroundStyle(isToday ? SocialTheme.bg : SocialTheme.text)
                        }
                    }
                }
                ForEach(days, id: \.self) { date in
                    row(date)
                }
            }
            .padding(20)
        }
        .refreshable { await store.loadPosts(force: true) }
        .task { await store.loadPosts() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { path = [.newPost] } label: { Image(systemName: "plus").font(.system(size: 18, weight: .bold)) }
                    .accessibilityLabel("New post")
            }
        }
        .sheet(item: $selected) { post in
            SocialPostSheet(store: store, post: post) { selected = nil }
                .presentationDetents([.medium, .large])
        }
    }

    private func dot(_ post: SocialPost?) -> Color {
        guard let post else { return .clear }
        if post.status == .on_hold { return SocialTheme.pink }
        return SocialTheme.tint(store.pillar(post.pillar).tint).fg
    }

    @ViewBuilder
    private func row(_ date: String) -> some View {
        let post = store.posts.first { $0.slotDate == date && $0.status != .expired } ?? store.posts.first { $0.slotDate == date }
        VStack(alignment: .leading, spacing: 6) {
            Text(date == store.today ? "Today · \(SocialDates.format(date, "EEE d"))" : SocialDates.format(date, "EEEE, MMM d"))
                .font(.system(size: 13, weight: .bold)).foregroundStyle(SocialTheme.muted)
            if let post {
                Button { selected = post } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            SocialChip(text: store.pillar(post.pillar).name, colors: SocialTheme.tint(store.pillar(post.pillar).tint))
                            if post.pinned { Text("Pinned").font(.system(size: 12, weight: .bold)).foregroundStyle(SocialTheme.tint("violet").fg) }
                            Spacer()
                            SocialChip(text: post.status.label, colors: SocialTheme.status(post.status))
                        }
                        Text(post.title).font(.system(size: 16, weight: .bold)).foregroundStyle(SocialTheme.text).multilineTextAlignment(.leading)
                        HStack {
                            Text("\(SocialDates.wallClock(post.time)) · \(store.channelList(post.channels))").font(.system(size: 13)).foregroundStyle(SocialTheme.muted)
                            if post.movedBackDays > 0, post.status != .posted {
                                Text("Moved back \(post.movedBackDays) day\(post.movedBackDays == 1 ? "" : "s")").font(.system(size: 12, weight: .bold)).foregroundStyle(SocialTheme.tint("yellow").fg)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SocialTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(post.status == .on_hold ? SocialTheme.pink : .clear, lineWidth: 2))
                    .opacity(date < store.today ? 0.55 : 1)
                }
                .buttonStyle(.plain)
            } else if let through = store.overview?.plannedThrough, date <= through {
                Text(date < store.today ? "Nothing went out. The held post kept this slot." : "Nothing goes out. The held post kept this slot.")
                    .font(.system(size: 14, weight: .bold)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(SocialTheme.tint("yellow").bg, in: RoundedRectangle(cornerRadius: 22)).foregroundStyle(SocialTheme.tint("yellow").fg)
            } else {
                Text(store.overview?.nextPlanDate.map { "Maya plans this on \(SocialDates.format($0, "MMM d"))" } ?? "Not planned yet")
                    .font(.system(size: 14)).foregroundStyle(SocialTheme.muted).padding(.vertical, 6)
            }
        }
    }
}

/// A post from the calendar: read it, approve, hold or edit.
struct SocialPostSheet: View {
    @ObservedObject var store: SocialStore
    let post: SocialPost
    let onDone: () -> Void
    @State private var editing = false

    var body: some View {
        let current = store.posts.first { $0.id == post.id } ?? post
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SocialChip(text: store.pillar(current.pillar).name, colors: SocialTheme.tint(store.pillar(current.pillar).tint))
                    SocialChip(text: current.status.label, colors: SocialTheme.status(current.status))
                    if current.pinned { SocialHelpButton.pinned }
                }
                Text(current.title).font(.system(size: 22, weight: .bold))
                Text("\(SocialDates.slot(current, today: store.today)) · \(store.channelList(current.channels))").foregroundStyle(SocialTheme.muted)
                Text(current.body.isEmpty ? "Maya writes this one three days before it goes out." : current.body).foregroundStyle(SocialTheme.muted)
                if !current.body.isEmpty, [.drafted, .needs_review, .on_hold].contains(current.status) {
                    Button("Approve") { Task { await store.approve(current); onDone() } }.buttonStyle(SocialPillButtonStyle(kind: .primary, height: 50))
                }
                HStack(spacing: 10) {
                    if !current.body.isEmpty, current.status.isActive {
                        Button("Edit") { editing = true }.buttonStyle(SocialPillButtonStyle())
                    }
                    if [.planned, .drafted, .needs_review, .approved].contains(current.status) {
                        Button("Hold") { Task { await store.hold(current); onDone() } }.buttonStyle(SocialPillButtonStyle())
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $editing) {
            SocialEditPostView(store: store, post: current) { _ in editing = false; onDone() }
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
                    Section("This doesn’t fit the strategy yet") {
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
