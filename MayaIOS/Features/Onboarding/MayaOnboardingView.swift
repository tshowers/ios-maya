import SwiftUI
import TODDAuthKit
import TODDProfileKit

/// Maya's sign-in page (pushed from ChatView's banner - never a sheet). The
/// TODD profile is shared across apps, so it leads with "Already use
/// Network or another TODD app? Sign in". New users answer one question per
/// screen (name, role, company, what Maya should help with) under the
/// 4-segment bar with "Download" already done, then sign in last - see
/// ONBOARDING-PROFILE-BILLING-PLAYBOOK.md.
///
/// After sign-in it reads the profile: if the core fields are there it
/// says "You're all set, <name>"; otherwise it asks only what's missing.
/// Answers only ever fill blank fields (`POST /api/onboarding/profile`).
struct MayaOnboardingView: View {
    @ObservedObject var authService: AuthService
    let onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var answers = AuthService.profileStore.load()
    @State private var helpWith: Set<String> = [MayaOnboardingView.helpOptions[0]]
    @State private var isRoleListOpen = false
    @State private var isOtherRole = false
    @State private var errorMessage = ""
    @State private var isWorking = false
    /// After sign-in: only the questions the shared profile still lacks.
    @State private var missingSteps: [Step] = []
    @State private var greetingName = ""
    @FocusState private var isFieldFocused: Bool

    static let helpOptions = [
        "Sharpen my message",
        "Find my best audience",
        "Clarify my offer",
        "Plan my marketing",
        "Write posts and emails",
        "Grow my sales",
    ]

    enum Step: Hashable {
        case welcome, firstName, lastName, role, company, helpWith, signIn
        case checking, allSet

        /// 0 Download (done before the app opened), 1 About you,
        /// 2 Your business, 3 Sign in.
        var section: Int {
            switch self {
            case .welcome, .firstName, .lastName, .role: return 1
            case .company, .helpWith: return 2
            case .signIn, .checking, .allSet: return 3
            }
        }
    }

    private static let newUserOrder: [Step] = [.welcome, .firstName, .lastName, .role, .company, .helpWith, .signIn]

    private var isFinishingProfile: Bool { authService.currentUser != nil }

    var body: some View {
        VStack(spacing: 0) {
            if !isFinishingProfile && step != .allSet {
                OnboardingProgressBar(step: step, order: Self.newUserOrder)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .frame(maxWidth: 560)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding()
            }
            footer
                .frame(maxWidth: 560)
                .padding()
        }
        .background(MayaTheme.background.ignoresSafeArea())
        .navigationTitle(step == .allSet ? "" : "Connect to TODD")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(previousStep != nil)
        .toolbar {
            if let back = previousStep {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        step = back
                    } label: {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .onAppear {
            if let profession = answers.profession.nilIfBlank {
                isOtherRole = !ProfileChoices.roles.contains(profession)
            } else {
                answers.profession = ProfileChoices.defaultRole
            }
            // Signed in already (e.g. unlocked after a restored session):
            // go straight to the profile check.
            if isFinishingProfile { Task { await checkProfile() } }
        }
        .onChange(of: answers) { _, value in AuthService.profileStore.save(value) }
        .onChange(of: helpWith) { _, _ in answers.jobDescriptionForTODD = Self.jobDescription(helpWith) }
        .onChange(of: step) { _, newStep in
            isFieldFocused = [.firstName, .lastName, .company].contains(newStep) || (newStep == .role && isOtherRole)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text("You're already 1 step in")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MayaTheme.accent)
                Text("Let Maya get to know your business")
                    .font(.largeTitle.bold())
                    .foregroundStyle(MayaTheme.text)
                Text("Signed in, Maya gives advice for your business - not generic tips - and remembers your conversations.")
                    .font(.subheadline)
                    .foregroundStyle(MayaTheme.muted)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Already use Network or another TODD app?")
                        .font(.headline)
                        .foregroundStyle(MayaTheme.text)
                    Text("Sign in and Maya already knows you.")
                        .font(.subheadline)
                        .foregroundStyle(MayaTheme.muted)
                    primaryButton("Sign in") { step = .signIn }
                        .accessibilityIdentifier("maya-onboarding-existing")
                }
                .padding(16)
                .background(MayaTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MayaTheme.border))
                .padding(.top, 8)
            }

