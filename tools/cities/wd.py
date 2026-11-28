import csv, json, sys, time, urllib.request, urllib.parse
dl, out = sys.argv[1], sys.argv[2]
rows=[r for r in csv.reader(open(dl+'/cities15000.txt',encoding='utf-8'),delimiter='\t')]
ids=[r[0] for r in rows if int(r[14])>=100000 or r[7]=='PPLC']
res={}
for i in range(0,len(ids),400):
    vals=' '.join('"%s"'%x for x in ids[i:i+400])
    q='SELECT ?gn ?ja ?en ?sl WHERE { VALUES ?gn {%s} ?item wdt:P1566 ?gn; wikibase:sitelinks ?sl. OPTIONAL{?item rdfs:label ?ja FILTER(lang(?ja)="ja")} OPTIONAL{?item rdfs:label ?en FILTER(lang(?en)="en")} }'%vals
    req=urllib.request.Request('https://query.wikidata.org/sparql',data=urllib.parse.urlencode({'query':q,'format':'json'}).encode(),headers={'User-Agent':'city-list-research/0.1','Accept':'application/sparql-results+json'})
    for b in json.load(urllib.request.urlopen(req,timeout=120))['results']['bindings']:
        g=b['gn']['value']; sl=int(b['sl']['value'])
        if g not in res or sl>res[g]['sl']:
            res[g]={'sl':sl,'ja':b.get('ja',{}).get('value'),'en':b.get('en',{}).get('value')}
    print(i,len(res),file=sys.stderr); time.sleep(1)
json.dump(res,open(out,'w',encoding='utf-8'),ensure_ascii=False)
