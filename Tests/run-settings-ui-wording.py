#!/usr/bin/env python3
"""Approved wording and retired keys, independent of layout implementation."""
from pathlib import Path
import argparse,json,subprocess,re
import xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--interfaces',type=Path);args=p.parse_args()
r=Path(__file__).resolve().parents[1];interfaces=args.interfaces or r/'Resources/Interfaces'
fixture=json.loads((r/'Tests/Fixtures/SettingsChangeNoteStrings.json').read_text())
def strings(path):return json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(path)]))
retired=[
'Not found (current setting will be kept)',
'Select a command to change its shortcut. Changes take effect immediately. Macros and text input key bindings use their own editors.',
'The newest detected installation is selected. You can choose another candidate below. Custom engine commands and the alternate path are unchanged.',
'The following macros use this shortcut. Assigning it to the menu command will make their shortcuts inactive. Their files will not be changed.\n\n%@',
'Correct this field, or restore its last saved value. Other settings are already saved.',
'Custom menu shortcuts will be removed. Existing KeyEquivalents.plist settings will be preserved.',
'Expanded','Collapsed',
'Use Command or Control with a key, or a function key (F1–F20).']
guidance=json.loads((r/'Tests/Fixtures/SettingsShortcutGuidance.json').read_text());retired+=guidance['retired']
reviewed=json.loads((r/'Tests/Fixtures/SettingsReviewedTooltips.json').read_text());retired.append(reviewed['retired_recording_key'])
terminology=json.loads((r/'Tests/Fixtures/SettingsCatalogTerminology.json').read_text())
keys=fixture['languages']['en']
for lang,expected in fixture['languages'].items():
    loc=interfaces/(lang+'.lproj');panes=interfaces/('Base.lproj' if lang=='en' else lang+'.lproj')
    actual=strings(loc/'Localizable.strings')
    search_wording=json.loads((r/'Tests/Fixtures/SettingsSearchWording.json').read_text())
    if lang in search_wording['counts']:assert actual['Settings results: %lu']==search_wording['counts'][lang],(lang,'Search counts refer to settings')
    engine=strings(panes/'SettingsCategories.strings')
    # A note may first say what the setting does; the default is always its last part.
    for key,value in [('catalog.typesetting.0.3.note','pdflatexmk'),('catalog.typesetting.8.0.note','kpsewhich -progname=latex -format=tex'),('catalog.typesetting.8.1.note','bibtex')]:assert engine[key].endswith(search_wording['prefixes'][lang]+value),(lang,'Engine defaults use consistent localized wording',key)
    assert "Changes the Dock icon only. Click OK to keep your choice." not in strings(panes/"SettingsDock.strings"),(lang,"obsolete Dock confirmation guidance")
    for (table,key),value in zip(reviewed['keys'],reviewed['languages'][lang]):assert strings(panes/(table+'.strings'))[key]==value,(lang,key)
    assert actual['New shortcut']==reviewed['languages'][lang][3],(lang,'recording label')
    category_strings=strings(panes/'SettingsCategories.strings')
    dock_contract=json.loads((r/'Tests/Fixtures/SettingsDockLabels.json').read_text())
    translated=dock_contract['languages']['Base' if lang=='en' else lang]
    for key,value in zip(dock_contract['category_keys'],translated):assert category_strings[key]==value,(lang,key)
    dock=strings(panes/'SettingsDock.strings')
    assert set(dock)==set(dock_contract['dock_keys']),(lang,'Dock key set excludes obsolete instructions')
    for key,value in zip(dock_contract['dock_keys'],translated[3:]):assert dock[key]==value,(lang,key)
    assert not any(k.startswith('catalog.appearance.10.0.') for k in category_strings),(lang,'unused Dock row keys')
    conversion=json.loads((r/'Tests/Fixtures/SettingsConversionNotes.json').read_text())
    if lang in conversion:
        for key,value in conversion[lang].items():assert category_strings[key]==value,(lang,'approved conversion explanation',key)
    for key,value in zip(terminology['keys'],terminology['languages']['Base' if lang=='en' else lang]):assert category_strings[key]==value,(lang,key)
    assert not set(retired)&actual.keys(),(lang,'retired UI keys')
    for key,value in zip(guidance['keys'],guidance['languages'][lang]):assert actual[key]==value,(lang,key)
    for n in [0,1,2,5]:assert actual[keys[n]]==expected[n],(lang,keys[n])
    assert actual['Currently open files retain their old encoding.']==fixture['legacy_encoding_warning'][lang],(lang,'legacy encoding warning')
    assert strings(panes/'SettingsSource.strings')['585.title']==expected[4],(lang,'Find title')
    assert strings(panes/'SettingsPreview.strings')['113.ibShadowedToolTip']==expected[3],(lang,'zoom tooltip')
    assert 'catalog.editor.7.0.note' not in strings(panes/'SettingsCategories.strings'),(lang,'constant restart note')
    assert not any(k.startswith('LIV-SV') for k in strings(panes/'SettingsFooter.strings')),(lang,'footer explanation')
    assert not {'F86-wI-vOl.label','L8F-o2-roK.label'} & strings(panes/'SettingsThemes.strings').keys(),(lang,'retired intermediate theme headings')
    assert not any(k.startswith('LIV-TH') for k in strings(panes/'SettingsThemes.strings')),(lang,'theme explanation')
