# 都市の一覧を作り直す

`ios/Ruuuto/Features/Map/Data/cities.json`（RCNO-29）を作るスクリプト。アプリのビルドには使わない。

## 一覧の決まり

- 都市: 次のどれかに当てはまるもの。Wikipedia の言語版が100以上、各国の首都、各国の人口上位3、日本の県庁所在地と人口30万以上の市。東京23区とニューヨークの区は都市として載せない。日本語名が見つからない都市は外す
- 地域: 国ごとに「北部・南部・東部・西部・中部」。面積5万km²未満の国は国全体を1件にする。代表点は人口で重みを付けた中心、タイムゾーンはその地域で人口が最も多いもの
- ID: 都市は `gn:<GeoNames ID>`、地域は `region:<国コード>-<N|S|E|W|C>`（1件の国は `region:<国コード>`）。photos.city に保存するのはこのID

## 手順

```sh
mkdir dl work
curl -o dl/cities15000.zip https://download.geonames.org/export/dump/cities15000.zip && unzip dl/cities15000.zip -d dl
curl -o dl/countryInfo.txt https://download.geonames.org/export/dump/countryInfo.txt
python -I tools/cities/wd.py dl work/wd.json            # Wikipedia の言語版の数と日本語名（Wikidata）
python -I tools/cities/countries.py work/countries.json # 国名（Wikidata）
# alternateNamesV2.zip から日本語名と英語名だけを work/alt.json に抜き出す（約200MB）
python -I tools/cities/build.py dl work ios/Ruuuto/Features/Map/Data/cities.json cities.csv
```

`build.py` は最後に自己検査（IDの重複と長さ、座標、東京・大阪・ソウル・サンパウロなどの名前）を実行する。

## 出典

- GeoNames cities15000、alternateNames（CC BY 4.0、https://www.geonames.org/）。アプリ内のライセンス表示に記載が要る
- Wikidata のラベル（CC0）
