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

グループ選択とボードはHTMLの画面を参照する。ログインや通知設定など、HTMLに画面がない箇所は共通カラー、角丸のカード、丸みのある見出しを使って補う。日本語の文字はiOSのシステムフォントを使う。
