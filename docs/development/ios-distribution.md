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

Xcodeで配布用のArchiveを作り、App Store Connectへ送信して対象のTestFlightグループに割り当てる。対象iPhoneにインストールし、起動、カメラ権限、撮影、通知の許可、プッシュの到着とタップ後の遷移を確認する。通知には登録したApp IDのPush Notifications設定と、配布用APNsのサーバー設定が必要。配布経路、ビルド番号、端末、OS、確認結果をJiraに残す。 [APNsへの登録](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns) · [TestFlight](https://developer.apple.com/testflight/)
