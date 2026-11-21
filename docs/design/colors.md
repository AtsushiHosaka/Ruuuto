# iOSの共通カラー

[画面デザインHTML](eesu-ui-design.html)の初期表示は12月の「クリスマス・雪夜」。そのときの配色を [Asset Catalog](../../ios/Ruuuto/Assets.xcassets) に登録し、SwiftUIから [RuuutoPalette](../../ios/Ruuuto/Core/Design/RuuutoPalette.swift) を参照する。各画面では色の値を直接指定せず、用途に合う色を選ぶ。

| アセット | 色 | 用途 |
| --- | --- | --- |
| `RuuutoAccent` | `#6E9BF2` | 主操作、選択状態、装飾 |
| `RuuutoInk` | `#0D1A33` | ボードや認証の濃背景、薄背景の本文、青いボタンの文字 |
| `RuuutoPage` | `#F3F7FE` | グループ選択などの薄背景 |
| `RuuutoSoft` | `#283E68` | 濃背景上のカードやドット |
| `RuuutoLine` | `#BED2F9` | 薄背景の境界線、濃背景上の補助文字 |
| `RuuutoSub` | `#515A6C` | 薄背景上の補助文字 |

アクセントと濃背景はHTMLの指定値、そのほかはCSSの `color-mix()` をsRGBで計算し、8bitの値に丸めた標準色。季節ごとの色の切替は、HTML内の12か月分の定義を参照する。

グループ選択とボードは元のHTMLを参照する。グループ作成、招待受付、お題編集、通知設定は[承認済みの追加画面](ruuuto-flow-mock.html)に沿って作る。写真枠、シート、ボタンなど、役割がある部分に面を使う。

## 文字

SwiftUIでは、見出しにM PLUS Rounded 1c ExtraBold、本文にNoto Sans JP Regular相当、写真のキャプションにYusei Magicを使う。3書体はアプリに同梱する。

本文の書体を指定するときは、Viewで `@Environment(\.dynamicTypeSize)` を読み、`RuuutoType.body(.body, dynamicTypeSize: dynamicTypeSize)` に渡す。見出しとキャプションは `RuuutoType.rounded` と `RuuutoType.hand` で、それぞれの文字スタイルに合わせて拡大する。 [カスタムフォントとDynamic Type](https://developer.apple.com/documentation/swiftui/applying-custom-fonts-to-text)

[同梱フォントと各SIL Open Font License](../../ios/Ruuuto/Core/Design/Fonts) を参照する。

[フォントの配布元コミット](https://github.com/google/fonts/tree/06bfe0d62a98375cb09c942fa18e68bd32cff057/ofl)