        case .firstName:
            question("What's your first name?", hint: "So Maya knows who she's advising.") {
                boxedField("First name", text: $answers.firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
            }

        case .lastName:
            question("And your last name?", hint: nil) {
                boxedField("Last name", text: $answers.lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
            }

        case .role:
            question("What's your role?", hint: "Pick the closest fit.") {
                roleList
            }

        case .company:
            question("What's your company called?", hint: "Maya uses it in the plans and posts she drafts.") {
                boxedField("Company name", text: $answers.companyName)
                    .textContentType(.organizationName)
            }

        case .helpWith:
            question("What should Maya help you with?", hint: "Pick as many as you like.") {
                ChipWrap(spacing: 8) {
                    ForEach(Self.helpOptions, id: \.self) { option in
                        chip(option, isSelected: helpWith.contains(option)) {
                            if helpWith.contains(option) { helpWith.remove(option) } else { helpWith.insert(option) }
                        }
                    }
                }
            }

        case .signIn:
            VStack(alignment: .leading, spacing: 14) {
                Text(answers.isReadyToSubmit ? "Last step: sign in" : "Sign in to TODD")
                    .font(.title2.bold())
                    .foregroundStyle(MayaTheme.text)
                Text(answers.isReadyToSubmit
                     ? "Your answers are saved to your TODD profile, so Network, Docs and the rest know you too."
                     : "Use the same Apple or Google account you use for Network, Docs or Pulse.")
                    .font(.subheadline)
                    .foregroundStyle(MayaTheme.muted)
                VStack(spacing: 12) {
                    SignInWithAppleButtonView(
                        onSignedIn: { Task { await finishSignIn() } },
                        onError: { errorMessage = $0.localizedDescription }
                    )
                    SignInWithGoogleButtonView(
                        onSignedIn: { Task { await finishSignIn() } },
                        onError: { errorMessage = $0.localizedDescription }
                    )
                }
                .disabled(isWorking)
                .padding(.top, 8)
                if isWorking { ProgressView().frame(maxWidth: .infinity) }
                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }

        case .checking:
            VStack(spacing: 12) {
                ProgressView()
                Text("Checking your profile…")
                    .font(.subheadline)
                    .foregroundStyle(MayaTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)

        case .allSet:
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(MayaTheme.accent)
                Text(greetingName.isEmpty ? "You're all set" : "You're all set, \(greetingName)")
                    .font(.largeTitle.bold())
                    .foregroundStyle(MayaTheme.text)
                Text("Maya has your profile, so her advice fits your business. Update it anytime from the menu.")
                    .font(.subheadline)
                    .foregroundStyle(MayaTheme.muted)
            }
            .padding(.top, 24)
        }
    }

