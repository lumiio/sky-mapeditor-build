import json,sys
d=json.load(sys.stdin)['devices']
for rt,devs in d.items():
    for x in devs:
        if x.get('isAvailable') and x['name'].startswith('iPhone'):
            print(x['udid']); sys.exit(0)
print('')
