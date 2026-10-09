import SwiftUI

// MARK: - First run (1p)

struct SocialWelcomeView: View {
    @ObservedObject var store: SocialStore
    @State private var hours = 6
    @State private var isBusy = false

    private let rules: [(String, String)] = [
        ("I decide what goes out and when.", "Every post fits the strategy I build from your profile."),
        ("Posts approve themselves", "after the time you pick below, unless you hold them."),
        ("A held post keeps its slot.", "Unpinned posts behind it move back a day."),
        ("Pinned posts never move.", "If one isn’t approved by its date, it expires."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MayaAvatar(size: 64)
                SocialChip(text: "INCLUDED WITH YOUR MAYA PLAN", colors: SocialTheme.tint("green"))
                Text("Before I take over your calendar, here’s how I work.")
                    .font(.system(size: 32, weight: .bold)).kerning(-0.8)
                    .foregroundStyle(SocialTheme.text)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30).background(SocialTheme.surface, in: Circle())
                            (Text(rule.0).bold() + Text(" " + rule.1)).font(.system(size: 16)).foregroundStyle(SocialTheme.text)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Auto-approve after").font(.system(size: 16, weight: .bold))
                    Picker("Auto-approve after", selection: $hours) {
                        ForEach([2, 4, 6], id: \.self) { Text("\($0) hours").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("You can change this later in Social profile.").font(.system(size: 14)).foregroundStyle(SocialTheme.muted)
                }
                .padding(20)
                .background(SocialTheme.surface, in: RoundedRectangle(cornerRadius: 28))

                Button {
                    Task {
                        isBusy = true
                        defer { isBusy = false }
                        do {
                            store.apply(try await store.api.onboard(autoApproveHours: hours))
                            await MayaPushService.shared.requestPermission()
                        } catch {
                            store.errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    HStack { if isBusy { ProgressView().tint(.white) }; Text("Set up Maya Social") }
                }
                .buttonStyle(SocialPillButtonStyle(kind: .primary, height: 56))
                .disabled(isBusy)

                Button("Not now") {
                    store.skippedFirstRun = true
                    if let overview = store.overview { store.apply(overview) }
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SocialTheme.blueInk)
                .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }
}

// MARK: - No strategy (1h), incomplete profile (1n), strategy review

struct SocialSetupView: View {
    @ObservedObject var store: SocialStore
    let openProfile: () -> Void

    @State private var companyName = ""
    @State private var companyGoal = ""
    @State private var productName = ""
    @State private var productDescription = ""
    @State private var isBuilding = false
    @State private var isSaving = false

    private var missing: [String] { store.overview?.missing ?? [] }
    private var formValid: Bool {
        !companyName.trimmingCharacters(in: .whitespaces).isEmpty
            && !companyGoal.trimmingCharacters(in: .whitespaces).isEmpty
            && (!missing.contains("products") || !productName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isBuilding {
                    building
                } else if let pending = store.overview?.pendingStrategy {
                    SocialNotice(tint: "blue", text: "Here’s my first strategy for you. Nothing is scheduled until you approve it. Then I’ll plan three weeks and draft the first posts.") { EmptyView() }
                    SocialStrategyBody(store: store, strategy: pending)
                    Button("Regenerate") { generate() }
                        .buttonStyle(SocialPillButtonStyle(height: 46))
                } else if missing.isEmpty {
                    noStrategy
                } else {
                    incomplete
                }
            }
            .padding(20)
        }
        // 3h: once built, Approve stays pinned to the bottom.
        .safeAreaInset(edge: .bottom) {
            if !isBuilding, store.overview?.pendingStrategy != nil {
                Button {
                    Task {
                        isSaving = true
                        defer { isSaving = false }
                        do {
                            store.apply(try await store.api.approveStrategy())
                            await store.loadPosts(force: true)
                            await MayaPushService.shared.requestPermission()
                        } catch { store.errorMessage = error.localizedDescription }
                    }
                } label: {
                    HStack { if isSaving { ProgressView().tint(.white); Text("Planning your calendar…") } else { Text("Approve and plan my calendar") } }
                }
                .buttonStyle(SocialPillButtonStyle(kind: .primary, height: 54))
                .disabled(isSaving)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(SocialTheme.bg)
            }
        }
        .onAppear {
            companyName = store.overview?.profile?.companyName ?? ""
            companyGoal = store.overview?.profile?.companyGoal ?? ""
        }
    }

    /// 3h: what Maya is doing while she builds.
    private var building: some View {
        VStack(alignment: .leading, spacing: 18) {
            MayaAvatar(size: 76)
                .padding(5)
                .background(SocialTheme.tint("blue").bg, in: Circle())
            Text("Building your strategy…").font(.system(size: 30, weight: .bold)).kerning(-0.8)
            VStack(spacing: 8) {
                buildStep("Read your profile", state: .done)
                buildStep("Picking content pillars", state: .doing)
                buildStep("Setting channel cadence", state: .doing)
                buildStep("Planning three weeks, once you approve", state: .next)
            }
        }
    }

    private enum StepState { case done, doing, next }

    private func buildStep(_ text: String, state: StepState) -> some View {
        HStack(spacing: 12) {
            switch state {
            case .done: Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(SocialTheme.tint("green").fg).frame(width: 22)
            case .doing: ProgressView().frame(width: 22)
            case .next: Circle().strokeBorder(SocialTheme.surface2, lineWidth: 2).frame(width: 22, height: 22)
            }
            Text(text).font(.system(size: 16, weight: .bold)).foregroundStyle(state == .next ? SocialTheme.muted : SocialTheme.text)
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .background(state == .next ? Color.clear : SocialTheme.surface, in: Capsule())
    }

    private var noStrategy: some View {
        VStack(alignment: .leading, spacing: 18) {
            MayaAvatar(size: 64)
            Text("I don’t have a social strategy for you yet.").font(.system(size: 30, weight: .bold)).kerning(-0.6)
            Text("I’ll build one from your profile: pillars, channels, how often to post and the rules I follow. Nothing goes on the calendar until you’ve seen it.")
                .font(.system(size: 17)).foregroundStyle(SocialTheme.muted)
            requirement("Company name", store.overview?.profile?.companyName ?? "")
            requirement("Company goal", store.overview?.profile?.companyGoal ?? "")
            requirement("Products and services", (store.overview?.profile?.products ?? []).map(\.name).joined(separator: ", "))
            Button { generate() } label: { Label("Generate strategy from my profile", systemImage: "sparkles") }
                .buttonStyle(SocialPillButtonStyle(kind: .primary, height: 56))
            Button("Review profile first", action: openProfile)
                .font(.system(size: 15, weight: .bold)).foregroundStyle(SocialTheme.blueInk).frame(maxWidth: .infinity)
        }
    }

    private func requirement(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).frame(width: 26, height: 26)
                .background(SocialTheme.tint("green").bg, in: Circle()).foregroundStyle(SocialTheme.tint("green").fg)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 15, weight: .bold))
                Text(value).font(.system(size: 14)).foregroundStyle(SocialTheme.muted).lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(SocialTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    // 1n
    private var incomplete: some View {
        VStack(alignment: .leading, spacing: 18) {
            let pink = SocialTheme.tint("pink")
            VStack(alignment: .leading, spacing: 6) {
                Label("I can’t build a strategy yet.", systemImage: "exclamationmark.circle").font(.system(size: 18, weight: .bold))
                Text("Your profile is missing \(missing.count) of the 3 things I need. Fill \(missing.count == 1 ? "it" : "them") in here and \(missing.count == 1 ? "it’ll" : "they’ll") save to your profile.").font(.system(size: 14))
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(pink.bg, in: RoundedRectangle(cornerRadius: 24)).foregroundStyle(pink.fg)

            field("Company name", text: $companyName, missing: missing.contains("companyName"))
            field("Company goal", text: $companyGoal, missing: missing.contains("companyGoal"), prompt: "e.g. Book 20 discovery calls a month")
            if missing.contains("products") {
                field("Product or service", text: $productName, missing: true, prompt: "Name")
                field("What it does", text: $productDescription, missing: false, prompt: "One line on what it does")
            }
            Button {
                Task { await saveAndGenerate() }
            } label: {
                HStack { if isSaving { ProgressView().tint(.white) }; Text("Save and generate strategy") }
            }
            .buttonStyle(SocialPillButtonStyle(kind: .primary, height: 54))
            .disabled(!formValid || isSaving)
            .opacity(formValid ? 1 : 0.4)
            Text("Saves to your Taliferro profile").font(.system(size: 13)).foregroundStyle(SocialTheme.muted).frame(maxWidth: .infinity)
        }
    }

    private func field(_ label: String, text: Binding<String>, missing: Bool, prompt: String = "") -> some View {
        let empty = text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 15, weight: .bold))
            TextField(prompt, text: text)
                .padding(.horizontal, 18).frame(height: 48)
                .background(missing && empty ? SocialTheme.bg : SocialTheme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(missing && empty ? SocialTheme.pink : .clear, lineWidth: 2))
        }
    }

