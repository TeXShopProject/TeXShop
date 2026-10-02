#!/usr/bin/env python3
# Terada: 原本から接続を失わず、WebKit内部クラスとタブの領域外配置を除去したことを検証。
from pathlib import Path
import subprocess, sys, xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
bundle=Path(sys.argv[1]) if len(sys.argv)>1 else None
for kind in ('Preferences','TSDocument'):
    for path in sorted((root/'Resources/Interfaces').glob(f'*/{kind}.nib/designable.nib')):
        relative=path.relative_to(root)
        original=ET.fromstring(subprocess.check_output(['git','show',f'a1c197b:{relative}'],cwd=root))
        current=ET.parse(path).getroot()
        def connections(r):
            result=[]
            for e in r.findall('.//connections/*'):
                attrs=dict(e.attrib)
                if kind=='TSDocument' and attrs.get('property')=='htmlView': attrs['property']='htmlViewContainer'
                result.append((e.tag,tuple(sorted(attrs.items()))))
            return sorted(result)
        assert connections(original)==connections(current),path
        if kind=='TSDocument':
            outlet=current.find('.//outlet[@property="htmlViewContainer"]')
            assert outlet is not None,path
            assert current.find(f'.//customView[@id="{outlet.get("destination")}"]') is not None,path
            assert current.find('.//wkWebView') is None,path
            binaries=list(path.parent.glob('keyedobjects*.nib'))
            if bundle:
                bn=bundle/'Contents/Resources'/path.parent.parent.name/f'{kind}.nib'
                if not bn.exists() and path.parent.parent.name=='Base.lproj': bn=bundle/'Contents/Resources/en.lproj'/f'{kind}.nib'
                assert bn.exists(),bn
                binaries+=list(bn.glob('keyedobjects*.nib')) if bn.is_dir() else [bn]
            for binary in binaries:
                data=binary.read_bytes()
                assert b'WKColorExtensionView' not in data and b'WKWebView' not in data,binary
                assert b'htmlViewContainer' in data,binary
        else:
            for view in current.findall('.//tabViewItem/view'):
                frame=view.find('rect');w=float(frame.get('width'));h=float(frame.get('height'))
                tops=[]
                for child in view.findall('./subviews/*'):
                    f=child.find('rect')
                    if f is None:continue
                    x,y,cw,ch=(float(f.get(k,'0')) for k in ('x','y','width','height'))
                    assert x>=0 and y>=0 and x+cw<=w+.01 and y+ch<=h+.01,(path,child.get('id'),f.attrib,w,h)
                    tops.append(y+ch)
                assert abs(h-max(tops)-12)<.01,(path,view.get('id'))
            assert not any('name' in f.attrib for f in current.findall('.//font')),path
        print(path.parent.parent.name,kind,'OK')
