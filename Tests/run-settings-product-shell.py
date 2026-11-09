#!/usr/bin/env python3
"""Compile the complete production Settings owner; all windows stay unordered."""
from pathlib import Path
import argparse,subprocess,tempfile,shutil,re
from pane_fixtures import bundles,sources
from shortcut_sources import NAMES
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('output',nargs='?',type=Path);p.add_argument('--app',type=Path);p.add_argument('--language');p.add_argument('--mutations',action='store_true');a=p.parse_args()
with tempfile.TemporaryDirectory(prefix='texshop-product-shell-') as temp:
 t=Path(temp);(t/'fixtures').mkdir()
 compile=['xcrun','clang','-fobjc-arc','-DTS_TEST_REAL_SHORTCUTS','-DTS_TEST_REAL_PROFILE','-DNSBeginCriticalAlertSheet=TSTestUnexpectedCriticalSheet','-F',str(r),'-Wno-deprecated-declarations','-mmacosx-version-min=14.6','-I',str(r/'Sources'),'-I',str(r/'Tests'),'-framework','Cocoa','-framework','Carbon',str(r/'Tests/SettingsProductShell.m'),str(r/'Tests/PreferencesTestServices.m'),*map(str,sources(r)),str(r/'Sources/TSPreferences+Panes.m'),*[str(r/'Sources'/n) for n in ['TSPreferences.m','TSPreferenceProfile.m','TSPreferences-Color.m','TSColorSupport.m','TSThemeFileStore.m','TSPreferenceInput.m','globals.m','TSDockIconController.m',*NAMES]],*map(str,sorted((r/'Sources').glob('TSSettings*.m'))),'-o',str(t/'probe')]
 def build(replacement=None):
  subprocess.run([str(replacement) if replacement and x==str(r/'Sources/TSPreferences.m') else x for x in compile],check=True)
 build()
 shell=t/'SettingsWindow.nib'
 if a.app:shutil.copy2(a.app/'Contents/Resources/SettingsWindow.nib',shell)
 else:subprocess.run(['xcrun','ibtool','--compile',str(shell),str(r/'Resources/SettingsWindow.xib')],check=True)
 for bundle in bundles(r,t/'fixtures',product=a.app,dock=True):
  if a.language and bundle.stem!=a.language:continue
  shutil.copy2(r/'Resources/FactoryDefaults.plist',bundle/'Contents/Resources/FactoryDefaults.plist')
  shutil.copy2(r/'Tests/Fixtures/SettingsDependencies.json',bundle/'Contents/Resources/SettingsDependencies.json')
  for themeName in ['LiteTheme','DarkTheme']:
   shutil.copy2(r/('Resources/TeXShop/Themes/'+themeName+'.plist'),bundle/('Contents/Resources/'+themeName+'.plist'))
  profiles=bundle/'Contents/Resources/Profiles';profiles.mkdir()
  for profile in sorted((r/'Resources/Shellscripts').glob('*Defaults*.plist')):shutil.copy2(profile,profiles/profile.name)
  shutil.copy2(shell,bundle/'Contents/Resources/SettingsWindow.nib')
  command=[str(t/'probe'),str(bundle)]
  if a.output:folder=a.output/bundle.stem;folder.mkdir(parents=True,exist_ok=True);command.append(str(folder))
  print('LANGUAGE',bundle.stem,flush=True);subprocess.run(command,check=True,timeout=120)

  if a.mutations:
   original=(r/'Sources/TSPreferences.m').read_text()
   cases=[('profile-transient-clear','TSPreferences.m','[self.settingsChangeNotes valuesReplaced];',';'),('encoding-sheet','TSPreferences.m','[self.settingsChangeNotes recordUserChangeForKey:EncodingKey previousValue:oldValue ?: @""];','NSBeginCriticalAlertSheet(@"Encoding",nil,nil,nil,nil,nil,NULL,NULL,NULL,@"Warning");'),
    ('dictionary-stale-entry','TSSettingsPaneRefresh.inc','[dictionaryPopup removeAllItems];',';'),
    ('dictionary-localization','TSSettingsPaneRefresh.inc','NSLocalizedString(@"Automatic Language", @"")','@"Automatic Language"'),
    ('cross-category-refresh','TSSettingsPaneRefresh.inc','if ([identifier isEqual:TSSettingsCategoryGeneral]) { [self refreshGeneralSettingsFromDefaults:defaults]; return; }','if ([identifier isEqual:TSSettingsCategoryGeneral]) { [self refreshGeneralSettingsFromDefaults:defaults]; [self refreshDocumentsSettingsFromDefaults:defaults]; return; }'),
    ('detached-radio-state','TSSettingsPaneRefresh.inc','useTwoWindowsButton.state = ![defaults boolForKey:SourceAndPreviewInSameWindowKey];',';'),
   ]
   for outlet in ['docWindowPosButton','pdfWindowPosButton','consoleWindowPosButton','htmlWindowPosButton','sparkleIntervalMatrix','engineTextField']:
    cases.append(('dependency-'+outlet,'TSSettingsPaneRefresh.inc','[_'+outlet+' setEnabled: NO];','[_'+outlet+' setEnabled: YES];') if outlet not in ['sparkleIntervalMatrix'] else ('dependency-'+outlet,'TSSettingsPaneRefresh.inc','[_sparkleIntervalMatrix setEnabled: [defaults boolForKey: SparkleAutomaticUpdateKey]];','[_sparkleIntervalMatrix setEnabled:YES];'))
   for name,filename,old,new in cases:
    source=(r/'Sources'/filename).read_text();pattern=r'\s*'.join(re.escape(token) for token in re.findall(r'\w+|[^\s]',old));assert len(re.findall(pattern,source))==1,(name,len(re.findall(pattern,source)));mutated=re.sub(pattern,lambda match:new,source)
    changed=t/'TSPreferences.m';changed.write_text(mutated if filename=='TSPreferences.m' else original)
    header=t/'TSSettingsPaneRefresh.inc';header.write_text(mutated if filename=='TSSettingsPaneRefresh.inc' else (r/'Sources/TSSettingsPaneRefresh.inc').read_text())
    build(changed)
    result=subprocess.run([str(t/'probe'),str(bundle)],capture_output=True,text=True,timeout=120)
    assert result.returncode and 'FAIL:' in result.stderr,(name,result.stdout,result.stderr)
    print('DETECTED',name,result.stderr.strip(),flush=True)
   build();subprocess.run([str(t/'probe'),str(bundle)],check=True,timeout=120);print('NORMAL CONTROL',bundle.stem,flush=True)
