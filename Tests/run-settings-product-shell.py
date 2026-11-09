#!/usr/bin/env python3
"""Compile the complete production Settings owner; all windows stay unordered."""
from pathlib import Path
import argparse,subprocess,tempfile,shutil,re
from pane_fixtures import bundles,sources
from shortcut_sources import NAMES
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('output',nargs='?',type=Path);p.add_argument('--app',type=Path);p.add_argument('--language');p.add_argument('--mutations',action='store_true');p.add_argument('--additional-mutations',action='store_true');p.add_argument('--mutation-start');a=p.parse_args()
with tempfile.TemporaryDirectory(prefix='texshop-product-shell-') as temp:
 t=Path(temp);(t/'fixtures').mkdir()
 compile=['xcrun','clang','-fobjc-arc','-DTS_TEST_REAL_SHORTCUTS','-DTS_TEST_REAL_PROFILE','-DNSBeginCriticalAlertSheet=TSTestUnexpectedCriticalSheet','-F',str(r),'-Wno-deprecated-declarations','-mmacosx-version-min=14.6','-I',str(r/'Sources'),'-I',str(r/'Tests'),'-framework','Cocoa','-framework','Carbon',str(r/'Tests/SettingsProductShell.m'),str(r/'Tests/PreferencesTestServices.m'),*map(str,sources(r)),str(r/'Sources/TSPreferences+Panes.m'),*[str(r/'Sources'/n) for n in ['TSPreferences.m','TSPreferenceProfile.m','TSPreferences-Color.m','TSColorSupport.m','TSThemeFileStore.m','TSPreferenceInput.m','globals.m','TSDockIconController.m',*NAMES]],*map(str,sorted((r/'Sources').glob('TSSettings*.m'))),'-o',str(t/'probe')]
 def build(replacements=None):
  replacements=replacements or {}
  subprocess.run([str(replacements.get(x,x)) for x in compile],check=True)
 build()
 shell=t/'SettingsWindow.nib'
 if a.app:shutil.copy2(a.app/'Contents/Resources/SettingsWindow.nib',shell)
 else:subprocess.run(['xcrun','ibtool','--compile',str(shell),str(r/'Resources/SettingsWindow.xib')],check=True)
 for bundle in bundles(r,t/'fixtures',product=a.app,dock=True):
  if a.language and bundle.stem!=a.language:continue
  shutil.copy2(r/'Resources/FactoryDefaults.plist',bundle/'Contents/Resources/FactoryDefaults.plist')
  shutil.copy2(r/'Tests/Fixtures/SettingsDependencies.json',bundle/'Contents/Resources/SettingsDependencies.json')
  shutil.copy2(r/'Tests/Fixtures/SettingsCatalogReference.json',bundle/'Contents/Resources/SettingsCatalogReference.json')
  shutil.copy2(r/'Tests/Fixtures/SettingsInputRules.json',bundle/'Contents/Resources/SettingsInputRules.json')
  shutil.copy2(r/'Tests/Fixtures/SettingsHeightReference.json',bundle/'Contents/Resources/SettingsHeightReference.json')
  for themeName in ['LiteTheme','DarkTheme']:
   shutil.copy2(r/('Resources/TeXShop/Themes/'+themeName+'.plist'),bundle/('Contents/Resources/'+themeName+'.plist'))
  profiles=bundle/'Contents/Resources/Profiles';profiles.mkdir()
  for profile in sorted((r/'Resources/Shellscripts').glob('*Defaults*.plist')):shutil.copy2(profile,profiles/profile.name)
  shutil.copy2(shell,bundle/'Contents/Resources/SettingsWindow.nib')
  command=[str(t/'probe'),str(bundle)]
  if a.output:folder=a.output/bundle.stem;folder.mkdir(parents=True,exist_ok=True);command.append(str(folder))
  print('LANGUAGE',bundle.stem,flush=True);subprocess.run(command,check=True,timeout=120)

  if a.mutations or a.additional_mutations:
   cases=[
    ('profile-transient-clear','TSPreferences.m','[self.settingsChangeNotes valuesReplaced];',';'),
    ('encoding-sheet','TSPreferences.m','[self.settingsChangeNotes recordUserChangeForKey:EncodingKey previousValue:oldValue ?: @""];','NSBeginCriticalAlertSheet(@"Encoding",nil,nil,nil,nil,nil,NULL,NULL,NULL,@"Warning");'),
    ('dictionary-stale-entry','TSSettingsPaneRefresh.inc','[dictionaryPopup removeAllItems];',';'),
    ('dictionary-localization','TSSettingsPaneRefresh.inc','NSLocalizedString(@"Automatic Language", @"")','@"Automatic Language"'),
    ('detached-radio-state','TSSettingsPaneRefresh.inc','useTwoWindowsButton.state = ![defaults boolForKey:SourceAndPreviewInSameWindowKey];',';'),
    ('profile-theme-order','TSPreferences.m','if (preparations & TSPreferencePrepareTheme) [[TSColorSupport sharedInstance] initializeColors];\n    TSPostPreferenceNotifications(changed, self);','TSPostPreferenceNotifications(changed, self);\n    if (preparations & TSPreferencePrepareTheme) [[TSColorSupport sharedInstance] initializeColors];'),
    ('profile-dock','TSPreferences.m','if (preparations & TSPreferencePrepareDock) [[TSDockIconController sharedController] restoreSavedIcon];',';'),
    ('close-validation','TSPreferences.m','return window != _prefsWindow || [self finishPreferenceEditing:YES];','return YES;'),
    ('focus-treated-as-edit','TSPreferenceInput.m','if (self.editedField != field) return YES;','if (self.editedField != field && field.currentEditor == nil) return YES;'),
    ('shared-restore-value','TSPreferenceInput.m','NSString *original = [rule displayStringFromDefaults:defaults];','NSString *original = @"20";'),
    ('disabled-label-color','TSPrefPaneLayout.m','NSColor.disabledControlTextColor','NSColor.labelColor'),
    ('switch-to-checkbox','TSSettingsPaneClassification.inc','[TSPrefPaneLayout switchForButton:source]','source'),
    ('spelling-checkbox','TSSettingsPaneClassification.inc','button.cell=radio.cell;','[button setButtonType:NSButtonTypeRadio];'),
    ('keyboard-card','TSShortcutPaneController.m','[TSPrefPaneLayout decorateGroupsInView:group];',';'),
   ]
   dependency_rules=[('DocumentWindowPosModeKey, 0','DocumentWindowPosModeKey, 1'),('PdfWindowPosModeKey, 0','PdfWindowPosModeKey, 1'),('ConsoleWindowPosModeKey, 0','ConsoleWindowPosModeKey, 1'),('HtmlWindowPosModeKey, 0','HtmlWindowPosModeKey, 1'),('SparkleAutomaticUpdateKey, 1','SparkleAutomaticUpdateKey, 0'),('DefaultCommandKey, 2','DefaultCommandKey, 1')]
   for old,new in dependency_rules:cases.append(('dependency-'+old.split(',')[0],'TSSettingsDependencies.inc',old,new))
   if a.additional_mutations:cases=[]
   cases.extend([
    ('legacy-spelling-note','TSPreferences.m','[self.settingsChangeNotes recordUserChangeForKey:TSTeXAwareSpellCheckingKey previousValue:previousNoteValue];\n}\n\n- (IBAction)editSpellingExclusions:', ';\n}\n\n- (IBAction)editSpellingExclusions:'),
    ('input-range','TSPreferences.m','minimum:2 maximum:50 allowsEmpty:NO','minimum:2 maximum:51 allowsEmpty:NO'),
    ('profile-validation','TSPreferences.m','- (IBAction)setDefaults:(NSMenuItem *)sender\n{\n    if (![self finishPreferenceEditing:YES]) return;','- (IBAction)setDefaults:(NSMenuItem *)sender\n{'),
    ('history-bound','TSSettingsNavigationHistory.m','self.entries.count > 50','self.entries.count > 51'),
    ('history-inactive-key','TSSettingsWindowController.m','if (controller != nil && self.isKeyWindow && self.attachedSheet == nil)', 'if (controller != nil && self.attachedSheet == nil)'),
    ('sidebar-wrap','TSSettingsSidebarRow.m','label.maximumNumberOfLines = 2;','label.maximumNumberOfLines = 1;'),
    ('wrap-note','TSSettingsCatalogLayout.inc','@"id": @"catalog.editor.0.5", @"kind": @"popup", @"title": @"catalog.editor.0.5.title", @"note": @"catalog.editor.0.1.note"','@"id": @"catalog.editor.0.5", @"kind": @"popup", @"title": @"catalog.editor.0.5.title", @"note": @""'),
    ('line-highlight-note','TSSettingsCatalogLayout.inc','@"id": @"catalog.editor.0.4", @"kind": @"switch", @"title": @"catalog.editor.0.4.title", @"note": @"catalog.editor.0.1.note"','@"id": @"catalog.editor.0.4", @"kind": @"switch", @"title": @"catalog.editor.0.4.title", @"note": @""'),
   ])
   for name in ['Chapter','Section','Subsection','Subsubsection','Introduction','Conclusion','Exercises','Project','Figure','Table','Mark']:
    text=(r/'Sources/TSPreferences.m').read_text();start=text.index('- (IBAction)XML'+name+'ButtonChanged:');end=text.index('\n}',start)+2
    original=text[start:end];changed=original.replace('[(TSAppDelegate *)NSApp.delegate updateXMLTabs];',';');assert changed!=original
    cases.append(('XML-'+name,'TSPreferences.m',original,changed))
   for key,enabled in [('showSpaceCharacterKey',1),('showFullwidthSpaceCharacterKey',1),('showNewLineCharacterKey',1),('showTabCharacterKey',1),('TSTeXAwareSpellCheckingKey',1)]:
    cases.append(('dependency-'+key,'TSSettingsDependencies.inc',key+', '+str(enabled)+',',key+', '+str(1-enabled)+','))
   cases.extend([
    ('profile-copy-menu','TSPreferences.m','if (preparations & TSPreferencePreparePDFCopy) [(TSAppDelegate *)NSApp.delegate syncImageCopyTypeMenu];',';'),
    ('termination-validation','TSPreferences.m','[self finishPreferenceEditing:NO];',';'),
    ('font-ending-guard','TSPreferences.m','!self.ownsFontPanel || self.endingPreferences ||','!self.ownsFontPanel ||'),
    ('theme-edited-source','TSPreferences-Color.m','fromDictionary: EditingColors isWindowDark: withDarkColors','fromDictionary: liteColors isWindowDark: withDarkColors'),
    ('theme-appearance-default','TSPreferences-Color.m','fromDictionary: EditingColors isWindowDark: withDarkColors','fromDictionary: EditingColors isWindowDark: NO'),
    ('theme-marker-refresh','TSPreferences-Color.m','[self refreshInheritedBracketColorWells];',';'),
   ])
   if a.mutation_start:cases=cases[next(i for i,c in enumerate(cases) if c[0]==a.mutation_start):]
   for name,filename,old,new in cases:
    source=(r/'Sources'/filename).read_text()
    count=source.count(old)
    assert count>0,(name,count)
    # Color has two setter paths; both must implement the same disabled color.
    assert count==1 or name in ('disabled-label-color','theme-marker-refresh'),(name,count)
    stage=t/name;stage.mkdir()
    changed=stage/filename;changed.write_text(source.replace(old,new))
    replacements={str(r/'Sources'/filename):changed}
    if filename=='TSSettingsCatalogLayout.inc':shutil.copy2(r/'Sources/TSSettingsPaneClassification.inc',stage/'TSSettingsPaneClassification.inc')
    if filename.endswith('.inc'):
     for unit in ['TSPreferences.m','TSPreferences+Panes.m']:
      copied=stage/unit;shutil.copy2(r/'Sources'/unit,copied);replacements[str(r/'Sources'/unit)]=copied
    build(replacements)
    result=subprocess.run([str(t/'probe'),str(bundle)],capture_output=True,text=True,timeout=120)
    assert result.returncode and 'FAIL:' in result.stderr,(name,result.stdout,result.stderr)
    if a.output:(a.output/(name+'-'+bundle.stem+'.log')).write_text(result.stdout+result.stderr)
    print('DETECTED',name,result.stderr.strip(),flush=True)
   build();subprocess.run([str(t/'probe'),str(bundle)],check=True,timeout=120);print('NORMAL CONTROL',bundle.stem,flush=True)
