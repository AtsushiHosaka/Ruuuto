import json, sys, urllib.request, urllib.parse
q='SELECT ?cc ?ja ?en WHERE { ?c wdt:P297 ?cc. OPTIONAL{?c rdfs:label ?ja FILTER(lang(?ja)="ja")} OPTIONAL{?c rdfs:label ?en FILTER(lang(?en)="en")} }'
req=urllib.request.Request('https://query.wikidata.org/sparql',data=urllib.parse.urlencode({'query':q,'format':'json'}).encode(),headers={'User-Agent':'city-list-research/0.1','Accept':'application/sparql-results+json'})
res={}
for b in json.load(urllib.request.urlopen(req,timeout=120))['results']['bindings']:
    res.setdefault(b['cc']['value'],{'ja':b.get('ja',{}).get('value'),'en':b.get('en',{}).get('value')})
json.dump(res,open(sys.argv[1],'w',encoding='utf-8'),ensure_ascii=False)
print(len(res))
