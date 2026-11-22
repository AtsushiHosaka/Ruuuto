# iOSの表示言語

Ruuutoの開発言語は日本語（`ja`）。日本語と英語（`en`）に対応し、表示言語はiOSの言語設定に従う。アプリの表示名はどちらも `Ruuuto` とする。

共通文言は `Localizable.xcstrings`、機能固有の文言は必要に応じて機能別のString Catalogに追加する。機能と用途が分かるキーを付け、日本語と英語を登録する。SwiftUIでは `Text`、表示用に `String` が必要な箇所では `String(localized:)` を使う。表示名やグループ名など、利用者が入力した文章は `Text(verbatim:)` で表示する。日付・時刻・数値の表示には、端末の言語と地域に従う `FormatStyle` を使う。 [文字列カタログ](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)

iOSが表示するカメラの権限文言は `ios/Ruuuto/InfoPlist.xcstrings` で管理する。`ios/Configuration/Info.plist` にも既定の日本語文言を置き、日本語を修正するときは両方を更新する。 [Info.plistのローカライズ](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AboutInformationPropertyListFiles.html)

Xcodeの共有スキーム `Ruuuto` の実行オプションでアプリの言語を日本語と英語に切り替える。変更した画面の文言を両方で確認し、権限文言を変更した場合はその言語で初めてカメラへのアクセスを求めたときのダイアログを確認する。
