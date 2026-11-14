#!/usr/bin/env python3
# Terada: Verify preserved connections, removal of WebKit internals, and tab content bounds.
from pathlib import Path
import subprocess, sys, xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
bundle=Path(sys.argv[1]) if len(sys.argv)>1 else None
ORIGINAL_SOURCES='db040b9'  # Initial import of the original TeXShop 5.58 sources
# Preferences.nib remains only as a historical migration fixture.
# Connections of the 5.58 document window that were wrong and have been corrected
# (#42 and the localized nib audit, run-localized-nibs.py). Each entry names the exact
# connection removed and added; every other connection must stay as in 5.58.
def outlet(prop,dest,ident):return ('outlet',(('destination',dest),('id',ident),('property',prop)))
def action(sel,ident,target='-2'):return ('action',(('id',ident),('selector',sel),('target',target)))
CORRECTED={
    # #42: the editor outlet pointed to the text annotation panel, whose outlet was missing.
    'ro.lproj':([outlet('textView','RAn-kp-SNH','Jbj-v1-ByF')],
                [outlet('textView','21','Jbj-v1-ByF'),outlet('stringWindowTextView','RAn-kp-SNH','Ohb-Vr-poi')]),
    # Previous pointed to the log window's content view; the encoding pop-up of the older Save accessory changed the file type.
    'es.lproj':([outlet('previousButton','1606','qdu-yl-BAe'),action('setSaveExtension:','fqS-Vq-hgb')],
                [outlet('previousButton','393','qdu-yl-BAe')]),
    # The text annotation choices lacked the strikeout button; it was added where Base has it.
    'fr.lproj':([],[outlet('tLog','LqC-fO-238','VgR-V5-IfL'),action('strikeoutAnnotation:','Stk-Fr-a01','-1')]),
    'ko.lproj':([action('lockDocument:','NLs-gZ-1iV')],[action('gotoURL:','NLs-gZ-1iV')]),
    'pt-PT.lproj':([action('convertTiff:','yKe-Uz-9qP')],
                   [action('doTag:','yKe-Uz-9qP'),outlet('showFullPathButton','3921','Bcb-fn-oGM'),outlet('slabels','OUv-dr-rDM','bJm-TP-SIA')]),
    # The split window's AutoComplete and Color Index buttons were added with their connections.
    'zh_CN.lproj':([action('lockDocument:','LJq-e2-BPE')],
                   [action('gotoURL:','LJq-e2-BPE'),outlet('autoCompleteSplitButton','oCL-rZ-3aW','2wM-qZ-cUD'),
                    outlet('indexColorSplitBox','Ih7-yf-Js1','o3g-yr-DO1'),action('changeAutoComplete:','9Wv-gf-ygw'),action('showIndexColor:','ecQ-oX-sf2')]),
}
for kind in ('TSDocument',):
    for path in sorted((root/'Resources/Interfaces').glob(f'*/{kind}.nib/designable.nib')):
        relative=path.relative_to(root)
        current=ET.parse(path).getroot()
        def connections(r):
            result=[]
            for e in r.findall('.//connections/*'):
                attrs=dict(e.attrib)
                if kind=='TSDocument' and attrs.get('property')=='htmlView': attrs['property']='htmlViewContainer'
                result.append((e.tag,tuple(sorted(attrs.items()))))
            return sorted(result)
        if kind=='TSDocument':
            # The document window keeps the connections of the original 5.58 sources. The Settings
            # window has gained controls since; run-preferences-wiring.py checks its connections.
            original=ET.fromstring(subprocess.check_output(['git','show',f'{ORIGINAL_SOURCES}:{relative}'],cwd=root))
            expected=connections(original)
            removed,added=CORRECTED.get(path.parent.parent.name,([],[]))
            for item in removed:
                assert item in expected,(path,'corrected connection is not in 5.58',item)
                expected.remove(item)
            assert not set(added)&set(expected),(path,'added connection was already in 5.58')
            expected=sorted(expected+added)
            assert expected==connections(current),path
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

subprocess.run([sys.executable,str(root/"Tests/run-settings-panes.py"),*(["--app",str(bundle)] if bundle else [])],check=True)
