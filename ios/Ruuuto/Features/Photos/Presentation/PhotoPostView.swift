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
    @State private var cameraAccess: CameraAccess = .notDetermined
    @State private var showsCamera = false
    @State private var showsCityPicker = false
    @Environment(\.locale) private var locale
    private let cities = CityCatalog.bundled
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview
                    if model.preparedPhoto != nil { cityRow }
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

    /// 投稿に付ける都市（RCNO-29）。都市なしでも投稿できる。
    private var cityRow: some View {
        Button {
            showsCityPicker = true
        } label: {
            HStack {
                Label {
                    Text("photos.city.row", tableName: "Map")
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                Spacer()
                if let id = model.cityID {
                    Text(verbatim: cities.city(id: id)?.name(for: locale) ?? id)
                } else {
                    Text("photos.city.row.none", tableName: "Map")
                }
                if model.canChangeCity {
                    Image(systemName: "chevron.right").foregroundStyle(RuuutoPalette.sub)
                }
            }
            .font(RuuutoType.body(.body, dynamicTypeSize: dynamicTypeSize))
            .foregroundStyle(RuuutoPalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!model.canChangeCity)
        .accessibilityHint(Text("photos.city.row.hint", tableName: "Map"))
        .sheet(isPresented: $showsCityPicker) {
            CityPickerView(catalog: cities, selectedID: model.cityID) { city in
                model.cityID = city?.id
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task { await openCamera() }
                } label: {
                    Label {
                        Text("photos.post.camera", tableName: "Photos")
                    } icon: {
                        Image(systemName: "camera")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(RuuutoPalette.accent)
                .disabled(cameraAccess == .unavailable)

                PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
                    Label {
                        if model.preparedPhoto == nil {
                            Text("photos.post.choose", tableName: "Photos")
                        } else {
                            Text("photos.post.choose_other", tableName: "Photos")
                        }
                    } icon: {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                .buttonStyle(.bordered)
            }
            .disabled(model.isPosting || model.state == .preparing)

            cameraNotice
        }
        .onAppear { cameraAccess = CameraAccess.current() }
        // 設定アプリで許可を変えて戻ってきたときに読み直す
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            cameraAccess = CameraAccess.current()
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(
                onCapture: { image in
                    showsCamera = false
                    guard let data = image.jpegData(compressionQuality: 0.95) else {
                        model.selectionFailed()
                        return
                    }
                    Task { await model.select(data) }
                },
                onCancel: { showsCamera = false }
            )
            .ignoresSafeArea()
        }
    }

    /// カメラを使えないときの案内（RCNO-16）。拒否されていても、ライブラリからは選べる。
    @ViewBuilder private var cameraNotice: some View {
        switch cameraAccess {
        case .denied:
            VStack(spacing: 8) {
                Text("photos.camera.denied", tableName: "Photos")
                    .font(RuuutoType.body(.footnote, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(RuuutoPalette.sub)
                    .multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("photos.camera.open_settings", tableName: "Photos")
                }
                .font(RuuutoType.body(.footnote, dynamicTypeSize: dynamicTypeSize))
            }
        case .unavailable:
            Text("photos.camera.unavailable", tableName: "Photos")
                .font(RuuutoType.body(.footnote, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(RuuutoPalette.sub)
                .multilineTextAlignment(.center)
        case .authorized, .notDetermined:
            EmptyView()
        }
    }

    private func openCamera() async {
        cameraAccess = await CameraAccess.requestIfNeeded()
        showsCamera = cameraAccess == .authorized
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
