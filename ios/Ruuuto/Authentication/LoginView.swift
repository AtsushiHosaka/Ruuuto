import SwiftUI

struct LoginView: View {
    enum Mode: String, CaseIterable {
        case signIn = "ログイン"
        case signUp = "アカウントを作成"
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
        case failed(String)
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
                Text("Ruuuto")
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
            Picker("手続き", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(submitting)

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("メールアドレス")
                TextField(
                    "メールアドレス",
                    text: $email,
                    prompt: Text("name@example.com").foregroundStyle(RuuutoPalette.muted)
                )
                .accessibilityLabel("メールアドレス")
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
                fieldLabel("パスワード")
                SecureField(
                    "パスワード",
                    text: $password,
                    prompt: Text("パスワードを入力").foregroundStyle(RuuutoPalette.muted)
                )
                .accessibilityLabel("パスワード")
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
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            case .confirmationRequired:
                Label("確認メールを開き、アカウントを確認してからログインしてください。", systemImage: "envelope")
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
                            .accessibilityLabel("送信中")
                    } else {
                        Text(mode.rawValue)
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

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
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
            submission = .failed(mode == .signIn
                ? "ログインできませんでした。メールアドレス、パスワード、メールの確認状況を確かめてください。"
                : "アカウントを作成できませんでした。メールアドレスとパスワードを確認してください。")
        }
    }
}