    /// More than five roles, so it's a row with a chevron that opens the
    /// list inline (tap, don't type; no popups). "Other" reveals a field.
    private var roleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { isRoleListOpen.toggle() }
            } label: {
                HStack {
                    Text(isOtherRole ? "Other" : answers.profession)
                        .font(.body.weight(.semibold))
                    Spacer()
                    Image(systemName: isRoleListOpen ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(MayaTheme.text)
                .padding(14)
                .background(MayaTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MayaTheme.border))
            }
            .buttonStyle(.plain)

            if isRoleListOpen {
                VStack(spacing: 0) {
                    ForEach(ProfileChoices.roles + ["Other"], id: \.self) { role in
                        let isSelected = role == "Other" ? isOtherRole : (!isOtherRole && answers.profession == role)
                        Button {
                            if role == "Other" {
                                if !isOtherRole { answers.profession = "" }
                                isOtherRole = true
                                isFieldFocused = true
                            } else {
                                isOtherRole = false
                                answers.profession = role
                            }
                            withAnimation { isRoleListOpen = false }
                        } label: {
                            HStack {
                                Text(role).foregroundStyle(MayaTheme.text)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark").foregroundStyle(MayaTheme.accent)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(MayaTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MayaTheme.border))
            }

            if isOtherRole {
                boxedField("Your role", text: $answers.profession)
                    .textInputAutocapitalization(.words)
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .welcome:
            VStack(spacing: 8) {
                secondaryButton("I'm new to TODD") { step = .firstName }
                    .accessibilityIdentifier("maya-onboarding-new")
                Text("Maya keeps working without an account - this just makes her advice yours.")
                    .font(.caption)
                    .foregroundStyle(MayaTheme.muted)
                    .multilineTextAlignment(.center)
            }
        case .signIn, .checking:
            EmptyView()
        case .allSet:
            primaryButton("Start talking to Maya") { onFinished() }
        default:
            HStack(spacing: 10) {
                if step == .company {
                    secondaryButton("Skip") { advance() }
                }
                primaryButton(isFinishingProfile && isLastMissingStep ? "Save" : "Next") { advance() }
                    .disabled(!canAdvance || isWorking)
            }
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .firstName: return answers.firstName.nilIfBlank != nil
        case .lastName: return answers.lastName.nilIfBlank != nil
        case .role: return answers.profession.nilIfBlank != nil
        case .helpWith: return !helpWith.isEmpty
        default: return true
        }
    }

    private var isLastMissingStep: Bool { missingSteps.last == step }

    private var previousStep: Step? {
        let order = isFinishingProfile ? missingSteps : Self.newUserOrder
        guard let index = order.firstIndex(of: step), index > 0 else { return nil }
        // "Already use TODD?" jumps welcome -> signIn; Back returns there.
        if step == .signIn && !answers.isReadyToSubmit { return .welcome }
        return order[index - 1]
    }

    private func advance() {
        if isFinishingProfile {
            guard let index = missingSteps.firstIndex(of: step) else { return }
            if index + 1 < missingSteps.count {
                step = missingSteps[index + 1]
            } else {
                Task { await saveMissingAnswers() }
            }
            return
        }
        guard let index = Self.newUserOrder.firstIndex(of: step), index + 1 < Self.newUserOrder.count else { return }
        step = Self.newUserOrder[index + 1]
        if step == .signIn {
            answers.jobDescriptionForTODD = Self.jobDescription(helpWith)
            answers.isReadyToSubmit = true
        }
    }

    // MARK: - After sign-in

    private func finishSignIn() async {
        errorMessage = ""
        isWorking = true
        defer { isWorking = false }
        do {
            // Creates the TODD workspace if needed and saves any answers
            // (blank fields only) before the profile check below.
            try await authService.bootstrapTenant()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await checkProfile()
    }

    private func checkProfile() async {
        step = .checking
        guard let profile = try? await authService.profileAPI.load() else {
            // Couldn't read it - don't block Maya on a profile check.
            step = .allSet
            return
        }
        greetingName = profile.firstName
        var missing: [Step] = []
        if profile.firstName.nilIfBlank == nil { missing.append(.firstName) }
        if profile.lastName.nilIfBlank == nil { missing.append(.lastName) }
        if profile.profession.nilIfBlank == nil { missing.append(.role) }
        if profile.companyName.nilIfBlank == nil { missing.append(.company) }
        if profile.jobDescriptionForTODD.nilIfBlank == nil { missing.append(.helpWith) }
        missingSteps = missing
        step = missing.first ?? .allSet
    }

    private func saveMissingAnswers() async {
        isWorking = true
        defer { isWorking = false }
        answers.jobDescriptionForTODD = Self.jobDescription(helpWith)
        answers.isReadyToSubmit = true
        AuthService.profileStore.save(answers)
        await authService.submitOnboardingProfileIfNeeded()
        if greetingName.isEmpty { greetingName = answers.firstName }
        step = .allSet
    }

    /// "Help me sharpen my message and clarify my offer." - stored in
    /// jobDescriptionForTODD, the same field Network's wizard fills.
    static func jobDescription(_ selected: Set<String>) -> String {
        let goals = helpOptions.filter(selected.contains).map { $0.prefix(1).lowercased() + $0.dropFirst() }
        switch goals.count {
        case 0: return ""
        case 1: return "Help me \(goals[0])."
        default: return "Help me \(goals.dropLast().joined(separator: ", ")) and \(goals.last!)."
        }
    }

    // MARK: - Pieces

    private func question(_ title: String, hint: String?, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isFinishingProfile {
                Text("Just a couple of things Maya doesn't know yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MayaTheme.accent)
            }
            Text(title).font(.title2.bold()).foregroundStyle(MayaTheme.text)
            if let hint {
                Text(hint).font(.subheadline).foregroundStyle(MayaTheme.muted)
            }
            field()
        }
    }

    private func boxedField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.title3)
            .foregroundStyle(MayaTheme.text)
            .autocorrectionDisabled()
            .padding(14)
            .background(MayaTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MayaTheme.border))
            .focused($isFieldFocused)
            .submitLabel(.next)
            .onSubmit { if canAdvance { advance() } }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(isSelected ? MayaTheme.accent : MayaTheme.surface))
            .overlay(Capsule().strokeBorder(isSelected ? MayaTheme.accent : MayaTheme.border, lineWidth: 1))
            .foregroundStyle(isSelected ? Color.white : MayaTheme.text)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(MayaTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(MayaTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MayaTheme.accent, lineWidth: 1.5))
                .foregroundStyle(MayaTheme.accent)
        }
    }
}

/// Download is already checked - installing the app was step one
/// (endowed progress), same as the other TODD apps' wizards.
private struct OnboardingProgressBar: View {
    let step: MayaOnboardingView.Step
    let order: [MayaOnboardingView.Step]

    private static let titles = ["Download", "About you", "Your business", "Sign in"]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(MayaTheme.accent.opacity(0.18))
                            Capsule().fill(MayaTheme.accent).frame(width: geometry.size.width * fill(index))
                        }
                    }
                    .frame(height: 6)
                    HStack(spacing: 4) {
                        if fill(index) >= 1 {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(MayaTheme.accent)
                        }
                        Text(Self.titles[index]).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(.caption2.weight(index == step.section ? .bold : .medium))
                    .foregroundStyle(index <= step.section ? MayaTheme.text : MayaTheme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.section + 1) of 4, \(Self.titles[step.section])")
    }

    private func fill(_ index: Int) -> Double {
        if index < step.section { return 1 }
        if index > step.section { return 0 }
        let siblings = order.filter { $0.section == index }
        let position = siblings.firstIndex(of: step) ?? 0
        return Double(position + 1) / Double(siblings.count + 1)
    }
}

/// Wraps chips onto as many lines as they need.
private struct ChipWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