source=(r/'Sources/Settings/TSPreferences.m').read_text();start=source.index('- (IBAction)encodingChanged:');end=source.index('\n}',start)
assert 'NSBeginCriticalAlertSheet' not in source[start:end], 'Encoding warning must be inline'
assert 'recordUserChangeForKey:EncodingKey' in source[start:end], 'Encoding action must reach the inline note manager'
index=(r/'Sources/Settings/TSSettingsSearchCatalog.inc').read_text()
assert 'catalog.editor.7.0.note' not in index and 'shortcut.hint' not in index
for text in retired:assert text.replace('\n','\\n') not in index
for text in keys[:3]:assert text not in index
print('PASS: 12 languages, approved inline notices, original encoding translations, retired UI keys and index exclusions')

row_contract=json.loads((r/'Tests/Fixtures/SettingsRowTranslations.json').read_text())
for lang,expected_rows in row_contract['rows'].items():
    actual=strings(interfaces/f'{lang}.lproj'/'SettingsCategories.strings')
    for key,value in expected_rows.items():assert actual[key]==value,(lang,'translated row name',key)

translated=json.loads((r/'Tests/Fixtures/SettingsSixthWording.json').read_text())
for lang,tables in translated.items():
    for table,expected in tables.items():
        actual=strings(interfaces/f'{lang}.lproj'/table)
        for key,value in expected.items():assert actual[key]==value,(lang,table,key,'sixth audit reviewed wording')
print('PASS: translated choices, group names and approved semantics in every language')

translated=json.loads((r/"Tests/Fixtures/SettingsSeventhWording.json").read_text())
for lang,tables in translated.items():
    for table,expected in tables.items():
        actual=strings(interfaces/f"{lang}.lproj"/table)
        for key,value in expected.items():assert actual[key]==value,(lang,table,key,"seventh audit reviewed wording")
print("PASS: seventh audit wording decisions and translated legacy choices")

translated=json.loads((r/"Tests/Fixtures/SettingsEighthWording.json").read_text())
for lang,tables in translated.items():
    for table,expected in tables.items():
        actual=strings(interfaces/f"{lang}.lproj"/table)
        for key,value in expected.items():assert actual[key]==value,(lang,table,key,"eighth audit reviewed wording")
print("PASS: personal XML mark is translated in catalog and legacy controls")

translated=json.loads((r/"Tests/Fixtures/SettingsIntegrationWording.json").read_text())
for lang,tables in translated.items():
    for table,expected in tables.items():
        actual=strings(interfaces/f"{lang}.lproj"/table)
        for key,value in expected.items():assert actual[key]==value,(lang,table,key,"integration audit reviewed wording")
print("PASS: integration audit translations and consistent local terminology")

translated=json.loads((r/"Tests/Fixtures/SettingsRowNotes.json").read_text())
for lang,tables in translated.items():
    for table,expected in tables.items():
        actual=strings(interfaces/f"{lang}.lproj"/table)
        for key,value in expected.items():assert actual[key]==value,(lang,table,key,"reviewed row explanation")
layout=(r/"Sources/Settings/TSSettingsCatalogLayout.inc").read_text()
notes=sorted(set(re.findall(r'@"note": @"(catalog\.[^"]+)"',layout)))
assert {'catalog.general.0.1.note','catalog.editor.2.2.note'}<=set(notes),'row explanations are shown'
for loc in sorted(interfaces.glob("*.lproj/SettingsCategories.strings")):
    actual=strings(loc)
    for key in notes:assert actual.get(key,"").strip(),(loc.parent.name,key,"row explanation in every language")
