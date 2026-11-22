# Ruuuto 開発ガイド

仕様の基準は [spec.md](spec.md)。UI案は [画面デザイン](docs/design/eesu-ui-design.html)、担当と受け入れ条件は [JiraのRCNOボード](https://atsushi0130.atlassian.net/jira/software/projects/RCNO/boards/5) を参照する。仕様とJiraの記載に差があれば、担当者と判断をそろえてから仕様を更新する。

## 着手からPRまで

1. Jiraの課題を読み、対象の動作、完了条件、依存課題、担当者を確認する。着手したら「進行中」にし、未確定の仕様は関連課題に残す。
2. 最新の `main` から課題ごとにブランチを作る。例は `codex/rcno-6-group-switching`。別のPRが前提なら、そのブランチをベースにし、PR本文に先にマージするPRを記載する。前提PRがマージされたら、前提PRの変更が重複しないよう、自分の課題のコミットを最新の `main` に載せ直す。PRのベースを `main` に戻し、差分が課題の範囲に収まり、ビルドが通ることを確認する。
3. 1課題につき1PRを作る。タイトルは `[RCNO-6] 所属グループを切り替える` のように書く。修正を始める前に他の担当者の進行中の差分を確認し、共通の型やAPIを変えるときは利用側と合意する。
4. iOSは共有スキーム `Ruuuto` でビルドする。受け入れ条件を実際の画面・データ・対象環境で確認し、失敗、権限拒否、再試行など、課題に関係するケースも確認する。検証用データと実データを区別する。
5. `git diff --check` とPRの差分を確認してから提出する。結果が未確認の項目や、先にマージ・配備される必要のある作業があれば、ドラフトPRにして残件を明記する。
6. レビューの指摘を反映し、差分と必要な検証をやり直す。課題を「完了」にするのは、マージとJiraの受け入れ条件の確認が済んだ時点とする。

### PR本文と画面の証拠

| 欄 | 書くこと |
| --- | --- |
| 変更内容 | Jiraのリンク、利用者から見た変更、担当範囲 |
| 設計と影響範囲 | 変更した層、データの流れ、状態の管理場所、API・権限・マイグレーションの変更。設計判断を変えた場合は理由と仕様へのリンク |
| 検証 | 端末またはシミュレータ、OS、接続先の種別、操作手順と結果。ビルド、実機起動、本番配信のうち実施した確認 |
| 画面 | 変更後のスクリーンショット。既存画面を直した場合は比較に必要な変更前の画面 |
| 操作や遷移 | 操作の開始から結果までの短い動画。共同編集は可能なら2端末の同期を一緒に映す。PR上で動画の閲覧を確認 |

接続待ちでプレビューを使った場合は「プレビュー」と記載する。証拠がない項目には理由と追加確認の条件を書く。このリポジトリは公開設定なので、画像・動画・ログには検証用の名前と写真を使い、トークン、端末情報、実際の招待リンクや非公開の写真を含めない。

iOSシミュレータ向けのビルドはリポジトリのルートで実行する。

```sh
xcodebuild -project ios/Ruuuto.xcodeproj -scheme Ruuuto \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## アーキテクチャ

iOSはFeature-based MVVMで機能ごとにまとめ、Clean Architectureの依存方向に沿ってPresentation・Domain・Dataを分ける。画面状態はViewModel、Supabase接続はData、依存の組み立てと画面遷移はAppで扱う。配置先、依存関係、Repositoryの契約、接続時の確認事項は [iOSアーキテクチャ](docs/development/architecture.md) に従う。

## 国際化

利用者に表示する固定文言を追加・変更するPRでは、日本語と英語を登録し、両言語で表示を確認する。見出しやボタンに加え、エラー、空状態、アクセシビリティラベル、権限と通知の文言も対象とする。アプリ名はどちらの言語でもRuuutoとする。サーバーはクライアントが言語に応じて表示を選べるよう、エラーコードや構造化データを返す。 [iOSの表示言語](docs/development/ios-localization.md)

## Supabaseプロジェクトを用意する

あゆむは既存のチーム用プロジェクトがあるか確認する。新規の場合は [Supabaseのプロジェクト作成画面](https://supabase.com/dashboard/new) から、チームが管理できる組織に検証用を作る。組織、リージョン、プランと配布用の分離方法はチーム内で決める。配布用に切り替える前に、検証用でマイグレーションと権限を確認する。 [環境の課題](https://atsushi0130.atlassian.net/browse/RCNO-39)

iOS担当に、既存のチーム内共有先で次を届ける。

- 環境名、Project URL、Project Ref、Dashboardリンク。共同管理が必要な人は組織へ招待する。
- Dashboardの接続画面または `Settings → API Keys` にあるクライアント用のPublishable keyと、その設定先。iOSには `sb_publishable_` のキーを使う。
- 確定した認証方式、必要なリダイレクトURL、使用可能なRPC・Storage・Realtimeと、マイグレーションを適用した版。
- テストアカウントの登録・招待方法、疎通を確認する手順、問い合わせ先。

DBパスワード、`service_role`、`sb_secret_`、APNs署名鍵は、利用する担当者とサーバー用の秘密管理に分けて保管する。公開リポジトリ、Jira本文、times、iOSの設定ファイルへ貼らない。 [SupabaseのAPIキー](https://supabase.com/docs/guides/getting-started/api-keys)

## 毎日の進捗をtimesへ共有する

作業日の終了時に、メンター相談局で導入した `team-workflows` の `work-session` で、その日進んだことをまとめて自分の `#times-自分の名前` に投稿する。Claude Codeのコマンドは `/team-workflows:進捗共有`。振り返りも行う日は `/team-workflows:ふりかえり` を使える。

投稿には「実際に動いたこと」「確認方法と結果」「残っている作業・困っていること」「Jira・PRなどのリンク」を入れる。投稿をエージェントに任せる場合は、宛先と送信の許可が確認できるときに送る。確認できないときは下書きを本人に返す。 [作業報告スキル](https://github.com/AtsushiHosaka/team-ai-connectors/blob/main/plugins/team-workflows/skills/work-session/SKILL.md)
