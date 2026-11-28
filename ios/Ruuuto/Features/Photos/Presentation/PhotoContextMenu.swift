import SwiftUI

/// 写真の長押しメニュー。iOS 標準のコンテキストメニューで、周りをぼかして写真だけを浮かせる。
///
/// - プレビューには元の色の写真を渡す。退色したボード（RCNO-28）でも、長押しで元の写真を確かめられる。
/// - 「大きく見る」はすべての写真に出す。メニューが空だとプレビューも出ないため、また VoiceOver からも
///   元の写真を開けるようにするため。
/// - 「取り下げる」は自分の写真だけに出す（RCNO-14）。
struct PhotoContextMenu<Preview: View>: ViewModifier {
    let target: PhotoWithdrawalViewModel.Target
    let postedBy: UUID
    let withdrawal: PhotoWithdrawalViewModel?
    let onViewLarger: () -> Void
    @ViewBuilder let preview: () -> Preview

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: onViewLarger) {
                Label {
                    Text("photos.menu.view", tableName: "Photos")
                } icon: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
            }
            if let withdrawal, withdrawal.canWithdraw(postedBy: postedBy) {
                Button(role: .destructive) {
                    withdrawal.request(target)
                } label: {
                    Label {
                        Text("photos.withdraw.action", tableName: "Photos")
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            }
        } preview: {
            preview()
        }
    }
}

extension View {
    func photoContextMenu<Preview: View>(
        target: PhotoWithdrawalViewModel.Target,
        postedBy: UUID,
        withdrawal: PhotoWithdrawalViewModel?,
        onViewLarger: @escaping () -> Void,
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        modifier(PhotoContextMenu(
            target: target, postedBy: postedBy, withdrawal: withdrawal,
            onViewLarger: onViewLarger, preview: preview
        ))
    }

    /// 取り下げの確認と失敗の案内。写真を並べる画面に1つだけ付ける。
    func photoWithdrawalDialogs(_ model: PhotoWithdrawalViewModel) -> some View {
        modifier(PhotoWithdrawalDialogs(model: model))
    }
}

private struct PhotoWithdrawalDialogs: ViewModifier {
    let model: PhotoWithdrawalViewModel

    private var confirming: PhotoWithdrawalViewModel.Target? {
        if case .confirming(let target) = model.state { return target }
        return nil
    }

    private var failure: (PhotoWithdrawalViewModel.Target, PhotoPostError)? {
        if case .failed(let target, let error) = model.state { return (target, error) }
        return nil
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                Text("photos.withdraw.confirm.title", tableName: "Photos"),
                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { model.dismiss() } }),
                titleVisibility: .visible,
                presenting: confirming
            ) { target in
                Button(role: .destructive) {
                    Task { await model.confirm(target) }
                } label: {
                    Text("photos.withdraw.action", tableName: "Photos")
                }
                Button(role: .cancel) {} label: {
                    Text("photos.post.cancel", tableName: "Photos")
                }
            } message: { _ in
                Text("photos.withdraw.confirm.message", tableName: "Photos")
            }
            .alert(
                Text("photos.withdraw.failed.title", tableName: "Photos"),
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { model.dismiss() } }),
                presenting: failure
            ) { target, error in
                if error.canRetry {
                    Button {
                        Task { await model.confirm(target) }
                    } label: {
                        Text("photos.withdraw.retry", tableName: "Photos")
                    }
                }
                Button(role: .cancel) {} label: {
                    Text("photos.common.close", tableName: "Photos")
                }
            } message: { _, error in
                switch error {
                case .forbidden: Text("photos.withdraw.forbidden", tableName: "Photos")
                default: Text("photos.withdraw.failed", tableName: "Photos")
                }
            }
    }
}
