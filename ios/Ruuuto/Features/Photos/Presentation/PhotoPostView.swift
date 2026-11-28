import PhotosUI
import SwiftUI
import UIKit

extension PhotoPostViewModel: Identifiable {}

/// ライブラリから写真を選び、プレビューしてからボードに投稿する画面（RCNO-13）。
///
/// PhotosPicker はアプリの外で動くため、写真ライブラリへのアクセス許可を求めない。
/// 選んだ1枚だけがアプリに渡る。
struct PhotoPostView: View {
    @State var model: PhotoPostViewModel
    @State private var pickerItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview
                    status
                    picker
                }
                .padding(20)
            }
            .background(RuuutoPalette.page)
            .navigationTitle(Text("photos.post.title", tableName: "Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        model.cancelSelection()
                        dismiss()
                    } label: {
                        Text("photos.post.cancel", tableName: "Photos")
                    }
                    .disabled(model.isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    submitButton
                }
            }
            .interactiveDismissDisabled(model.isPosting)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .onChange(of: model.state) { _, state in
            if case .posted = state { dismiss() }
        }
    }

    @ViewBuilder private var preview: some View {
        if let photo = model.preparedPhoto, let image = UIImage(data: photo.data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(Text("photos.post.preview_label", tableName: "Photos"))
        } else if model.state == .preparing {
            ProgressView {
                Text("photos.post.preparing", tableName: "Photos")
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(RuuutoPalette.line.opacity(0.4))
                .frame(height: 240)
                .overlay {
                    Text("photos.post.empty", tableName: "Photos")
                        .font(RuuutoType.body(.callout, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(RuuutoPalette.sub)
                        .multilineTextAlignment(.center)
                        .padding()
                }
        }
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .posting(_, let step):
            ProgressView(value: Double(step.rawValue), total: Double(PhotoPostViewModel.Step.count)) {
                Text("photos.post.step \(step.rawValue) \(PhotoPostViewModel.Step.count)", tableName: "Photos")
            }
        case .failed(_, let failure):
            VStack(spacing: 12) {
                Text(message(for: failure))
                    .font(RuuutoType.body(.callout, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                if model.canSubmit {
                    Button {
                        Task { await model.submit() }
                    } label: {
                        Text("photos.post.retry", tableName: "Photos")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RuuutoPalette.accent)
                }
            }
        case .previewing:
            Text("photos.post.hint", tableName: "Photos")
                .font(RuuutoType.body(.footnote, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(RuuutoPalette.sub)
                .multilineTextAlignment(.center)
        case .choosing, .preparing, .posted:
            EmptyView()
        }
    }

    private var picker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
            if model.preparedPhoto == nil {
                Text("photos.post.choose", tableName: "Photos")
            } else {
                Text("photos.post.choose_other", tableName: "Photos")
            }
        }
        .buttonStyle(.bordered)
        .disabled(model.isPosting || model.state == .preparing)
    }

    private var submitButton: some View {
        Button {
            Task { await model.submit() }
        } label: {
            if model.isPosting {
                ProgressView()
            } else {
                Text("photos.post.submit", tableName: "Photos")
            }
        }
        .disabled(!model.canSubmit)
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                model.selectionFailed()
                return
            }
            await model.select(data)
        } catch {
            model.selectionFailed()
        }
    }

    private func message(for failure: PhotoPostViewModel.Failure) -> String {
        switch failure {
        case .preparation(.unreadable): String(localized: "photos.post.error.unreadable", table: "Photos")
        case .preparation(.tooLarge): String(localized: "photos.post.error.too_large", table: "Photos")
        case .post(.boardClosed): String(localized: "photos.post.error.closed", table: "Photos")
        case .post(.withdrawn): String(localized: "photos.post.error.withdrawn", table: "Photos")
        case .post(.forbidden): String(localized: "photos.post.error.forbidden", table: "Photos")
        case .post(.rejected): String(localized: "photos.post.error.rejected", table: "Photos")
        case .post(.retryable): String(localized: "photos.post.error.retryable", table: "Photos")
        }
    }
}
