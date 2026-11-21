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
    @State private var errorMessage: String?
    @State private var confirmationRequired = false
    @State private var submitting = false

    @FocusState private var focus: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                artwork
                Text("ルート")
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
            errorMessage = nil
        }
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(RuuutoPalette.soft.opacity(0.4))
            .overlay {
                Canvas { context, size in
                    var dots = Path()
                    for x in stride(from: 9.0, to: size.width, by: 18.0) {
                        for y in stride(from: 9.0, to: size.height, by: 18.0) {
                            dots.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                        }
                    }
                    context.fill(dots, with: .color(RuuutoPalette.muted.opacity(0.3)))
                }
            }
            .overlay {
                ZStack {
                    photoTile(tint: RuuutoPalette.line, rotation: -11)
                        .offset(x: -38, y: 3)
                    photoTile(tint: RuuutoPalette.accent, rotation: 10)
                        .offset(x: 37, y: 7)

                    Image(systemName: "star.fill")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(RuuutoPalette.accent)
                        .shadow(color: RuuutoPalette.ink.opacity(0.35), radius: 3, y: 2)
                        .rotationEffect(.degrees(14))
                        .offset(x: 88, y: -40)
                }
            }
            .frame(height: 144)
            .accessibilityHidden(true)
    }

    private func photoTile(tint: Color, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(tint)
            .frame(width: 70, height: 61)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: RuuutoPalette.ink.opacity(0.45), radius: 7, y: 5)
            .rotationEffect(.degrees(rotation))
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

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            }

            if confirmationRequired {
                Label("確認メールを開き、アカウントを確認してからログインしてください。", systemImage: "envelope")
                    .font(.subheadline)
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

    private var canSubmit: Bool {
        !submitting && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func submit() async {
        guard canSubmit else { return }
        focus = nil
        submitting = true
        errorMessage = nil
        confirmationRequired = false
        defer { submitting = false }

        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch mode {
            case .signIn:
                try await signIn(address, password)
            case .signUp:
                if try await !signUp(address, password) {
                    mode = .signIn
                    confirmationRequired = true
                }
            }
            password = ""
        } catch is CancellationError {
            return
        } catch {
            errorMessage = mode == .signIn
                ? "ログインできませんでした。メールアドレス、パスワード、メールの確認状況を確かめてください。"
                : "アカウントを作成できませんでした。メールアドレスとパスワードを確認してください。"
        }
    }
}
