import re,sys,os
p='/tmp/qa-boot.log'
if not os.path.exists(p):
    print('QA FAIL: 没有 boot.log（App 可能在启动阶段就挂了）'); sys.exit(1)
s=open(p,encoding='utf-8',errors='ignore').read()
if 'first frame ok' not in s:
    print('QA FAIL: 没走到 first frame ok'); sys.exit(1)
probes=re.findall(r'探针 f\d+ .*?地形=\(([^)]*)\)', s)
if not probes:
    print('QA FAIL: 日志里没有探针读数'); sys.exit(1)
clear=(0.03,0.05,0.09)
bad=0
for t in probes:
    v=tuple(round(float(x),4) for x in t.split(',')[:3])
    print('probe', v)
    if all(abs(v[i]-clear[i])<1e-3 for i in range(3)): bad+=1
if bad==len(probes):
    print('QA FAIL: 所有探针都等于 clearColor，主 pass 一个像素都没画上去'); sys.exit(1)
print('QA PASS: 至少有一处探针不是 clearColor')