print("PASS: every row explanation exists in every language, including External Editor and right-to-left lines")

# A pop-up row's title names the setting, not one of its choices.
catalog=(r/"Sources/Settings/TSSettingsSearchCatalog.inc").read_text()
popups={"row."+i for i in re.findall(r'@"id": @"(catalog\.[^"]+)", @"kind": @"popup"',layout)}
entries={}
for row,table,key,weight in re.findall(r'add\(\w+, @"(row\.[^"]+)", @"(\w+)", @"([^"]+)", TSSettingsSearchWeight(Label|Choice)\)',catalog):
    if row in popups:entries.setdefault(row,{'Label':[],'Choice':[]})[weight].append((table,key))
assert 'row.catalog.typesetting.0.2' in entries and len([e for e in entries.values() if e['Label'] and e['Choice']])>=20,'pop-up rows with choices are found'
for loc in sorted(interfaces.glob("*.lproj/SettingsCategories.strings")):
    tables={}
    def text(table,key):
        if table not in tables:
            path=loc.parent/(table+'.strings');tables[table]=strings(path) if path.exists() else {}
        return tables[table].get(key)
    for row,entry in entries.items():
        choices={text(*choice) for choice in entry['Choice']}-{None}
        for label in entry['Label']:assert text(*label) not in choices,(loc.parent.name,row,text(*label),'pop-up title repeats one of its choices')
names=json.loads((r/"Tests/Fixtures/SettingsTypesettingNames.json").read_text())['languages']
assert {p.parent.stem for p in interfaces.glob("*.lproj/SettingsCategories.strings")}==set(names),'every language has reviewed Typesetting names'
for lang,expected in names.items():
    for table in ('SettingsCategories.strings','SettingsTypesetting.strings','Localizable.strings'):
        actual=strings(interfaces/f"{'en' if lang=='Base' and table=='Localizable.strings' else lang}.lproj"/table)
        for key,value in expected[table].items():assert actual[key]==value,(lang,table,key,'reviewed Typesetting name')
    note=strings(interfaces/f"{lang}.lproj/SettingsCategories.strings")['catalog.typesetting.3.2.note']
    assert note.startswith(expected['note_prefix']) and note.endswith('~/bin/context/tex/texmf-osx-arm64/bin'),(lang,'second engines note names the magic comment, then the default')
    menu=f"{lang}.lproj/MainMenu.nib/designable.nib";menu=ET.parse(interfaces/menu if (interfaces/menu).exists() else r/"Resources/Interfaces"/menu).getroot()
    titles={e.get('identifier'):e.get('title') for e in menu.iter('menuItem') if (e.get('identifier') or '').startswith('TSShortcut.doChooseMethod:.')}
    choices=expected['SettingsTypesetting.strings']
    assert titles['TSShortcut.doChooseMethod:.100']==choices['191.title'] and titles['TSShortcut.doChooseMethod:.101']==choices['187.title'],(lang,'Typeset menu and Settings name the methods alike',titles)
    categories=strings(interfaces/f"{lang}.lproj/SettingsCategories.strings")
    assert categories['group.typesetting.4.title']==choices['191.title'] and categories['group.typesetting.5.title']==choices['187.title'] and categories['group.typesetting.6.title']==strings(interfaces/f"{lang}.lproj/SettingsTypesetting.strings")['190.title'],(lang,'command groups are named after the typesetting methods')
    assert all(categories[k]==categories[k].strip() for k in categories if k.startswith('catalog.typesetting.') and k.endswith('.title')),(lang,'Typesetting row titles have no stray spaces')
assert 'NSLocalizedString(@"Not found", @"")' in (r/'Sources/Settings/TSPreferences.m').read_text(encoding='latin1'),'Auto Setup says only Not found'
order=[g for g in re.findall(r'@"id": @"(group\.typesetting\.\d+)"',layout)]
assert order.index('group.typesetting.7')==order.index('group.typesetting.5')+1,'Ghostscript follows the Via DVI commands'
print("PASS: pop-up titles differ from their choices; reviewed Typesetting names match in Settings and the Typeset menu; command groups are named after the methods and Ghostscript follows Via DVI")
