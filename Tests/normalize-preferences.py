#!/usr/bin/env python3
# Terada: 接続とグループ内の相対位置を維持して、各タブを上端に揃える。
from pathlib import Path
import re
import xml.etree.ElementTree as ET

for path in sorted(Path('Resources/Interfaces').glob('*/Preferences.nib/designable.nib')):
    source = path.read_text()
    root = ET.fromstring(source)
    original = {e.get('id'): ET.tostring(e.find('rect')).decode() for e in root.iter() if e.get('id') and e.find('rect') is not None}
    def frame(e):
        return e.find('rect')
    def number(e, k):
        return float(frame(e).get(k, '0'))
    def setrect(e, **kw):
        for k,v in kw.items(): frame(e).set(k, f'{v:g}')
    def children(v):
        return [e for e in v.findall('./subviews/*') if frame(e) is not None]
    def align(v, height, width):
        items = children(v)
        top = max(number(e,'y')+number(e,'height') for e in items)
        left = min(number(e,'x') for e in items)
        for e in items:
            setrect(e, y=number(e,'y')+height-12-top, x=number(e,'x')+max(0, 12-left))
        setrect(v, width=width,height=height)
    # 括弧のチェック欄は標準のコントロール幅を確保する。
    for v in root.findall('.//view'):
        buttons=[c for c in children(v) if c.tag=='button' and c.find('buttonCell') is not None and c.find('buttonCell').get('title') in ['{ }','[ ]','( )','< >']]
        if len(buttons)==4:
            buttons.sort(key=lambda c:number(c,'x'))
            for i,c in enumerate(buttons): setrect(c,x=12+i*55,y=12,width=53,height=22)
    tabs = next(t for t in root.findall('.//tabView') if len(t.findall('./tabViewItems/tabViewItem')) == 9)
    assert tabs is not None
    for nested in tabs.findall('.//tabView'):
        views = nested.findall('./tabViewItems/tabViewItem/view')
        height=max(max(number(c,'y')+number(c,'height') for c in children(v))-min(number(c,'y') for c in children(v)) for v in views)+24
        width=max(max(number(c,'x')+number(c,'width') for c in children(v))+max(0,12-min(number(c,'x') for c in children(v))) for v in views)+12
        for v in views: align(v,height,width)
        setrect(nested,height=height+46,width=width+20)
    views=tabs.findall('./tabViewItems/tabViewItem/view')
    height=max(max(number(c,'y')+number(c,'height') for c in children(v))-min(number(c,'y') for c in children(v)) for v in views)+24
    width=max(max(number(c,'x')+number(c,'width') for c in children(v))+max(0,12-min(number(c,'x') for c in children(v))) for v in views)+12
    width=max(width,max(number(v,'width') for v in views))
    for v in views: align(v,height,width)
    setrect(tabs,x=12,y=60,width=width+20,height=height+46)
    window=next(w for w in root.findall('.//window') if tabs in list(w.iter())); content=window.find('./view[@key="contentView"]')
    oldwidth=number(content,'width'); newwidth=width+44; newheight=height+118
    for e in children(content):
        if e is not tabs and number(e,'x')>oldwidth/2: setrect(e,x=number(e,'x')+newwidth-oldwidth)
    setrect(content,width=newwidth,height=newheight)
    setrect(window,width=newwidth,height=newheight)
    for e in root.iter():
        ident=e.get('id')
        if ident not in original: continue
        new=ET.tostring(e.find('rect')).decode()
        if new==original[ident]: continue
        pattern=r'(<[^>]+\bid="'+re.escape(ident)+r'"[^>]*>(?:(?!<rect).)*?)<rect\b[^>]*/>'
        rect=ET.tostring(e.find('rect'),encoding='unicode').strip()
        source,n=re.subn(pattern,lambda m:m[1]+rect,source,count=1,flags=re.S)
        assert n==1,ident
    path.write_text(source)
    print(path.parent.parent.name, f'{newwidth:g} x {newheight:g}')
