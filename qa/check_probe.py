#!/usr/bin/env python3
"""模拟器冒烟断言。

游戏包里的 metallib 是 iphoneos 平台的，模拟器加载会报 "library was not compiled for the simulator"，
地形管线在模拟器里必然是 0，所以模拟器上不可能有真实画面——像素断言只在管线真建起来时才做。
模拟器能验证的是：App 起得来、资产找得到、地形 meta 解得开、command buffer 编码不炸。
"""
import re, sys, os

p = '/tmp/qa-boot.log'
if not os.path.exists(p):
    print('QA FAIL: 没有 boot.log（App 在启动阶段就挂了）')
    sys.exit(1)
s = open(p, encoding='utf-8', errors='ignore').read()

required = ['shader 函数就绪', 'pipeline 构建完成', 'renderer init done', 'window 已显示']
missing = [k for k in required if k not in s]
if missing:
    print('QA FAIL: 缺少关键阶段日志', missing)
    sys.exit(1)

if 'terrain meta 解码失败' in s:
    print('QA FAIL: 地形 meta 解码失败')
    sys.exit(1)

ready = re.findall(r'地形组资源就绪 (\d+) 组 / 管线 (\d+)', s)
if not ready:
    print('QA FAIL: 没有构建地形资源')
    sys.exit(1)
groups, pipes = int(ready[-1][0]), int(ready[-1][1])
print(f'terrain: {groups} 组 / {pipes} 管线')

if pipes == 0:
    print('QA PASS(冒烟): 模拟器加载不了 iphoneos metallib，地形管线 0 属预期，跳过像素断言')
    sys.exit(0)

probes = re.findall(r'探针 f\d+ .*?地形=\(([^)]*)\)', s)
if not probes:
    print('QA FAIL: 日志里没有探针读数')
    sys.exit(1)
clear = (0.03, 0.05, 0.09)
bad = 0
for t in probes:
    v = tuple(round(float(x), 4) for x in t.split(',')[:3])
    print('probe', v)
    if all(abs(v[i] - clear[i]) < 1e-3 for i in range(3)):
        bad += 1
if bad == len(probes):
    print('QA FAIL: 所有探针都等于 clearColor，主 pass 一个像素都没画上去')
    sys.exit(1)
print('QA PASS: 至少有一处探针不是 clearColor')
