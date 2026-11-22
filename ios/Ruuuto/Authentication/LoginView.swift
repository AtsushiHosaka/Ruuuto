import SwiftUI

struct LoginView: View {
    enum Mode: CaseIterable {
        case signIn
        case signUp

        var title: Text {
            switch self {
            case .signIn: Text("auth.action.sign_in", tableName: "Authentication")
            case .signUp: Text("auth.action.sign_up", tableName: "Authentication")
            }
        }

        var failureMessage: Text {
            switch self {
            case .signIn: Text("auth.sign_in.failure", tableName: "Authentication")
            case .signUp: Text("auth.sign_up.failure", tableName: "Authentication")
            }
        }
    }

    let signIn: (String, String) async throws -> Void
    let signUp: (String, String) async throws -> Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize = 54

    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var submission: Submission = .idle

    private enum Submission: Equatable {
        case idle
        case submitting
        case confirmationRequired
        case failed(Mode)
    }

    @FocusState private var focus: LoginCredentialFields.Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                brand
                authenticationForm
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            LoginBackground()
                .ignoresSafeArea()
        }
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onChange(of: mode) {
            switch submission {
            case .failed:
                submission = .idle
            case .confirmationRequired where mode == .signUp:
                submission = .idle
            default:
                break
            }
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 0) {
            LoginArtwork()
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(verbatim: "Ruuuto")
                .font(.system(size: wordmarkSize, weight: .heavy, design: .rounded))
                .tracking(-wordmarkSize * 0.04)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var authenticationForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            modeTabs
            LoginCredentialFields(
                email: $email,
                password: $password,
                focus: $focus,
                isCreatingAccount: mode == .signUp,
                isSubmitting: submitting,
                submit: submit
            )
            submitButton
                .padding(.top, 8)
            feedback
        }
    }

    private var modeTabs: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))

        return layout {
            ForEach(Mode.allCases, id: \.self) { option in
                Button {
                    mode = option
                } label: {
                    option.title
                        .font(.subheadline.weight(mode == option ? .heavy : .semibold))
                        .foregroundStyle(mode == option ? .white : RuuutoPalette.line)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 7)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            if mode == option {
                                Rectangle()
                                    .fill(RuuutoPalette.accent)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(RuuutoPalette.line.opacity(0.45))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("auth.mode.label", tableName: "Authentication"))
        .disabled(submitting)
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if submitting {
                    ProgressView()
                        .tint(RuuutoPalette.ink)
                        .accessibilityLabel(Text("auth.submission.in_progress", tableName: "Authentication"))
                } else {
                    mode.title
                        .font(.headline.weight(.heavy))
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 49)
            .foregroundStyle(canSubmit || submitting ? RuuutoPalette.ink : RuuutoPalette.line)
            .background(
                canSubmit || submitting ? RuuutoPalette.accent : RuuutoPalette.soft,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    @ViewBuilder
    private var feedback: some View {
        switch submission {
        case .failed(let failedMode):
            failedMode.failureMessage
                .font(.subheadline)
                .foregroundStyle(RuuutoPalette.line)
        case .confirmationRequired:
            Text("auth.sign_up.confirm_email", tableName: "Authentication")
                .font(.subheadline)
                .foregroundStyle(RuuutoPalette.line)
        case .idle, .submitting:
            EmptyView()
        }
    }

    private var submitting: Bool { submission == .submitting }

    private var canSubmit: Bool {
        !submitting && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func submit() async {
        guard canSubmit else { return }
        focus = nil
        submission = .submitting
        defer {
            if submission == .submitting { submission = .idle }
        }

        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch mode {
            case .signIn:
                try await signIn(address, password)
            case .signUp:
                if try await !signUp(address, password) {
                    mode = .signIn
                    submission = .confirmationRequired
                }
            }
            password = ""
        } catch is CancellationError {
            return
        } catch {
            submission = .failed(mode)
        }
    }
}