    private func saveAndGenerate() async {
        isSaving = true
        defer { isSaving = false }
        guard var profile = store.overview?.profile else { return }
        profile.companyName = companyName.trimmingCharacters(in: .whitespaces)
        profile.companyGoal = companyGoal.trimmingCharacters(in: .whitespaces)
        if !productName.trimmingCharacters(in: .whitespaces).isEmpty {
            profile.products.append(SocialProduct(id: nil, name: productName.trimmingCharacters(in: .whitespaces), description: productDescription))
        }
        do {
            store.apply(try await store.api.saveProfile(profile))
            generate()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func generate() {
        Task {
            isBuilding = true
            defer { isBuilding = false }
            do {
                _ = try await store.api.generateStrategy()
            } catch let error as SocialAPIError where error.code == "profile_incomplete" {
                // The overview reload below shows what's missing.
            } catch {
                store.errorMessage = error.localizedDescription
            }
            await store.load()
        }
    }
}

// MARK: - Strategy (1g)

struct SocialStrategyBody: View {
    @ObservedObject var store: SocialStore
    let strategy: SocialStrategy

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                SocialKicker(text: "Social strategy · Built \(SocialDates.format(String(strategy.builtAt.prefix(10)), "MMM d")) from your profile")
                Text(strategy.goal).font(.system(size: 30, weight: .bold)).kerning(-0.8).foregroundStyle(SocialTheme.text)
                HStack(alignment: .top, spacing: 10) {
                    MayaAvatar()
                    Text("That goal comes from your profile. I re-check this strategy whenever your profile changes, and I won’t schedule anything that doesn’t fit it.")
                        .font(.system(size: 15)).foregroundStyle(SocialTheme.muted)
                }
            }

            Text("Content pillars").font(.system(size: 20, weight: .bold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(strategy.pillars, id: \.key) { pillar in
                    let colors = SocialTheme.tint(pillar.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(pillar.share)%").font(.system(size: 26, weight: .bold))
                        Text(pillar.name).font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                    .padding(16)
                    .background(colors.bg, in: RoundedRectangle(cornerRadius: 24))
                    .foregroundStyle(colors.fg)
                }
            }

            SocialKicker(text: "Channels")
            VStack(spacing: 8) {
                ForEach(strategy.channels, id: \.key) { channel in
                    SocialChannelRow(store: store, channel: channel)
                }
            }

            Text("Rules Maya follows").font(.system(size: 20, weight: .bold))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26).background(SocialTheme.surface, in: Circle())
                        Text(rule).font(.system(size: 15)).foregroundStyle(SocialTheme.text)
                    }
                }
            }
        }
    }

    private var rules: [String] {
        [
            "At least one post goes out every day.",
            "Every post fits a pillar. Your posts too: I block anything that doesn’t, and suggest a version that does.",
            "Posts auto-approve \(store.hours) hours after I draft them, unless you hold them.",
            "A held post keeps its slot. Unpinned posts behind it move back a day.",
            "Pinned posts never move. If one isn’t approved by its date, it expires.",
            "No prices, discounts or claims that aren’t in your profile.",
        ]
    }
}

