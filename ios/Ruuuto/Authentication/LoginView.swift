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

    @FocusState private var focus: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LoginArtwork()
                Text(verbatim: "Ruuuto")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .accessibilityAddTraits(.isHeader)
                authenticationCard
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RuuutoPalette.ink.ignoresSafeArea())
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

    private var authenticationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { option in
                    option.title.tag(option)
                }
            } label: {
                Text("auth.mode.label", tableName: "Authentication")
            }
            .pickerStyle(.segmented)
            .disabled(submitting)

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(emailLabel)
                TextField(
                    text: $email,
                    prompt: Text(verbatim: "name@example.com").foregroundStyle(RuuutoPalette.muted)
                ) {
                    emailLabel
                }
                .accessibilityLabel(emailLabel)
                .disabled(submitting)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .email)
                .onSubmit { focus = .password }
                .padding(12)
                .frame(minHeight: 48)
                .background(RuuutoPalette.ink, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(passwordLabel)
                SecureField(
                    text: $password,
                    prompt: Text("auth.password.prompt", tableName: "Authentication")
                        .foregroundStyle(RuuutoPalette.muted)
                ) {
                    passwordLabel
                }
                .accessibilityLabel(passwordLabel)
                .disabled(submitting)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit { Task { await submit() } }
                .padding(12)
                .frame(minHeight: 48)
                .background(RuuutoPalette.ink, in: RoundedRectangle(cornerRadius: 12))
            }

            switch submission {
            case .failed(let failedMode):
                Label {
                    failedMode.failureMessage
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .font(.subheadline)
            case .confirmationRequired:
                Label {
                    Text("auth.sign_up.confirm_email", tableName: "Authentication")
                } icon: {
                    Image(systemName: "envelope")
                }
                .font(.subheadline)
            case .idle, .submitting:
                EmptyView()
            }

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
                            .font(.system(.headline, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(RuuutoPalette.ink)
                .background(
                    canSubmit || submitting ? RuuutoPalette.accent : RuuutoPalette.muted,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .opacity(canSubmit || submitting ? 1 : 0.75)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(18)
        .background(RuuutoPalette.soft, in: RoundedRectangle(cornerRadius: 24))
    }

    private var emailLabel: Text {
        Text("auth.email.label", tableName: "Authentication")
    }

    private var passwordLabel: Text {
        Text("auth.password.label", tableName: "Authentication")
    }

    private func fieldLabel(_ title: Text) -> some View {
        title
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(RuuutoPalette.muted)
            .accessibilityHidden(true)
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
