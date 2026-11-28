"""Ruuuto の都市一覧を作る。python -I build.py <dl> <work> <out.json> <out.csv>

有名な都市 = Wikipedia の言語版が100以上 / 首都 / 各国の人口上位3 / 日本の県庁所在地か人口30万以上。
それ以外の場所は「国 + 北部・南部・東部・西部・中部」の地域で選ぶ。
"""
import csv, json, sys, collections

dl, work, out_json, out_csv = sys.argv[1:5]
rows = list(csv.reader(open(f'{dl}/cities15000.txt', encoding='utf-8'), delimiter='\t'))
wd = json.load(open(f'{work}/wd.json', encoding='utf-8'))
cn = json.load(open(f'{work}/countries.json', encoding='utf-8'))
area = {}
for line in open(f'{dl}/countryInfo.txt', encoding='utf-8'):
    if line.startswith('#'):
        continue
    f = line.rstrip('\n').split('\t')
    area[f[0]] = float(f[6] or 0)

alt = json.load(open(f'{work}/alt.json', encoding='utf-8'))

def pop(r): return int(r[14])

# 東京23区は GeoNames で都市として登録されているものがあるが、都市としては扱わない
TOKYO_WARDS = {'Chiyoda', 'Chūō', 'Minato', 'Shinjuku', 'Bunkyō', 'Taitō', 'Sumida', 'Kotō', 'Shinagawa',
               'Meguro', 'Ōta', 'Setagaya', 'Shibuya', 'Nakano', 'Suginami', 'Toshima', 'Kita', 'Arakawa',
               'Itabashi', 'Nerima', 'Adachi', 'Katsushika', 'Edogawa'}

NYC_BOROUGHS = {'Brooklyn', 'Queens', 'Manhattan', 'The Bronx', 'Bronx', 'Staten Island'}

def is_area(r):
    # 都市の一部（地区）、東京の区、ニューヨークの区は除く
    return (r[7] == 'PPLX' or (r[8] == 'JP' and r[1] in TOKYO_WARDS)
            or (r[8] == 'US' and r[1] in NYC_BOROUGHS))

# GeoNames の英語名で崩れているもの
EN_FIX = {'Espoon keskus': 'Espoo', 'Sharjah city': 'Sharjah', 'Kaohsiung City': 'Kaohsiung',
          'Puebla City': 'Puebla', 'Davao City': 'Davao', 'Tuenmen': 'Tuen Mun',
          'Lexington-Fayette': 'Lexington'}
# 「市」まで含めて都市名のもの
KEEP_SHI = {'四日市', '廿日市'}

# 有名な都市を選ぶ
by_cc = collections.defaultdict(list)
for r in rows:
    if not is_area(r):
        by_cc[r[8]].append(r)
picked = set()
for cc, rs in by_cc.items():
    rs.sort(key=pop, reverse=True)
    picked.update(r[0] for r in rs[:3])
for r in rows:
    g = r[0]
    if is_area(r):
        continue
    if r[7] == 'PPLC' or wd.get(g, {}).get('sl', 0) >= 100:
        picked.add(g)
    # 日本: 県庁所在地と、人口30万以上の市
    if r[8] == 'JP' and (r[7] == 'PPLA' or (r[7] == 'PPLA2' and pop(r) >= 300000)):
        picked.add(g)

def has_cjk(s): return any('぀' <= ch <= 'ヿ' or '一' <= ch <= '鿿' for ch in s)

def best_alt(g, lang):
    # GeoNames の別名: 正式名 > 短縮名 > その他。俗称と旧称は使わない
    cands = [a for a in alt.get(g, []) if a[0] == lang and not a[4] and not a[5]]
    if lang == 'ja':
        cands = [a for a in cands if has_cjk(a[1])]
    cands.sort(key=lambda a: (not a[2], not a[3]))  # 同順位なら GeoNames の並び順
    return cands[0][1] if cands else None

def ja_name(r):
    w = (wd.get(r[0]) or {}).get('ja')
    name = best_alt(r[0], 'ja') or (w if w and has_cjk(w) else None)
    if not name:
        return None
    if name in KEEP_SHI:
        return name
    # 「〜市」「東京都」「ソウル特別市」は都市名だけにする
    for suf in ('特別市', '広域市', '直轄市', '市', '都'):
        if r[8] in ('JP', 'CN', 'TW', 'KR') and name.endswith(suf) and len(name) > len(suf):
            return name[:-len(suf)]
    # 行政区画の名前で登録されているもの（「アルビール県」「ヤレン地区」）
    for suf in ('教区', '地区', '県'):
        if r[8] != 'JP' and name.endswith(suf) and len(name) > len(suf):
            return name[:-len(suf)].rstrip('＝=')
    return name

def en_name(r):
    name = best_alt(r[0], 'en') or (wd.get(r[0]) or {}).get('en') or r[2]
    name = EN_FIX.get(name, name)
    return name[:-len(' District')] if name.endswith(' District') else name

cities, dropped = [], []
for r in rows:
    if r[0] not in picked:
        continue
    ja = ja_name(r)
    if not ja:  # 日本語名が見つからない都市は一覧に入れない（地域で選べる）
        dropped.append((r[1], r[8], pop(r)))
        continue
    cities.append({
        'id': f'gn:{r[0]}', 'ja': ja, 'en': en_name(r),
        'country': r[8], 'lat': round(float(r[4]), 3), 'lng': round(float(r[5]), 3), 'tz': r[17],
        '_pop': pop(r), '_sl': wd.get(r[0], {}).get('sl', 0),
    })

