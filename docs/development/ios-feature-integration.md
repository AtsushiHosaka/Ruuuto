# ログイン後のiOS実装をつなぐ

認証済みの利用者ごとに `SignedInWorkspace` がViewModelを組み立てる。画面は同じWorkspaceを環境から受け取り、遷移先の `destination` と各ViewModelの状態を描画する。画面でSupabaseクライアントを作る必要はない。

| 操作 | 画面から使う入口 |
| --- | --- |
| 所属一覧・ボード | `groups` で一覧を表示し、`selectGroup(_:)` で切り替える。`currentBoard.state(for:)` で選択中のグループのボードを読む。 |
| グループ作成 | `showGroupCreation()` で始め、`groupCreation.submit()` で作成する。成功時は新しいグループのボードに進む。 [RCNO-44](https://atsushi0130.atlassian.net/browse/RCNO-44) |
| 招待 | 受け付けには `invitation` と `acceptInvitation()` を使う。発行は `showInvitationSharing()` と `invitationShare.requestLink()`、OSの共有シートは `shareInvitation()` を使う。 [RCNO-45](https://atsushi0130.atlassian.net/browse/RCNO-45) |
| お題変更 | `showTopicEditor()` で対象ボードの編集を開始し、`topicEditor` で入力を管理する。`saveTopic()` は保存後に同じグループのボードを読み直す。 [RCNO-46](https://atsushi0130.atlassian.net/browse/RCNO-46) |
| 通知設定 | `showNotificationSettings()` で開き、`notifications` の許可状態、端末同期、エラーと再試行を表示する。 [RCNO-47](https://atsushi0130.atlassian.net/browse/RCNO-47) |

通知を開くと、所属一覧を取得し直してアクセスできるグループかを確認する。通知のボードIDが開催中のものと異なる場合は、過去ボードの遷移先を渡す。表示時のボード取得と所属確認は履歴画面側で行う。 [RCNO-26](https://atsushi0130.atlassian.net/browse/RCNO-26)

## Supabase側と照合する暫定契約

iOSのアダプターは、Supabase Authのセッションを使って以下のRPCを呼び出す。プロジェクト公開前に、あゆむと関数名、入力、戻り値、エラーコードを照合する。テーブル名やサーバーの権限をiOS側で決める必要はない。

| 関連課題 | RPCと引数 | 結果 |
| --- | --- | --- |
| RCNO-42 | `ruuuto_list_groups()` | 本人が所属するグループの配列。各要素は `id` と `name` |
| RCNO-42 | `ruuuto_create_group(p_name)` | 作成したグループの単一オブジェクト。 `id` と `name` |
| RCNO-42 | `ruuuto_issue_invitation(p_group_id)` | `token` を持つ単一オブジェクト。発行権限、有効期限と失効はサーバーで判定 |
| RCNO-42 | `ruuuto_accept_invitation(p_token)` | `group_id` を持つ単一オブジェクト。参加済みは同じ成功結果。無効は `RC003`、期限切れは `RC004` |
| RCNO-43 | `ruuuto_current_board(p_group_id)` | `id`、`group_id`、`topic`、`opens_at`、`closes_at` を持つ単一オブジェクト。時刻はオフセット付きのISO 8601 |
| RCNO-41 | `ruuuto_save_topic(p_board_id, p_topic)` | 保存が確定したら成功。権限拒否は `42501`、入力エラーは `RC001`、ボードの締切後は `RC002` |
| RCNO-37 | `ruuuto_sync_device(p_installation_id, p_apns_token)` | 本人の端末登録を反映したら成功。解除時はトークンがJSONの `null`。通知のカスタム項目は `group_id` と `board_id` |

iOSはアプリのインストールごとに端末登録用のIDを保持し、通知許可またはトークンの変更を同期する。サインアウト時は同じセッションで端末登録の解除を試み、端末側のリモート通知登録を解除してからログアウトする。次回の登録では、サーバーが同じインストールIDを現在の利用者へ付け替える。APNsの署名鍵と送信設定はバックエンドで管理する。

## 環境が決まったら設定する値

手元で実行する場合はXcodeのスキームに `RUUUTO_SUPABASE_URL`、`RUUUTO_SUPABASE_PUBLISHABLE_KEY` と必要に応じて `RUUUTO_INVITATION_URL` を設定する。TestFlightではビルド時に設定する。 [配布用の環境変数](ios-distribution.md)

招待URLの形式は `https://<招待ドメイン>/invite/<token>`。招待の発行と受け付けで同じホストを使う。実際のiPhoneでリンクからアプリを開くには、Apple DeveloperのApp IDでAssociated Domainsを有効にし、ターゲットに `applinks:<招待ドメイン>` を設定する。招待ドメインの `/.well-known/apple-app-site-association` に同じApp IDとパスを登録する。APNs実機試験には同じApp IDのPush Notifications設定も必要。 [AppleのAssociated Domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
