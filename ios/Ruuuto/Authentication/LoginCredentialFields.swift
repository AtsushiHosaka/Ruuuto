import SwiftUI

struct LoginCredentialFields: View {
    enum Field {
        case email
        case password
    }

    @Binding var email: String
    @Binding var password: String
    let focus: FocusState<Field?>.Binding
    let isCreatingAccount: Bool
    let isSubmitting: Bool
    let submit: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            labeledField(emailLabel, field: .email) {
                TextField(
                    text: $email,
                    prompt: Text(verbatim: "name@example.com").foregroundStyle(RuuutoPalette.muted)
                ) {
                    emailLabel
                }
                .accessibilityLabel(emailLabel)
                .disabled(isSubmitting)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused(focus, equals: .email)
                .onSubmit { focus.wrappedValue = .password }
            }

            labeledField(passwordLabel, field: .password) {
                SecureField(
                    text: $password,
                    prompt: Text("auth.password.prompt", tableName: "Authentication")
                        .foregroundStyle(RuuutoPalette.muted)
                ) {
                    passwordLabel
                }
                .accessibilityLabel(passwordLabel)
                .disabled(isSubmitting)
                .textContentType(isCreatingAccount ? .newPassword : .password)
                .submitLabel(.go)
                .focused(focus, equals: .password)
                .onSubmit { Task { await submit() } }
            }
        }
    }

    private func labeledField<Content: View>(
        _ title: Text,
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(.footnote.weight(.semibold))
                .foregroundStyle(RuuutoPalette.line)
                .accessibilityHidden(true)

            content()
                .font(.body)
                .tint(RuuutoPalette.accent)
                .textFieldStyle(.plain)
                .frame(minHeight: 48)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(focus.wrappedValue == field ? RuuutoPalette.accent : RuuutoPalette.line.opacity(0.5))
                        .frame(height: focus.wrappedValue == field ? 2 : 1)
                        .allowsHitTesting(false)
                }
        }
    }

    private var emailLabel: Text {
        Text("auth.email.label", tableName: "Authentication")
    }

    private var passwordLabel: Text {
        Text("auth.password.label", tableName: "Authentication")
    }
}
