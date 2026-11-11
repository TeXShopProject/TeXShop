#!/usr/bin/env python3
"""Compile the complete production Settings owner; all windows stay unordered."""
from pathlib import Path
import argparse,subprocess,tempfile,shutil,re,json,os
from pane_fixtures import bundles,sources
from shortcut_sources import NAMES
from source_tree import include_args, source_file
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('output',nargs='?',type=Path);p.add_argument('--app',type=Path);p.add_argument('--language');p.add_argument('--mutations',action='store_true');p.add_argument('--integer-field-mutations',action='store_true');p.add_argument('--additional-mutations',action='store_true');p.add_argument('--mutation-start');p.add_argument('--audit-mutations',action='store_true');p.add_argument('--third-audit-mutations',action='store_true');p.add_argument('--capture-languages',nargs='+');p.add_argument('--mutation-only');p.add_argument('--fourth-audit-mutations',action='store_true');p.add_argument('--fifth-audit-mutations',action='store_true');p.add_argument('--opacity-field-mutations',action='store_true');p.add_argument('--sixth-audit-mutations',action='store_true');p.add_argument('--seventh-audit-mutations',action='store_true');p.add_argument('--visible-text-output',type=Path);p.add_argument('--visible-text-mutation',action='store_true');p.add_argument('--visible-text-whitespace-mutation',action='store_true');a=p.parse_args()
with tempfile.TemporaryDirectory(prefix='texshop-product-shell-') as temp:
 t=Path(temp);(t/'fixtures').mkdir()
 compile=['xcrun','clang','-fobjc-arc','-DTS_TEST_REAL_SHORTCUTS','-DTS_TEST_REAL_PROFILE','-DNSBeginCriticalAlertSheet=TSTestUnexpectedCriticalSheet','-F',str(r/'Frameworks'),'-Wno-deprecated-declarations','-mmacosx-version-min=14.6',*include_args(r),'-I',str(r/'Tests'),'-framework','Cocoa','-framework','Carbon',str(r/'Tests/SettingsProductShell.m'),str(r/'Tests/PreferencesTestServices.m'),*map(str,sources(r)),str(r/'Sources/Settings/TSPreferences+Panes.m'),*[str(source_file(r, n)) for n in ['TSPreferences.m','TSPreferenceProfile.m','TSPreferences-Color.m','TSColorSupport.m','TSThemeFileStore.m','TSPreferenceInput.m','globals.m','TSDockIconController.m',*NAMES]],*map(str,sorted((r/'Sources').rglob('TSSettings*.m'))),'-o',str(t/'probe')]
 def build(replacements=None):
  replacements=replacements or {}
  subprocess.run([str(replacements.get(x,x)) for x in compile],check=True)
 build()
 shell=t/'SettingsWindow.nib'
 if a.app:shutil.copy2(a.app/'Contents/Resources/Base.lproj/SettingsWindow.nib',shell)
 else:subprocess.run(['xcrun','ibtool','--compile',str(shell),str(r/'Resources/Interfaces/Base.lproj/SettingsWindow.xib')],check=True)
 for bundle in bundles(r,t/'fixtures',product=a.app,dock=True):
  if a.language and bundle.stem!=a.language:continue
  (bundle/'Contents/Resources/Defaults').mkdir(exist_ok=True);(bundle/'Contents/Resources/Themes').mkdir(exist_ok=True)
  shutil.copy2(r/'Resources/Defaults/FactoryDefaults.plist',bundle/'Contents/Resources/Defaults/FactoryDefaults.plist')
  shutil.copy2(r/'Tests/Fixtures/SettingsDependencies.json',bundle/'Contents/Resources/SettingsDependencies.json')
  shutil.copy2(r/'Tests/Fixtures/SettingsCatalogReference.json',bundle/'Contents/Resources/SettingsCatalogReference.json')
  shutil.copy2(r/'Tests/Fixtures/SettingsInputRules.json',bundle/'Contents/Resources/SettingsInputRules.json')
  shutil.copy2(r/'Tests/Fixtures/SettingsHeightReference.json',bundle/'Contents/Resources/SettingsHeightReference.json')
  for themeName in ['LiteTheme','DarkTheme']:
   shutil.copy2(r/('Resources/TeXShop/Themes/'+themeName+'.plist'),bundle/('Contents/Resources/Themes/'+themeName+'.plist'))
  profiles=bundle/'Contents/Resources/Profiles';profiles.mkdir()
  for profile in sorted((r/'Resources/Defaults').glob('*Defaults*.plist')):shutil.copy2(profile,profiles/profile.name);shutil.copy2(profile,bundle/'Contents/Resources/Defaults'/profile.name)
  shutil.copy2(shell,bundle/'Contents/Resources/SettingsWindow.nib')
  if (a.visible_text_mutation or a.visible_text_whitespace_mutation) and bundle.stem=='fr':
   path=bundle/'Contents/Resources/fr.lproj/SettingsCategories.strings'
   values=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(path)]))
   assert values['group.editor.2.title']=='Saisie'
   values['group.editor.2.title']='Typing' if a.visible_text_mutation else ' Saisie '
   path.write_text('\n'.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';' for k,v in values.items())+'\n')
  env=dict(os.environ)
  if a.visible_text_output:
   a.visible_text_output.mkdir(parents=True,exist_ok=True)
   env['TS_SETTINGS_VISIBLE_TEXT_PATH']=str(a.visible_text_output/(bundle.stem+'.json'))
  command=[str(t/'probe'),str(bundle)]
  if a.output and (not a.capture_languages or bundle.stem in a.capture_languages):folder=a.output/bundle.stem;folder.mkdir(parents=True,exist_ok=True);command.append(str(folder))
  print('LANGUAGE',bundle.stem,flush=True);subprocess.run(command,check=True,timeout=120,env=env)

  if a.integer_field_mutations or a.mutations or a.additional_mutations or a.audit_mutations or a.third_audit_mutations or a.fourth_audit_mutations or a.fifth_audit_mutations or a.opacity_field_mutations or a.sixth_audit_mutations or a.seventh_audit_mutations:
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
    text=(r/'Sources/Settings/TSPreferences.m').read_text();start=text.index('- (IBAction)XML'+name+'ButtonChanged:');end=text.index('\n}',start)+2
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
   if a.audit_mutations:cases=[]
   audit_cases=[
    ('close-generation','TSPreferences.m','self.endingPreferences = YES;\n    self.themeOperationGeneration++;\n    if (_prefsWindow.attachedSheet != nil) [_prefsWindow endSheet:_prefsWindow.attachedSheet returnCode:NSModalResponseCancel];\n    [self cancelEnginePathDiscovery];','self.endingPreferences = YES;\n    [self cancelEnginePathDiscovery];','Termination invalidates pending theme operations'),
    ('sheet-edit-guard','TSPreferences.m','if (showError && _prefsWindow.attachedSheet != nil) return NO;',';','An attached sheet blocks the owner editing transaction'),
    ('reopen-ending','TSPreferences.m','self.endingPreferences = NO;','self.endingPreferences = YES;','Showing a closed panel starts a fresh editing session'),
    ('cascade','TSSettingsWindowController.m','self.shouldCascadeWindows = NO;','self.shouldCascadeWindows = YES;','Settings has a title and disables cascading'),
    ('empty-title','TSSettingsWindowController.m','self.window.title = pane.title ?: @"";','self.window.title = @"";','Every category including Keyboard updates the window title'),
    ('tab-notification','TSPreferences.m','kind:TSPreferenceInputInteger minimum:2 maximum:50 allowsEmpty:NO notification:TSPreferenceNotificationForKey(tabsKey)','kind:TSPreferenceInputInteger minimum:2 maximum:50 allowsEmpty:NO notification:nil','Input notification contract'),
    ('keyboard-card-hidden','TSShortcutPaneController.m','[TSPrefPaneLayout decorateGroupsInView:group];','[TSPrefPaneLayout decorateGroupsInView:group]; [self viewWithIdentifier:@"card.background" inView:group].hidden=YES;','Every catalog group has its visible rounded filled card'),
    ('autosave-string','TSSettingsDependencies.inc','AutoSaveEnabledKey, 0, TSDependencyBoolean','AutoSaveEnabledKey, 0, TSDependencyInteger','Factory string YES'),
    ('live-find-action','TSPreferences.m','[self applyEffectsForPreferenceKeys:[NSSet setWithObject:FindMethodKey]];',';','Actual find action delivers one live-view notification'),
    ('opacity-scale','TSPrefPaneLayout.m','MIN(100,MAX(0,percent))/100.0','MIN(100,MAX(0,percent))/1.0','Opacity action preserves RGB'),
    ('opacity-read','TSPrefPaneLayout.m','self.source.color.alphaComponent*100','round(self.source.color.alphaComponent*100)','Loading a theme preserves fractional opacity'),
    ('opacity-no-action','TSPrefPaneLayout.m','self.source.color=[self.source.color colorWithAlphaComponent:MIN(100,MAX(0,percent))/100.0];\n    [self.source sendAction:self.source.action to:self.source.target];','self.source.color=[self.source.color colorWithAlphaComponent:MIN(100,MAX(0,percent))/100.0];','Opacity action preserves RGB'),
   ]
   prep='if (preparations & TSPreferencePrepareEncoding) [[TSEncodingSupport sharedInstance] setupForEncoding];'
   source=(r/'Sources/Settings/TSPreferences.m').read_text()
   if prep in source:
    old=source[source.index(prep):source.index('TSPostPreferenceNotifications(changed, self);')+len('TSPostPreferenceNotifications(changed, self);')]
    audit_cases.append(('encoding-order','TSPreferences.m',old,old.replace(prep,'')+'\n    '+prep,'Encoding is prepared before profile notifications'))
   expected=json.loads((r/'Tests/Fixtures/SettingsOwnerMutationFailures.json').read_text())
   for name,file,old,new,message in audit_cases:
    cases.append((name,file,old,new));expected[name]=message
   if a.third_audit_mutations:
    cases=[]
    third=[
     ('search-result-height','TSSettingsSidebarRow.m','return MAX(44,height);','return 44;','Search result height matches regular display'),
     ('keyboard-title','TSSettingsWindowController.m','self.window.title = NSLocalizedString(@"Keyboard", @"");','self.window.title = @"";','Every category including Keyboard updates the window title'),
     ('termination-generation','TSPreferences.m','- (void)finishPreferencesForTermination\n{\n    self.endingPreferences = YES;\n    self.themeOperationGeneration++;','- (void)finishPreferencesForTermination\n{\n    self.endingPreferences = YES;','Termination invalidates pending theme operations'),
     ('keyboard-card-alpha','TSShortcutPaneController.m','[TSPrefPaneLayout decorateGroupsInView:group];','[TSPrefPaneLayout decorateGroupsInView:group]; [self viewWithIdentifier:@"card.background" inView:group].alphaValue=0;','Every catalog group has its visible rounded filled card'),
     ('find-reverse','TSPreferences.m','[self applyEffectsForPreferenceKeys:[NSSet setWithObject:FindMethodKey]];','if ([SUD integerForKey:FindMethodKey]!=0) [self applyEffectsForPreferenceKeys:[NSSet setWithObject:FindMethodKey]];','Bar to panel action delivers the reverse live-view notification'),
     ('opacity-region','TSPrefPaneLayout.m','formatter.locale=NSLocale.currentLocale;','formatter.locale=[[NSLocale alloc]initWithLocaleIdentifier:@"en_US"];','Opacity percentage follows the current regional format'),
     ('opacity-missing-save','TSPreferences-Color.m','EditingColors[key]=@[@0,@0,@0,@(well.color.alphaComponent)];','return;','Absent alpha is created and saved once on edit'),
    ]
    for key in ['Source','Console','Preview']:
     third.append(('opacity-missing-'+key,'TSPreferences-Color.m',key+'AlphaColorWell.color = TSThemeWindowAlphaColor(EditingColors, TSTheme'+key+'AlphaKey)',key+'AlphaColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: TSTheme'+key+'AlphaKey]','Absent alpha opens without exception and displays full opacity'))
    for name,file,old,new,message in third:cases.append((name,file,old,new));expected[name]=message
   if a.fourth_audit_mutations:cases=[('search-height-minus-one','TSSettingsSidebarRow.m','CGFloat height=10;','CGFloat height=9;')];expected['search-height-minus-one']='Search result height matches regular display'
   if a.fifth_audit_mutations:
    fifth=[
     ('dock-caption','TSDockIconController.m','labelWithString:years[index]','labelWithString:label','Dock options have an accessible image and the approved year-only caption'),
     ('category-duplicate-name','TSSettingsWindowController.m','self.searchQuery.length && self.searchResults[(NSUInteger)row].targetIdentifier.length','self.searchQuery.length','Category result has one name and its category icon'),
     ('whole-color-table','TSSettingsWindowController.m','if ([ancestor isKindOfClass:NSGridView.class]) {','if (NO) {','Merged color search highlights only its selected grid row'),
     ('wrong-color-row','TSSettingsWindowController.m','NSInsetRect(bounds, -6, -3)','grid.bounds','Color row highlight leaves padding around names and percent fields'),
     ('bold-search-measurement','TSSettingsSidebarRow.m','NSArray *fonts=@[[NSFont systemFontOfSize:NSFont.systemFontSize],','NSArray *fonts=@[[NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold],','Search result height matches regular display'),
     ('search-measurement-insets','TSSettingsSidebarRow.m','CGFloat cellWidth=NSWidth([label frameForAlignmentRect:NSMakeRect(0,0,available,1)]);','CGFloat cellWidth=available;','Search result height matches regular display'),
    ]
    cases=[]
    for name,file,old,new,message in fifth:cases.append((name,file,old,new));expected[name]=message
   if a.opacity_field_mutations:
    field=[
     ('opacity-field-formatter','TSPrefPaneLayout.m','_field.formatter=[TSOpacityFormatter new];',';','Opacity has an editable whole-percentage field'),
     ('opacity-field-clamp','TSPrefPaneLayout.m',"percent = MIN(100, percent * 10 + [digits characterAtIndex:i] - '0');","percent = percent * 10 + [digits characterAtIndex:i] - '0';",'Opacity entry above 100 is clamped to 100'),
     ('opacity-field-letters','TSPrefPaneLayout.m','return [magnitude rangeOfCharacterFromSet:other].location == NSNotFound ? normalized : nil;','return normalized;','Opacity entry refuses letters, signs and decimals'),
     ('opacity-field-fullwidth','TSPrefPaneLayout.m','[string.precomposedStringWithCompatibilityMapping stringByTrimmingCharactersInSet:','[string stringByTrimmingCharactersInSet:','Full-width opacity digits follow the other numeric fields'),
     ('opacity-field-negative','TSPrefPaneLayout.m','NSInteger percent = 0;','NSInteger percent = [digits hasPrefix:@"-"] ? -5 : 0;','Negative opacity is clamped to zero'),
     ('opacity-field-long','TSPrefPaneLayout.m','NSString *digits = [*partial precomposedStringWithCompatibilityMapping];','NSString *digits = [*partial precomposedStringWithCompatibilityMapping]; if(digits.length>3)return NO;','Opacity retains the complete typed or pasted text until commit'),
     ('opacity-field-partial','TSPrefPaneLayout.m','NSString *digits = [*partial precomposedStringWithCompatibilityMapping];','NSString *digits = [TSOpacityFormatter normalizedDigits:*partial]; if(digits==nil)return NO;','Opacity retains the complete typed or pasted text until commit'),
     ('opacity-field-overflow','TSPrefPaneLayout.m',"percent = MIN(100, percent * 10 + [digits characterAtIndex:i] - '0');","percent = percent * 10 + [digits characterAtIndex:i] - '0';\n    percent = MIN(100,percent);",'Typed opacity moves the slider and saves once'),
     ('opacity-field-correction','TSPrefPaneLayout.m','self.field.objectValue=@(percent);','self.field.objectValue=@100;','Typed opacity moves the slider and saves once'),
     ('opacity-field-sync','TSPrefPaneLayout.m','    [self applyPercent:entered];\n','',
      'Explicitly entering the displayed integer replaces a fractional opacity'),
     ('opacity-field-passthrough','TSPrefPaneLayout.m','if(!self.fieldWasEdited || entered==self.slider.doubleValue){[self synchronize];return;}',';','Passing through the opacity field keeps the stored fractional alpha'),
     ('opacity-field-empty','TSPrefPaneLayout.m','    if(formatter.rejectionHandler!=nil)formatter.rejectionHandler();\n','','Opacity entry refuses letters, signs and decimals'),
     ('opacity-field-disabled','TSPrefPaneLayout.m','self.slider.enabled=enabled;self.field.enabled=enabled;','self.slider.enabled=enabled;','Disabled opacity disables its numeric field'),
    ]
    cases=[]
    for name,file,old,new,message in field:cases.append((name,file,old,new));expected[name]=message
   if a.integer_field_mutations:
    integer=[
     ('integer-stepper-missing','TSSettingsPaneClassification.inc','        if([kind isEqual:@"integer"])[parts addObject:[TSPrefPaneLayout stepperForIntegerField:field]];\n','','tabIndentField has a stepper right beside it'),
     ('integer-formatter-missing','TSPreferences.m','field.formatter = rule.kind == TSPreferenceInputInteger ? [[TSIntegerInputFormatter alloc] initWithInput:rule] : nil;','field.formatter = nil;','tabIndentField keeps typing to digits and carries its range'),
     ('integer-letters','TSPreferenceInput.m','    if ([digits rangeOfCharacterFromSet:other].location != NSNotFound) return NO;\n','','Typing 1.5 is refused without changing the entry'),
     ('integer-fullwidth','TSPreferenceInput.m','    NSString *digits = [*partial precomposedStringWithCompatibilityMapping];\n    NSCharacterSet','    NSString *digits = *partial;\n    NSCharacterSet','Full-width digits become ASCII digits'),
     ('integer-end-editing','TSPreferenceInput.m','errorDescription:(out NSString * _Nullable *)error\n{\n    if (value != NULL) *value = [string copy];','errorDescription:(out NSString * _Nullable *)error\n{\n    if (value != NULL) *value = @([string integerValue]);','Text at the end of editing is left to the common validator'),
     ('stepper-skips-validation','TSPrefPaneLayout.m','        if([delegate respondsToSelector:@selector(control:textShouldEndEditing:)] && ![delegate control:field textShouldEndEditing:editor])return;\n','','Stepper keeps the warning for an invalid entry'),
     ('stepper-keeps-direction','TSPrefPaneLayout.m','    NSInteger direction=self.integerValue-1;\n    self.integerValue=1;\n','    NSInteger direction=self.integerValue-1;\n','Stepper up stores one more, shows it and notifies documents once'),
     ('stepper-no-action','TSPrefPaneLayout.m','    [field sendAction:field.action to:field.target];\n}\n@end\n@implementation TSPrefPaneLayout','}\n@end\n@implementation TSPrefPaneLayout','Stepper up stores one more, shows it and notifies documents once'),
     ('refresh-unranged','TSSettingsPaneRefresh.inc','[remainingParagraphIndentField setIntegerValue:TSStoredIntegerInRange(defaults, SourceHeadIndentKey, TSParagraphIndentRange)];','[remainingParagraphIndentField setIntegerValue:[defaults integerForKey:SourceHeadIndentKey]];','Out-of-range stored values are shown inside the ranges'),
     ('restore-unranged','TSPreferenceInput.m','    if (number != nil && self.kind == TSPreferenceInputInteger)\n','    if (NO)\n','Restoring an entry shows the stored value inside the range'),
     ('rule-range-literal','TSPreferences.m','minimum:TSInterlineSpaceRange.minimum maximum:TSInterlineSpaceRange.maximum','minimum:0 maximum:20','Independent rule contract for interlineSpacingField'),
    ]
    cases=[]
    for name,file,old,new,message in integer:cases.append((name,file,old,new));expected[name]=message
   if a.sixth_audit_mutations:
    sixth=[
     ('sidebar-width-plus-six','TSSettingsSidebarRow.m','width - 40','width - 34','Long localized sidebar names fit at every supported width'),
     ('column-word-break','TSSettingsPaneClassification.inc','[header.widthAnchor constraintGreaterThanOrEqualToConstant:width].active=YES;',';','Localized color column headings fit without breaking words'),
     ('highlight-no-inset','TSSettingsWindowController.m','NSInsetRect(bounds, -6, -3)','NSInsetRect(bounds, 0, -2)','Color row highlight leaves padding around names and percent fields'),
     ('opacity-rounded-equality','TSPrefPaneLayout.m','if(!self.fieldWasEdited || entered==self.slider.doubleValue)','if(lround(entered)==lround(self.slider.doubleValue))','Explicitly entering the displayed integer replaces a fractional opacity'),
     ('opacity-settings-old-reader','TSPreferences-Color.m','SourceAlphaColorWell.color = TSThemeWindowAlphaColor(EditingColors, TSThemeSourceAlphaKey);','SourceAlphaColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey:TSThemeSourceAlphaKey] ?: [NSColor colorWithWhite:0 alpha:1];','Invalid theme opacity loads safely and consistently'),
    ]
    cases=[]
    for name,file,old,new,message in sixth:cases.append((name,file,old,new));expected[name]=message
   if a.seventh_audit_mutations:
    cases=[('sidebar-width-plus-six','TSSettingsSidebarRow.m','width - 40','width - 34'),('search-placeholder-overflow','TSSettingsWindowController.m','self.settingsSearchField.placeholderString = NSLocalizedString(@"Search Settings", @"");','self.settingsSearchField.placeholderString = @"Search all settings with a deliberately overlong placeholder";')]
    expected['sidebar-width-plus-six']='Long localized sidebar names fit at every supported width'
    expected['search-placeholder-overflow']='Search placeholder fits every supported sidebar width'
   if a.mutation_start:cases=cases[next(i for i,c in enumerate(cases) if c[0]==a.mutation_start):]
   if a.mutation_only:cases=[c for c in cases if c[0]==a.mutation_only];assert cases
   for name,filename,old,new in cases:
    assert old != new, (name, 'Mutation must change the source')
    source=(source_file(r, filename)).read_text()
    count=source.count(old)
    assert count>0,(name,count)
    # Color has two setter paths; both must implement the same disabled color.
    assert count==1 or name in ('disabled-label-color','theme-marker-refresh'),(name,count)
    stage=t/bundle.stem/name;stage.mkdir(parents=True)
    changed=stage/filename;changed.write_text(source.replace(old,new))
    replacements={str(source_file(r, filename)):changed}
    if filename=='TSSettingsCatalogLayout.inc':shutil.copy2(r/'Sources/Settings/TSSettingsPaneClassification.inc',stage/'TSSettingsPaneClassification.inc')
    if filename.endswith('.inc'):
     for unit in ['TSPreferences.m','TSPreferences+Panes.m']:
      copied=stage/unit;shutil.copy2(source_file(r, unit),copied);replacements[str(source_file(r, unit))]=copied
    build(replacements)
    result=subprocess.run([str(t/'probe'),str(bundle)],capture_output=True,text=True,timeout=120)
    assert result.returncode and 'FAIL: '+expected[name] in result.stderr,(name,expected[name],result.stdout,result.stderr)
    if a.output:(a.output/(name+'-'+bundle.stem+'.log')).write_text(result.stdout+result.stderr)
    print('DETECTED',name,result.stderr.strip(),flush=True)
   build();subprocess.run([str(t/'probe'),str(bundle)],check=True,timeout=120);print('NORMAL CONTROL',bundle.stem,flush=True)
