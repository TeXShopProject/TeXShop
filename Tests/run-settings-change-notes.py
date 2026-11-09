#!/usr/bin/env python3
"""Hidden, memory-only lifecycle checks for production change notes."""
from pathlib import Path
import argparse, subprocess, tempfile, shutil, plistlib
p=argparse.ArgumentParser();p.add_argument('--mutations',action='store_true');p.add_argument('--all-languages',action='store_true');args=p.parse_args()
r=Path(__file__).resolve().parents[1]
expected_failures={'find-always-restart': 'Panel and bar changes take effect without restart', 'find-ignore-launch': 'Leaving OgreKit for the standard panel needs restart', 'warning-red': 'Warning uses label text and an untinted multicolor symbol', 'announcement-priority': 'Showing a note requests a medium-priority VoiceOver announcement', 'category-clear': 'Category transition clears transient note', 'close-clear': 'Closing hides all notes', 'always-condition': 'No preview means no zoom note', 'ignore-original': 'Returning to session value clears spell note', 'same-value': 'Committing the same zoom does not show a note', 'restart-category': 'Restart notes survive reopening', 'launch-overwritten': 'Launch baseline is captured only once'}
with tempfile.TemporaryDirectory(prefix='texshop-change-notes-') as directory:
    d=Path(directory);bundle=d/'Strings.bundle';resources=bundle/'Contents/Resources';resources.mkdir(parents=True)
    (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.texshop.tests.change-notes','CFBundlePackageType':'BNDL','CFBundleDevelopmentRegion':'en','CFBundleLocalizations':['en']}))
    shutil.copytree(r/'Resources/Interfaces/Base.lproj',resources/'Base.lproj',ignore=shutil.ignore_patterns('*.xib'))
    shutil.copytree(r/'Resources/Interfaces/en.lproj',resources/'en.lproj',ignore=shutil.ignore_patterns('*.nib','TeXShopHelp','*.pdf'))
    original=r/'Sources/TSSettingsChangeNote.m'
    command=['xcrun','clang','-fobjc-arc','-DNSAccessibilityPostNotificationWithUserInfo=TSProbeAnnouncement','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-mmacosx-version-min=14.6','-I',str(r/'Sources'),'-I',str(r/'Tests'),'-framework','Cocoa',str(r/'Tests/SettingsChangeNotes.m'),str(original),str(r/'Sources/TSSettingsSearch.m'),str(r/'Sources/TSSettingsCategory.m'),'-o',str(d/'probe')]
    def run(source=None, strings=bundle):
        subprocess.run([str(source) if x==str(original) and source else x for x in command],check=True)
        return subprocess.run([str(d/'probe'),str(strings)],capture_output=True,text=True,timeout=60)
    result=run();print(result.stderr,result.stdout,flush=True);assert result.returncode==0
    if args.mutations:
        mutations=[
            ('find-always-restart','return [weakSelf.launch[@"FindMethod"] integerValue] == 2 || [weakSelf.defaults integerForKey:@"FindMethod"] == 2;','return YES;'),
            ('find-ignore-launch','return [weakSelf.launch[@"FindMethod"] integerValue] == 2 || [weakSelf.defaults integerForKey:@"FindMethod"] == 2;','return [weakSelf.defaults integerForKey:@"FindMethod"] == 2;'),
            ('warning-red','label.textColor = NSColor.labelColor;','label.textColor = NSColor.systemRedColor;'),
            ('announcement-priority','@(NSAccessibilityPriorityMedium)','@(NSAccessibilityPriorityLow)'),
            ('category-clear','if(!rule.restart)[rule.view setShown:NO announce:NO];','if(NO)[rule.view setShown:NO announce:NO];'),
            ('close-clear','[rule.view setShown:NO announce:NO]; }','[rule.view setShown:YES announce:NO]; }'),
            ('always-condition','![current isEqual:original] && rule.condition();','![current isEqual:original] && YES;'),
            ('ignore-original','![current isEqual:original] && rule.condition()','YES && rule.condition()'),
            ('same-value','if([current isEqual:value])return;','if(NO)return;'),
            ('restart-category','[self refreshRestartNotes];',';'),
            ('launch-overwritten','if (launchValues[key] == nil) launchValues[key] = [value copy];','launchValues[key] = [value copy];'),
        ]
        text=original.read_text()
        for name,old,new in mutations:
            assert text.count(old)==1,(name,text.count(old))
            changed=d/'TSSettingsChangeNote.m';changed.write_text(text.replace(old,new));result=run(changed)
            assert result.returncode and 'FAIL: '+expected_failures[name] in result.stderr,(name,result.returncode,result.stderr)
            print('DETECTED',name,result.stderr.strip(),flush=True)
        result=run();assert result.returncode==0;print('NORMAL CONTROL',result.stdout,flush=True)

    if args.all_languages:
        for loc in sorted((r/'Resources/Interfaces').glob('*.lproj')):
            if not (loc/'SettingsCategories.strings').exists():continue
            language='en' if loc.stem=='Base' else loc.stem
            localized=d/(language+'.bundle');res=localized/'Contents/Resources';res.mkdir(parents=True)
            (localized/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.texshop.tests.change-notes.'+language,'CFBundlePackageType':'BNDL','CFBundleDevelopmentRegion':language,'CFBundleLocalizations':[language]}))
            target=res/(language+'.lproj');target.mkdir()
            for path in loc.glob('Settings*.strings'):shutil.copy2(path,target/path.name)
            shutil.copy2(r/('Resources/Interfaces/'+language+'.lproj/Localizable.strings'),target/'Localizable.strings')
            result=run(strings=localized);assert result.returncode==0,(language,result.stderr);print(language,result.stdout,flush=True)