# 地域
PARTS = {'N': ('北部', 'Northern'), 'S': ('南部', 'Southern'), 'E': ('東部', 'Eastern'),
         'W': ('西部', 'Western'), 'C': ('中部', 'Central')}

def wpct(vals, ws, p):
    pairs = sorted(zip(vals, ws)); total = sum(ws); acc = 0
    for v, w in pairs:
        acc += w
        if acc >= total * p:
            return v
    return pairs[-1][0]

regions = []
for cc, rs in sorted(by_cc.items()):
    names = cn.get(cc) or {}
    cja, cen = names.get('ja') or cc, names.get('en') or cc
    lats = [float(r[4]) for r in rs]
    lngs = [float(r[5]) for r in rs]
    if min(lngs) < -150 and max(lngs) > 150:  # 日付変更線をまたぐ国（ロシア、フィジーなど）
        lngs = [x + 360 if x < 0 else x for x in lngs]
    ws = [max(pop(r), 1) for r in rs]

    def summarize(idx):
        w = [ws[i] for i in idx]; t = sum(w)
        lat = sum(lats[i] * ws[i] for i in idx) / t
        lng = sum(lngs[i] * ws[i] for i in idx) / t
        if lng > 180: lng -= 360
        tz = collections.Counter()
        for i in idx: tz[rs[i][17]] += ws[i]
        return round(lat, 3), round(lng, 3), tz.most_common(1)[0][0]

    if area.get(cc, 0) < 50000 or len(rs) < 5:
        lat, lng, tz = summarize(range(len(rs)))
        regions.append({'id': f'region:{cc}', 'ja': cja, 'en': cen, 'country': cc,
                        'lat': lat, 'lng': lng, 'tz': tz})
        continue
    lo_y, hi_y = wpct(lats, ws, .05), wpct(lats, ws, .95)
    lo_x, hi_x = wpct(lngs, ws, .05), wpct(lngs, ws, .95)
    groups = collections.defaultdict(list)
    for i in range(len(rs)):
        u = (lngs[i] - lo_x) / ((hi_x - lo_x) or 1) - .5
        v = (lats[i] - lo_y) / ((hi_y - lo_y) or 1) - .5
        if max(abs(u), abs(v)) < .2: k = 'C'
        elif abs(v) >= abs(u): k = 'N' if v > 0 else 'S'
        else: k = 'E' if u > 0 else 'W'
        groups[k].append(i)
    for k in 'NSEWC':
        if k not in groups:
            continue
        lat, lng, tz = summarize(groups[k])
        pja, pen = PARTS[k]
        regions.append({'id': f'region:{cc}-{k}', 'ja': cja + pja, 'en': f'{pen} {cen}', 'country': cc,
                        'lat': lat, 'lng': lng, 'tz': tz})

cities.sort(key=lambda c: (c['country'], -c['_pop']))

# 同じ国で同じ日本語名の都市が50km以内にあれば、人口の多い方だけ残す（Lexington と Lexington-Fayette など）
def near(a, b): return abs(a['lat'] - b['lat']) < .45 and abs(a['lng'] - b['lng']) < .6
kept = []
for c in cities:
    if not any(k['country'] == c['country'] and k['ja'] == c['ja'] and near(k, c) for k in kept):
        kept.append(c)
cities = kept
same_name = collections.Counter((c['country'], c['ja']) for c in cities)
dup_names = sorted(k for k, n in same_name.items() if n > 1)
with open(out_csv, 'w', encoding='utf-8-sig', newline='') as f:
    w = csv.writer(f)
    w.writerow(['種類', 'id', '日本語', '英語', '国', '緯度', '経度', 'タイムゾーン', '人口', 'Wikipedia言語版'])
    for c in cities:
        w.writerow(['都市', c['id'], c['ja'], c['en'], c['country'], c['lat'], c['lng'], c['tz'], c['_pop'], c['_sl']])
    for r in regions:
        w.writerow(['地域', r['id'], r['ja'], r['en'], r['country'], r['lat'], r['lng'], r['tz'], '', ''])
for c in cities:
    del c['_pop'], c['_sl']
json.dump({'version': 1,
           'source': 'GeoNames cities15000 (CC BY 4.0, https://www.geonames.org/), Wikidata labels (CC0)',
           'cities': cities, 'regions': regions},
          open(out_json, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))

# 自己検査
ids = [x['id'] for x in cities + regions]
assert len(ids) == len(set(ids)), 'id の重複'
assert all(len(i) <= 60 for i in ids), 'city 列は60字まで'
assert all(-90 <= x['lat'] <= 90 and -180 <= x['lng'] <= 180 and x['tz'] for x in cities + regions)
need = {'gn:1850147': '東京', 'gn:6173331': 'バンクーバー', 'gn:1853909': '大阪', 'gn:2643743': 'ロンドン',
        'gn:3448439': 'サンパウロ', 'gn:3117735': 'マドリード', 'gn:1835848': 'ソウル'}
got = {c['id']: c['ja'] for c in cities}
for k, v in need.items():
    assert got.get(k) == v, (k, got.get(k))
names = {c['ja'] for c in cities}
assert '四日市' in names and '四日' not in names and 'ブルックリン区' not in names
print('cities', len(cities), 'regions', len(regions), 'dropped', len(dropped), 'same-name', dup_names)
json.dump(dropped, open(f'{work}/dropped.json', 'w', encoding='utf-8'), ensure_ascii=False)
