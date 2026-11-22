# Ruuuto 初回リリース仕様案

初回リリースの目標日は2026年11月25日。iPhone向けにTestFlightで配布する。遠くに住む友達が週ごとのお題に沿って写真を持ち寄り、一つのボードを共同編集する。 [Jiraの初回リリース](https://atsushi0130.atlassian.net/browse/RCNO-1) · [iOSの配布準備](docs/development/ios-distribution.md)

GitHubの `main` 更新でXcode Cloudの配布ワークフローを起動し、指定したTestFlightの外部テスターグループに配布する。初回の外部配布はAppleのベータ審査を通過してから始まる。

アプリ名はすべての言語で「Ruuuto」とする。表示言語はiOSの設定に従い、日本語を既定として英語にも対応する。利用者が入力した名前・お題・投稿の文言は入力どおりに表示する。 [iOSの表示言語](docs/development/ios-localization.md)

## 要件

| ID | 初回リリースで実現すること |
| --- | --- |
| R1 | 利用者はメールアドレスとパスワードでログインし、グループを作れる。友達は招待リンクから参加でき、複数グループに所属できる。 |
| R2 | 開催中のお題はグループごとに常に1件。週次で固定のお題が切り替わり、利用者は独自のお題にも変更できる。固定のお題はSlackの月別・週別のお題案を使う。 |
| R3 | お題が変わったら、通知を許可した参加者にプッシュ通知を送る。 |
| R4 | 参加者はアプリ内で撮影するか、端末のライブラリから写真を選び、開催中のボードに投稿できる。 |
| R5 | グループの全員が、他の参加者が投稿した写真も自由に配置できる。編集中の参加者と、そのカーソルを共有する。 |
| R6 | ボードに文字、スタンプ、ペンの線を追加できる。 |
| R7 | 締切後のボードは閲覧できる。新規投稿と配置・装飾の編集は締め切る。投稿者は自分の写真を締切後も取り下げられる。 |
| R8 | 参加者は月別カレンダーから過去のボードを開ける。日がたったボードは表示を退色させる。 |
| R9 | 都市別マップから、共有された写真を都市ごとに見られる。画像のGPSメタデータから撮影位置が共有されないようにする。 |

画面案はホーム、撮影、都市別マップ、月別の振り返り、グループ選択。添付HTML内の期限、人数、都市、時差は表示例。初回投稿に添付された画像は未確認。 [Slackの仕様スレッド](https://w1792145450-sdd231600.slack.com/archives/C0CHA1ZBWBH/p1795256359860839) · [固定のお題案](https://w1792145450-sdd231600.slack.com/archives/C0CHA1ZBWBH/p1794652958977149) · [画面デザイン案](docs/design/eesu-ui-design.html)

## 設計案

バックエンドはSupabaseで作る。iOSはSupabase Swiftクライアントから接続する。利用者の識別にAuth、グループ・お題・ボード・写真の参照情報の保存にPostgres、画像の保管に非公開のStorageを使う。公開するテーブルと画像はグループの所属に基づいてアクセスを制御し、iOSには公開用キーを渡す。 [Swiftクライアント](https://supabase.com/docs/reference/swift/introduction) · [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) · [Storageのアクセス制御](https://supabase.com/docs/guides/storage/security/access-control)

ボード単位の非公開Realtimeチャネルで、保存済みの変更と一時的な参加者・カーソル情報を共有する。週の切替はCronで起動する。プッシュはEdge FunctionsからAPNsに送り、iOS側で受信と対象画面への遷移を扱う。 [Realtimeのアクセス制御](https://supabase.com/docs/guides/realtime/authorization) · [Cron](https://supabase.com/docs/guides/cron) · [Edge Functions](https://supabase.com/docs/guides/functions)

グループごとに参加者、開催中のボード、終了済みのボードを管理する。週次の切替は、既存のボードを締め切る処理と次のボードを公開する処理を一体で行う。参加と編集の権限は、画面の表示と保存処理の両方で確認する。

写真、配置、装飾は再表示や再接続のあとも復元する。編集中の参加者とカーソルは一時的な表示とし、退出または切断時に解除する。同じ写真を同時に動かしたときは、保存結果が両端末で一致するようにする。

カレンダーでは、月を選ぶと対象月の週別ボードを一覧にする。退色は表示に適用し、保存した画像は維持する。地図では都市を表示の単位とし、投稿に位置を付けない場合もボードに写真を掲載できる案とする。

## 仕様の確認が必要な点

| 対象 | 未確定の判断 |
| --- | --- |
| R1 | メール確認とアカウント復旧の手順、招待リンクのドメインと有効期限 |
| R2 | 週の切替時刻、第5週のお題、手動変更の権限、変更前の投稿と締切の扱い |
| R3 | 手動変更時に変更者本人へ配信するか、短時間に複数回変更した場合の配信 |
| R4–R6 | 最低対応iOS、写真の上限、装飾の変更・削除権限 |
| R8 | 退色の起点、期間、表示を変える部分 |
| R9 | 都市の入力方法、マップに表示するボードの範囲 |
| 配布 | 対象iPhone、Apple Developerチーム、TestFlightのテストグループ |

## 開発分担

iOSの開発は [Xcodeプロジェクト](ios/Ruuuto.xcodeproj) を開き、共有スキーム `Ruuuto` を選ぶ。初期設定の最低対応OSは暫定でiOS 17とし、配布対象の端末を確認して確定する。

| 担当 | 作業範囲 |
| --- | --- |
| あゆむ | Supabase全般。認証、所属と招待、データと権限、画像、リアルタイム配信、週次切替と通知配信、配布用の接続先を担当する。 |
| ルート | iOSの撮影、ライブラリと共通投稿、写真の取り下げ、都市別マップ、月別カレンダーと退色を担当する。 |
| さな | iOSの共同編集ボード。写真の配置、文字・スタンプ・ペン、編集内容の受信、参加者とカーソルの表示を担当する。 |
| あつし | iOSの認証と、ログイン後のグループ・招待・お題・通知の状態管理、画面遷移、ViewModel、結合と配布を担当する。 |

## Jira課題

各課題に定性的な達成目標と、受け入れ試験で確認する定量目標を記載する。定量目標の件数は試験条件の提案値。要件の未確定部分は該当する課題に記載する。

| 要件 | 課題 | 内容 | 担当 |
| --- | --- | --- | --- |
| R1 | [RCNO-2](https://atsushi0130.atlassian.net/browse/RCNO-2) | 参加者を識別して再訪時に復元する | あつし |
| R1 | [RCNO-3](https://atsushi0130.atlassian.net/browse/RCNO-3) | 誰でもグループを作れるようにする | あつし |
| R1 | [RCNO-7](https://atsushi0130.atlassian.net/browse/RCNO-7) | 招待からグループに参加する | あつし |
| R1 | [RCNO-6](https://atsushi0130.atlassian.net/browse/RCNO-6) | 所属グループを切り替える | あつし |
| R1 | [RCNO-5](https://atsushi0130.atlassian.net/browse/RCNO-5) | グループ外からの操作を拒否する | あゆむ |
| R2 | [RCNO-4](https://atsushi0130.atlassian.net/browse/RCNO-4) | Slackのお題案を週次の初期データにする | あゆむ |
| R2 | [RCNO-8](https://atsushi0130.atlassian.net/browse/RCNO-8) | 開催中のお題と締切を表示する | あつし |
| R2 | [RCNO-10](https://atsushi0130.atlassian.net/browse/RCNO-10) | 週の切替で次のお題を公開する | あゆむ |
| R2 | [RCNO-12](https://atsushi0130.atlassian.net/browse/RCNO-12) | グループのお題を自由入力で変更する | あつし |
| R3 | [RCNO-11](https://atsushi0130.atlassian.net/browse/RCNO-11) | 端末でプッシュ通知を許可する | あつし |
| R3 | [RCNO-9](https://atsushi0130.atlassian.net/browse/RCNO-9) | お題変更をプッシュで知らせる | あゆむ |
| R4・R7 | [RCNO-13](https://atsushi0130.atlassian.net/browse/RCNO-13) | ライブラリの写真を投稿する | ルート |
| R4・R7 | [RCNO-16](https://atsushi0130.atlassian.net/browse/RCNO-16) | アプリ内で撮影して投稿する | ルート |
| R4・R7 | [RCNO-15](https://atsushi0130.atlassian.net/browse/RCNO-15) | 投稿失敗を再試行する | ルート |
| R4・R7 | [RCNO-14](https://atsushi0130.atlassian.net/browse/RCNO-14) | 投稿者が自分の写真を取り下げる | ルート |
| R5 | [RCNO-17](https://atsushi0130.atlassian.net/browse/RCNO-17) | 参加者が写真を自由に配置する | さな |
| R5 | [RCNO-18](https://atsushi0130.atlassian.net/browse/RCNO-18) | 別端末へ編集内容を同期する | さな |
| R5 | [RCNO-19](https://atsushi0130.atlassian.net/browse/RCNO-19) | 同じ写真を同時に動かしたときの結果をそろえる | あゆむ |
| R5 | [RCNO-20](https://atsushi0130.atlassian.net/browse/RCNO-20) | 編集中のメンバーを表示する | さな |
| R5 | [RCNO-21](https://atsushi0130.atlassian.net/browse/RCNO-21) | 他の参加者のカーソルを表示する | さな |
| R6 | [RCNO-22](https://atsushi0130.atlassian.net/browse/RCNO-22) | ボードに文字を置く | さな |
| R6 | [RCNO-24](https://atsushi0130.atlassian.net/browse/RCNO-24) | ボードにスタンプを置く | さな |
| R6 | [RCNO-23](https://atsushi0130.atlassian.net/browse/RCNO-23) | ペンで描画する | さな |
| R6 | [RCNO-25](https://atsushi0130.atlassian.net/browse/RCNO-25) | 装飾を編集・削除する | さな |
| R7・R8 | [RCNO-27](https://atsushi0130.atlassian.net/browse/RCNO-27) | 締切後の投稿と編集を閉じる | あゆむ |
| R7・R8 | [RCNO-26](https://atsushi0130.atlassian.net/browse/RCNO-26) | 月別カレンダーから過去ボードを開く | ルート |
| R7・R8 | [RCNO-28](https://atsushi0130.atlassian.net/browse/RCNO-28) | 日がたったボードを退色させる | ルート |
| R9 | [RCNO-29](https://atsushi0130.atlassian.net/browse/RCNO-29) | 投稿に任意で都市を紐付ける | ルート |
| R9 | [RCNO-30](https://atsushi0130.atlassian.net/browse/RCNO-30) | 写真から意図しない位置情報の公開を防ぐ | ルート |
| R9 | [RCNO-31](https://atsushi0130.atlassian.net/browse/RCNO-31) | 都市別マップで写真を探す | ルート |
| 横断 | [RCNO-32](https://atsushi0130.atlassian.net/browse/RCNO-32) | 11月25日までの配布方法と対象端末を確定する | あつし |
| 横断 | [RCNO-33](https://atsushi0130.atlassian.net/browse/RCNO-33) | 2人で招待から振り返りまで通しで確認する | あつし |

### バックエンドの基盤

| 課題 | 内容 | 担当 |
| --- | --- | --- |
| [RCNO-34](https://atsushi0130.atlassian.net/browse/RCNO-34) | データモデルと初期マイグレーションを用意する | あゆむ |
| [RCNO-35](https://atsushi0130.atlassian.net/browse/RCNO-35) | 非公開の画像ストレージと削除処理を用意する | あゆむ |
| [RCNO-36](https://atsushi0130.atlassian.net/browse/RCNO-36) | ボード単位のリアルタイム配信を用意する | あゆむ |
| [RCNO-38](https://atsushi0130.atlassian.net/browse/RCNO-38) | 週次切替ジョブの実行と失敗時の再実行を用意する | あゆむ |
| [RCNO-37](https://atsushi0130.atlassian.net/browse/RCNO-37) | プッシュの配信処理と無効な端末登録の処理を用意する | あゆむ |
| [RCNO-39](https://atsushi0130.atlassian.net/browse/RCNO-39) | 初回配布用バックエンドの環境と動作確認を整える | あゆむ |
| [RCNO-40](https://atsushi0130.atlassian.net/browse/RCNO-40) | Supabase Authと参加者情報を設定する | あゆむ |
| [RCNO-42](https://atsushi0130.atlassian.net/browse/RCNO-42) | Supabaseでグループ作成と招待参加を実装する | あゆむ |
| [RCNO-43](https://atsushi0130.atlassian.net/browse/RCNO-43) | 開催中・履歴・都市別のボード参照を実装する | あゆむ |
| [RCNO-41](https://atsushi0130.atlassian.net/browse/RCNO-41) | 手動のお題変更をSupabaseで保存する | あゆむ |
