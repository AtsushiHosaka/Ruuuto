# iOSの配布準備

対象はiPhone。Xcodeで `ios/Ruuuto.xcodeproj` を開き、共有スキーム `Ruuuto` を使う。最低対応OSは暫定でiOS 17、バンドルIDは暫定で `com.atsushihosaka.ruuuto`。11月25日の初回版はTestFlightで配布する。対象端末とApple Developerチームは署名前に確認する。 [配布課題](https://atsushi0130.atlassian.net/browse/RCNO-32)

## 開発用と配布用の設定

開発用は `ios/Configuration/Local.Debug.xcconfig`、配布用は `ios/Configuration/Local.Release.xcconfig` を各自の環境で用意する。どちらもGitの対象外。設定がなければ接続値を空にしてビルドできる。接続が必要な検証では、あゆむから指定された環境の値を入れる。 [Supabase環境の課題](https://atsushi0130.atlassian.net/browse/RCNO-39)

| 設定名 | 値 |
| --- | --- |
| `RUUUTO_SUPABASE_HOST` | Project URLのホスト名だけ。例は `example.supabase.co` |
| `RUUUTO_SUPABASE_PUBLISHABLE_KEY` | 対象環境のクライアント用キー |
| `DEVELOPMENT_TEAM` | 実機・配布ビルドを署名するApple Developer Team ID |
| `PRODUCT_BUNDLE_IDENTIFIER` | 登録したApp IDが初期値と異なる場合に指定 |

データベース用やサーバー用の秘密情報はiOSの設定に入れない。配布ビルドでは検証用と配布用の接続先を照合し、Archiveに意図した設定が入っていることを確認する。

## ビルドと配布確認

シミュレータ向けにビルドする。署名と実機配布の確認はここでは行わない。

```sh
xcodebuild -project ios/Ruuuto.xcodeproj -scheme Ruuuto \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

TestFlightで配布したビルドを対象iPhoneにインストールし、起動、カメラ権限、撮影、通知の許可、プッシュの到着とタップ後の遷移を確認する。通知には登録したApp IDのPush Notifications設定と、配布用APNsのサーバー設定が必要。対象コミット、Xcode Cloudのビルド番号と結果、TestFlightの外部配布状況、端末とOSをJiraに残す。 [APNsへの登録](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns) · [TestFlight](https://developer.apple.com/testflight/)

## Xcode CloudからTestFlightへ配布する

初回の外部配布までに、配布対象のターゲットへRuuutoのアプリアイコンを登録し、App Store Connectで輸出コンプライアンスとベータ審査情報を確認する。 [配布の準備](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)

1. Xcodeで共有スキーム `Ruuuto` を選び、Apple Developerチームと登録済みのバンドルIDを確認する。初回セットアップではXcode CloudにGitHubの `AtsushiHosaka/Ruuuto` を接続し、配布アクションを付けずにビルドを確認する。 [初回ワークフローの設定](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow)
2. App Store ConnectでRuuutoの外部テスターグループとベータ審査情報を用意する。以下の設定で配布用ワークフローを作り、接続先とキーをEnvironmentに設定する。 [配布用ワークフロー](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution) · [外部テスターの設定](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
3. PRをマージして `main` が更新されたら、Xcode Cloudで該当コミットのArchiveと外部配布の実行を確認する。初回はAppleのTestFlight App Reviewを通過してから配布される。App Store Connectで審査状況、グループへの割り当てと `Testing` への遷移を確認する。

| ワークフローの項目 | 設定 |
| --- | --- |
| 名前 | `Main → TestFlight External` |
| Start Conditions | Branch Changesで `main` のみ |
| GeneralとEnvironment | Restrict EditingとCleanを有効にする |
| Actions | iOSの共有スキーム `Ruuuto` をArchive。Deployment Preparationは `TestFlight and App Store` |
| Post-Actions | `TestFlight External Testing` でRuuutoの外部テスターグループを指定 |

| ワークフローの環境変数 | 値 |
| --- | --- |
| `RUUUTO_RELEASE_SUPABASE_HOST` | 配布用SupabaseのProject URLのホスト名 |
| `RUUUTO_RELEASE_SUPABASE_PUBLISHABLE_KEY` | 同じ環境の `sb_publishable_` で始まるキー |
| `RUUUTO_REQUIRE_SUPABASE_FOR_ARCHIVE` | 2つの接続値を必須にする配布ワークフローに `1` を設定 |

`ios/ci_scripts/ci_post_clone.sh` は、Xcode Cloud内で接続値を `ios/Configuration/Cloud.Release.xcconfig` に書き込む。ReleaseはこのGit管理外のファイルがあるときに読み込む。配布ワークフローで必須化した後は、接続値がそろわないArchiveを中断する。通常のBuildや必須化前のArchiveでは、接続値を両方省略できる。 [ビルドスクリプト](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts) · [アクションの環境変数](https://developer.apple.com/documentation/xcode/environment-variable-reference)

日本語の確認項目は `ios/TestFlight/WhatToTest.ja.txt` に置く。配布前に、実際に含まれる変更と照合して更新する。 [TestFlightの確認項目](https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app)