struct SocialStrategyView: View {
    @ObservedObject var store: SocialStore
    @Binding var path: [SocialRoute]
    @State private var isBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let pending = store.overview?.pendingStrategy, store.strategy != nil {
                    SocialNotice(tint: "yellow", text: "Your profile changed, so I’m suggesting this strategy. Nothing changes until you approve it.") {
                        HStack {
                            Button("Keep current") { run { try await store.api.discardPendingStrategy() } }.buttonStyle(SocialPillButtonStyle(kind: .onCard, height: 40))
                            Button("Approve") { run { try await store.api.approveStrategy() } }.buttonStyle(SocialPillButtonStyle(kind: .primary, height: 40))
                        }
                    }
                    SocialStrategyBody(store: store, strategy: pending)
                } else if let strategy = store.strategy {
                    SocialStrategyBody(store: store, strategy: strategy)
                }
                HStack(spacing: 10) {
                    Button("Social profile") { path = [.profile] }.buttonStyle(SocialPillButtonStyle())
                    Button {
                        Task {
                            isBusy = true
                            defer { isBusy = false }
                            do { _ = try await store.api.generateStrategy(); await store.load() } catch { store.errorMessage = error.localizedDescription }
                        }
                    } label: { HStack { if isBusy { ProgressView().tint(SocialTheme.bg) }; Text("Regenerate") } }
                    .buttonStyle(SocialPillButtonStyle(kind: .ink))
                    .disabled(isBusy)
                }
            }
            .padding(20)
        }
        .refreshable { await store.load() }
    }

    private func run(_ call: @escaping () async throws -> SocialOverview) {
        Task {
            do { store.apply(try await call()) } catch { store.errorMessage = error.localizedDescription }
        }
    }
}


/// One strategy channel with where it stands (gaps 2b, 3c). Connecting
/// opens Maya Social on the web, where the provider's sign-in runs.
struct SocialChannelRow: View {
    @ObservedObject var store: SocialStore
    let channel: SocialChannel
    @Environment(\.openURL) private var openURL

    var body: some View {
        let state = store.channelState(channel.key)?.status ?? (store.isConnected(channel.key) ? "connected" : "not_connected")
        let signedOut = state == "needs_reconnect"
        HStack(spacing: 10) {
            Text(channel.name).font(.system(size: 16, weight: .bold))
            Spacer()
            Text("\(channel.perWeek)/wk").font(.system(size: 14)).foregroundStyle(signedOut ? SocialTheme.tint("yellow").fg : SocialTheme.muted)
            if state == "connected" {
                SocialChip(text: "Connected", colors: SocialTheme.tint("green"))
            } else {
                Button(signedOut ? "Reconnect" : "Connect") {
                    openURL(URL(string: "https://social.taliferro.tech/strategy#channels-title")!)
                }
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(SocialTheme.blue, in: Capsule())
                .foregroundStyle(.white)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .background(signedOut ? SocialTheme.tint("yellow").bg : SocialTheme.surface, in: Capsule())
    }
}
