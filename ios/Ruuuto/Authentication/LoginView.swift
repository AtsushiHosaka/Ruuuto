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

    var body: some View {
        Form {
            Section {
                Picker("手続き", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                TextField("メールアドレス", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("パスワード", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
            }
            .disabled(submitting)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if confirmationRequired {
                Text("確認メールを開き、アカウントを確認してからログインしてください。")
            }

            Button {
                Task { await submit() }
            } label: {
                if submitting {
                    ProgressView()
                        .accessibilityLabel("送信中")
                } else {
                    Text(mode.rawValue)
                }
            }
            .disabled(submitting || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
        }
        .navigationTitle("ルート")
        .onChange(of: mode) {
            errorMessage = nil
        }
    }

    private func submit() async {
        guard !submitting else { return }
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
