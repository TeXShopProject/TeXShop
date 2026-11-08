"""Build isolated bundles from shared settings nibs and their real translations."""
from pathlib import Path
import plistlib, shutil, subprocess

NAMES = ('Source','Editor','Preview','Console','Typesetting','Engines','MiscOne','MiscTwo','Themes','Footer','ThemeName')

def sources(root, names=NAMES):
    return [root/'Sources'/('TSPref'+n+'Controller.m') for n in (*names,'Pane')] + [root/'Sources/TSPrefPaneLayout.m']

def bundles(root, temp, names=NAMES, product=None, dock=False):
    compiled=temp/'compiled';compiled.mkdir()
    for name in names:
        target=compiled/('Settings'+name+'.nib')
        if product:
            src=product/'Contents/Resources/Base.lproj'/target.name
            if src.is_dir():shutil.copytree(src,target)
            else:shutil.copy2(src,target)
        else:
            subprocess.run(['xcrun','ibtool','--compile',str(target),str(root/'Resources/Interfaces/Base.lproj'/('Settings'+name+'.xib'))],check=True)
    result=[]
    for loc in sorted((root/'Resources/Interfaces').glob('*.lproj')):
        if not (loc/'SettingsCategories.strings').exists():continue
        language=loc.stem;bundle=temp/(language+'.bundle');resources=bundle/'Contents/Resources';resources.mkdir(parents=True)
        shutil.copytree(compiled,resources/'Base.lproj')
        (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.texshop.tests.panes','CFBundlePackageType':'BNDL','CFBundleDevelopmentRegion':language if language!='Base' else 'en','CFBundleLocalizations':[language if language!='Base' else 'en']}))
        destination=resources/loc.name;destination.mkdir(exist_ok=True)
        for name in [*('Settings'+n for n in names),'SettingsCategories','SettingsDock']:
            src=(product/'Contents/Resources'/loc.name if product else loc)/(name+'.strings')
            if src.exists():shutil.copy2(src,destination/src.name)
        localization = 'en.lproj' if language == 'Base' else loc.name
        localized = resources/localization; localized.mkdir(exist_ok=True)
        original = (product/'Contents/Resources'/localization if product else root/'Resources/Interfaces'/localization)/'Localizable.strings'
        if original.exists():shutil.copy2(original,localized/original.name)
        if dock:
            artwork=product/'Contents/Resources/DockIcons' if product else root/'Resources/DockIcons'
            (resources/'DockIcons').symlink_to(artwork,target_is_directory=True)
        result.append(bundle)
    assert len(result)==12
    return result
