#!/usr/bin/env python3
"""Check reviewed sixth-audit wording contracts by reverting isolated resources."""
from pathlib import Path
import json,os,shutil,subprocess,tempfile,sys
R=Path(__file__).resolve().parents[1]
expected=json.loads((R/'Tests/Fixtures/SettingsSixthWording.json').read_text())
with tempfile.TemporaryDirectory(prefix='texshop-sixth-wording-') as td:
    T=Path(td)
    for directory in ['Resources/Interfaces','Tests/Fixtures','Documentation/Releases','website','DocumentSources/Manual Source','DocumentSources/CommentLinesRevised','DocumentSources/ChangesDocument']:
        for source in (R/directory).rglob('*'):
            if source.is_file() and source.suffix in ['.strings','.htm','.html','.json','.md','.tex','.pdf','.cshelpindex']:
                dest=T/source.relative_to(R);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
    for name in ['Sources/Settings/TSSettingsCategory.m','Sources/Settings/TSSettingsCategoryList.m']:
        dest=T/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/name,dest)
    def wording():
        return subprocess.run(['python3',str(R/'Tests/run-settings-ui-wording.py'),'--interfaces',str(T/'Resources/Interfaces')],capture_output=True,text=True)
    checker=(R/'Tests/check-settings-guidance.py').read_text().replace('ROOT = Path(__file__).resolve().parents[1]','ROOT = Path('+repr(str(T))+')')
    def guidance():
        # The mutations are of the other books; the books still in translation are check-settings-guidance.py's own concern.
        return subprocess.run(['python3','-c',checker],capture_output=True,text=True,env=dict(os.environ,TEXSHOP_HELP_TRANSLATIONS_PENDING='1'))
    for run in [wording,guidance]:
        result=run();assert result.returncode==0,result.stderr
    for lang,tables in ({} if "--guidance-only" in sys.argv else expected).items():
        for table,entries in tables.items():
            path=T/'Resources/Interfaces'/f'{lang}.lproj'/table;original=path.read_bytes()
            values=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(path)]))
            key=next(iter(entries));values[key]='UNREVIEWED WORDING'
            path.write_text('\n'.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';' for k,v in values.items())+'\n')
            result=wording();path.write_bytes(original)
            assert result.returncode and ('sixth audit reviewed wording' in result.stderr or 'translated row name' in result.stderr),(lang,table,result.stderr)
            print('DETECTED reviewed choice/group translation',lang,table,flush=True)
    cases=[
        ('DocumentSources/Manual Source/Manual.tex',b'slider and a numeric field',b'slider and a label'),
        ('Documentation/Releases/6.00.md',b'typed as a number',b'typed as a label'),
        ('website/release-notes.html',b'typed as a number',b'typed as a label'),
        ('Documentation/Releases/6.00-ja.md','数値欄'.encode(),b'LABEL'),
        ('website/release-notes-ja.html','数値欄'.encode(),b'LABEL'),
    ]
    for lang in ['en','ja','de','es','ko']:
        path=f'Resources/Interfaces/{lang}.lproj/TeXShopHelp/pgs/basic_preferences.htm'
        cases.append((path,{'en':b'numeric field','ja':'数値欄'.encode(),'de':b'Zahlenfeld','es':b'campo num','ko':'숫자 입력 필드'.encode()}[lang],b'REMOVED'))
    # Reverting the new commit semantics must fail independently of field presence.
    # Release notes and the manual keep only the number field; the commit rule is documented in the help.
    for lang,old,encoding in [('en','typed and pasted','utf-8'),('ja','打鍵と貼り付け','utf-8'),('de','getippten und eingefügten','utf-8'),('es','escrito y el pegado','utf-8')]:
        cases.append((f'Resources/Interfaces/{lang}.lproj/TeXShopHelp/pgs/basic_preferences.htm',old.encode(encoding),b'CHANGED'))
    cases.append(('Resources/Interfaces/ko.lproj/TeXShopHelp/pgs/basic_preferences.htm','직접 입력한'.encode(),b'CHANGED'))
    for path,old,new in cases:
        p=T/path;original=p.read_bytes();assert old in original,path
        updated=original.replace(old,new)
        p.write_bytes(updated);result=guidance();p.write_bytes(original)
        assert result.returncode and ('numeric' in result.stderr.lower() or 'opacity' in result.stderr.lower()),(path,result.stderr)
        print('DETECTED numeric opacity guidance',path,flush=True)
    for run in [wording,guidance]:
        result=run();assert result.returncode==0,result.stderr
    print('NORMAL CONTROL sixth wording and opacity guidance')
