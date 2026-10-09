import SwiftUI

// MARK: - Social profile (1j + channels + auto-approve)

struct SocialProfileView: View {
    @ObservedObject var store: SocialStore
    @Environment(\.openURL) private var openURL
    @State private var profile = SocialProfile(companyName: "", companyGoal: "", timezone: nil, products: [], audience: "", location: "", website: "", tones: [])
    @State private var isSaving = false
    @State private var saved = false

    private let tones = ["Plain", "Confident", "Playful"]
    private let channelOrder = ["linkedin", "threads", "facebook", "instagram", "google_business_profile"]

    private var valid: Bool {
        !profile.companyName.trimmingCharacters(in: .whitespaces).isEmpty
            && !profile.companyGoal.trimmingCharacters(in: .whitespaces).isEmpty
            && profile.products.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        Form {
            Section {
                TextField("Company name", text: $profile.companyName)
                TextField("Company goal", text: $profile.companyGoal, axis: .vertical)
            } header: { Text("Required") } footer: { Text("This is your Taliferro profile. Changes here update it everywhere.") }

            Section("Products and services") {
                // By position: keying on the product itself changes identity on
                // every keystroke and drops the field's focus.
                ForEach(profile.products.indices, id: \.self) { index in
                    VStack(alignment: .leading) {
                        TextField("Name", text: $profile.products[index].name).font(.headline)
                        TextField("One line on what it does", text: $profile.products[index].description).font(.subheadline)
                    }
                }
                .onDelete { profile.products.remove(atOffsets: $0) }
                Button("Add product or service") { profile.products.append(SocialProduct(id: nil, name: "", description: "")) }
            }

            Section("About your business") {
                TextField("Audience", text: $profile.audience)
                TextField("Location", text: $profile.location)
                TextField("Website", text: $profile.website).keyboardType(.URL).textInputAutocapitalization(.never)
                HStack {
                    ForEach(tones, id: \.self) { tone in
                        let on = profile.tones.contains(tone)
                        Button(tone) {
                            if on { profile.tones.removeAll { $0 == tone } } else { profile.tones.append(tone) }
                        }
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(on ? SocialTheme.blue : SocialTheme.surface, in: Capsule())
                        .foregroundStyle(on ? .white : SocialTheme.text)
                    }
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack { Spacer(); if isSaving { ProgressView() } else { Text(saved ? "Saved" : "Save profile").bold() }; Spacer() }
                }
                .disabled(!valid || isSaving)
            } footer: {
                Text("When you save, Maya checks whether the strategy still fits. If it doesn’t, she suggests changes on Strategy. Nothing changes until you approve.")
            }

            Section("Auto-approve after") {
                Picker("Auto-approve after", selection: Binding(get: { store.hours }, set: { hours in
                    Task { do { store.apply(try await store.api.setAutoApproveHours(hours)) } catch { store.errorMessage = error.localizedDescription } }
                })) {
                    ForEach([2, 4, 6], id: \.self) { Text("\($0) hours").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach(channelOrder.filter { store.channelNames[$0] != nil }, id: \.self) { key in
                    HStack {
                        Text(store.channelNames[key] ?? key)
                        Spacer()
                        if (store.overview?.connectedChannels ?? []).contains(key) {
                            Label("Connected", systemImage: "checkmark").foregroundStyle(SocialTheme.tint("green").fg).font(.subheadline.bold())
                        } else {
                            Button("Connect") { openURL(URL(string: "https://social.taliferro.tech/profile#channels")!) }
                        }
                    }
                }
            } header: { Text("Channels") } footer: { Text("Maya posts only to channels you connect. Connecting opens Maya Social on the web.") }
        }
        .navigationTitle("Social profile")
        .onAppear { if let current = store.overview?.profile { profile = current } }
        .refreshable { await store.load() }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var cleaned = profile
        cleaned.products = cleaned.products.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        do {
            store.apply(try await store.api.saveProfile(cleaned))
            saved = true
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - New post (1k)

struct NewSocialPostView: View {
    @ObservedObject var store: SocialStore
    let onDone: () -> Void

    @State private var text = ""
    @State private var original: String?
    @State private var channels: Set<String> = []
    @State private var pinned = false
    @State private var pinDate = Date().addingTimeInterval(86_400)
    @State private var check: PostCheck?
    @State private var isChecking = false
    @State private var isAdding = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .onChange(of: text) { _, _ in scheduleCheck() }
            } header: { Text("Your post") } footer: { Text("Maya checks it against your strategy as you type.") }

            Section("Channels") {
                ForEach(store.strategy?.channels ?? [], id: \.key) { channel in
                    Toggle(channel.name, isOn: Binding(get: { channels.contains(channel.key) }, set: { on in
                        if on { channels.insert(channel.key) } else { channels.remove(channel.key) }
                    }))
                }
            }

            Section("When") {
                Picker("When", selection: $pinned) {
                    Text("Next open slot").tag(false)
                    Text("Pick a date and pin it").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: pinned) { _, _ in scheduleCheck() }
                if pinned {
                    DatePicker("Date and time", selection: $pinDate, in: Date().addingTimeInterval(86_400)...)
                        .onChange(of: pinDate) { _, _ in scheduleCheck() }
                }
            }

            Section {
                if isChecking {
                    HStack(spacing: 10) { ProgressView(); Text("Maya is checking it against your strategy…").foregroundStyle(SocialTheme.muted) }
                } else if let check, !check.aligned {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("This doesn’t fit the strategy yet", systemImage: "exclamationmark.circle").font(.headline)
                        ForEach(check.reasons, id: \.self) { Text("• \($0)").font(.subheadline) }
                        if let version = check.version {
                            Text("MY VERSION · \(store.pillar(check.pillar).name.uppercased()) PILLAR").font(.caption.bold()).padding(.top, 6)
                            Text(version.body).font(.subheadline).foregroundStyle(SocialTheme.text)
                            Button("Use Maya’s version") { original = text; text = version.body }
                                .buttonStyle(SocialPillButtonStyle(kind: .primary, height: 46))
                        }
                    }
                    .foregroundStyle(SocialTheme.tint("pink").fg)
                    .listRowBackground(SocialTheme.tint("pink").bg)
                } else if let check, check.aligned {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Fits the strategy", systemImage: "checkmark.circle").font(.headline)
                        if let slot = check.slot {
                            Text("It takes \(pinned ? "the pinned date" : "the next \(store.pillar(check.pillar).name) slot"): \(SocialDates.short(slot.slotDate)) at \(SocialDates.wallClock(slot.time)).")
                        } else if let error = check.placementError {
                            Text(error)
                        }
                        if let first = check.moved.first {
                            Text("“\(first.title ?? "The post there")” moves to \(SocialDates.short(first.to))\(check.moved.count > 1 ? ", and \(check.moved.count - 1) more move back a day" : ""). Pinned posts stay put.")
                        }
                        if let original {
                            Button("Go back to my version") { text = original; self.original = nil }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(SocialTheme.tint("green").fg)
                    .listRowBackground(SocialTheme.tint("green").bg)
                } else {
                    Text("Write at least a sentence and Maya will check it, then show you where it lands.").foregroundStyle(SocialTheme.muted)
                }
            }

            Section {
                Button {
                    Task { await add() }
                } label: {
                    HStack { Spacer(); if isAdding { ProgressView() } else { Label("Add to calendar", systemImage: canAdd ? "calendar.badge.plus" : "lock") }; Spacer() }
                }
                .disabled(!canAdd || isAdding)
            }
        }
        .navigationTitle("New post")
        .onAppear { channels = Set((store.strategy?.channels ?? []).map(\.key)) }
        .onDisappear { checkTask?.cancel() }
    }

    private var canAdd: Bool {
        (check?.aligned ?? false) && check?.slot != nil && !channels.isEmpty && !isChecking
    }

    private var draft: NewSocialPost {
        let timeZone = store.timeZone
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return NewSocialPost(
            body: text.trimmingCharacters(in: .whitespacesAndNewlines),
            channels: Array(channels),
            pinned: pinned,
            slotDate: pinned ? SocialDates.key(pinDate, timeZone: timeZone) : nil,
            time: pinned ? formatter.string(from: pinDate) : nil
        )
    }

    /// Checks 1.2 seconds after typing stops, once there's a sentence.
    private func scheduleCheck() {
        checkTask?.cancel()
        check = nil
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else { isChecking = false; return }
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            isChecking = true
            defer { isChecking = false }
            do {
                let result = try await store.api.check(draft)
                if !Task.isCancelled { check = result }
            } catch {
                if !Task.isCancelled { store.errorMessage = error.localizedDescription }
            }
        }
    }

    private func add() async {
        isAdding = true
        defer { isAdding = false }
        do {
            let created = try await store.api.create(draft)
            store.replace(created.post)
            await store.loadPosts(force: true)
            onDone()
        } catch let error as SocialAPIError {
            if let blocked = error.check { check = blocked } else { store.errorMessage = error.localizedDescription }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
