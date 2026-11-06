#!/usr/bin/env python3
"""Load every compiled preferences nib and exercise marker choices with isolated defaults."""
from pathlib import Path
import subprocess, tempfile, re
root=Path(__file__).resolve().parents[1]
source=(root/'Sources/TSPreferences.m').read_text()
def method(sig):
 a=source.index("\n"+sig)+1;b=source.index('\n}',a)+2;return source[a:b]
methods='\n'.join(method(s) for s in ['- (void)updateInvisibleCharacterControls:', '- (IBAction)invisibleCharacterChanged:'])
keys=['Space','FullwidthSpace','NewLine','Tab']
globals_source=(root/'Sources/globals.m').read_text(encoding='latin1')
constants='\n'.join(re.findall(r'^NSString \*(?:show(?:Space|FullwidthSpace|Tab|NewLine)CharacterKey|(?:Space|FullwidthSpace|Tab|NewLine)CharacterKindKey)\s*=.*?;', globals_source, re.M))
assert len(constants.splitlines())==8
update=method('- (void)updateControlsFromUserDefaults:')
assert '[self updateInvisibleCharacterControls:defaults];' in update
for caller in ('- (IBAction)showPreferences:', '- (void)undoDefaultPrefs:', '- (IBAction)setDefaults:'):
 assert '[self updateControlsFromUserDefaults:SUD];' in method(caller)
checkboxes='\n'.join(line for line in update.splitlines() if any('_show'+k+'CharacterButton setState:' in line for k in keys))
assert len(checkboxes.splitlines())==4
methods+='\n- (void)reloadControls:(NSUserDefaults *)defaults {\n'+checkboxes+'\n[self updateInvisibleCharacterControls:defaults];\n}'

ivars='\n'.join(f'NSPopUpButton *_{k}CharacterKindPopup; NSButton *_show{k}CharacterButton;' for k in keys)
program=r'''
#import <Cocoa/Cocoa.h>
#import "TSInvisibleCharacters.h"
#import "MemoryDefaults.h"
static NSUserDefaults *settings;
#define SUD settings
CONSTANTS
@interface TSPreferences:NSObject { @public NSUndoManager *_undoManager; BOOL invisibleCharacterTouched; IVARS }
@end
@implementation TSPreferences
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
METHODS
@end
@interface TSPreferenceWindow:NSWindow
@end
@implementation TSPreferenceWindow
- (BOOL)setFrameAutosaveName:(NSString *)name {return NO;}
- (void)saveFrameUsingName:(NSString *)name {}
@end
static void Check(BOOL ok, NSString *why) {if(!ok){NSLog(@"FAIL: %@",why);exit(1);}}
int main(int argc,char **argv){@autoreleasepool{
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 settings=[TSMemoryDefaults new];
 NSArray *keys=@[@"SpaceCharacterKind",@"FullwidthSpaceCharacterKind",@"NewLineCharacterKind",@"TabCharacterKind"];
 NSArray *show=@[@"ShowSpaceCharacter",@"ShowFullwidthSpaceCharacter",@"ShowNewLineCharacter",@"ShowTabCharacter"];
 NSArray *expected=@[@[@"␣",@"·"],@[@"□",@"■"],@[@"↵",@"¶",@"↩",@"⏎"],@[@"‣",@"▹",@"⇥"]];
 for(int n=1;n<argc;n++){
  TSPreferences *owner=[TSPreferences new];owner->_undoManager=[NSUndoManager new];owner->_undoManager.groupsByEvent=NO;
  NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:@(argv[n])] bundle:nil];NSArray *objects;
  Check([nib instantiateWithOwner:owner topLevelObjects:&objects],@"compiled nib loads");
  NSArray *popups=@[owner->_SpaceCharacterKindPopup,owner->_FullwidthSpaceCharacterKindPopup,owner->_NewLineCharacterKindPopup,owner->_TabCharacterKindPopup];
  NSArray *buttons=@[owner->_showSpaceCharacterButton,owner->_showFullwidthSpaceCharacterButton,owner->_showNewLineCharacterButton,owner->_showTabCharacterButton];
  for(int i=0;i<4;i++){[settings setInteger:1 forKey:keys[i]];[settings setBool:YES forKey:show[i]];[(NSButton *)buttons[i] setState:NSControlStateValueOn];}
  [owner updateInvisibleCharacterControls:settings];
  for(int i=0;i<4;i++){
   NSPopUpButton *p=popups[i];NSButton *b=buttons[i];
   NSView *box=p.superview.superview;
   Check(box.frame.size.width>100 && box.frame.size.height>100,@"visible settings box bounds");
   Check(NSContainsRect(p.superview.bounds,p.frame),@"popup stays inside settings box");
   Check([p isKindOfClass:NSPopUpButton.class] && p.target==owner && p.action==@selector(invisibleCharacterChanged:),@"popup wiring");
   Check([p.itemTitles isEqual:expected[i]],@"compiled menu glyphs and order");
   Check([TSInvisibleMarkers(keys[i]) isEqual:p.itemTitles],@"rendering and UI choices agree");
   Check(p.selectedTag==1 && p.enabled,@"existing second choice preserved");
   for(NSInteger j=0;j<p.numberOfItems;j++){
    [owner->_undoManager beginUndoGrouping];[p selectItemAtIndex:j];[NSApp sendAction:p.action to:p.target from:p];[owner->_undoManager endUndoGrouping];
    Check(TSInvisibleStoredIndex(settings,keys[i])==j,@"each choice saves");
    Check([settings integerForKey:keys[i]]>=0 && [settings integerForKey:keys[i]]<2,@"older renderers always receive a safe index");
    Check([p.title isEqual:expected[i][j]],@"selected menu label");
    [owner reloadControls:settings]; Check(p.selectedTag==j,@"persisted selection survives reload");
    [owner->_undoManager undo];[owner updateInvisibleCharacterControls:settings];
    Check(p.selectedTag==1 && [settings integerForKey:keys[i]]==1,@"cancel/undo restores prior choice");
   }
   // Switching back from an extended marker must remove the extended value.
   for(NSInteger added=2;added<p.numberOfItems;added++) for(NSInteger legacy=0;legacy<2;legacy++){
    [owner->_undoManager beginUndoGrouping];
    [p selectItemAtIndex:added];[NSApp sendAction:p.action to:p.target from:p];
    [p selectItemAtIndex:legacy];[NSApp sendAction:p.action to:p.target from:p];
    [owner->_undoManager endUndoGrouping];
    Check([settings objectForKey:TSInvisibleExtendedKey(keys[i])]==nil,@"returning to a legacy choice removes the extended key");
    [owner reloadControls:settings];Check(p.selectedTag==legacy,@"legacy choice survives reload after extended choice");
    [owner->_undoManager undo];[owner reloadControls:settings];
    Check(p.selectedTag==1 && [settings objectForKey:TSInvisibleExtendedKey(keys[i])]==nil,@"Cancel restores the choice before multiple changes");
   }
   [owner->_undoManager beginUndoGrouping];b.state=NSControlStateValueOff;[NSApp sendAction:b.action to:b.target from:b];[owner->_undoManager endUndoGrouping];
   Check(!p.enabled && p.selectedTag==1,@"disabled row retains selection");
   [owner->_undoManager undo];b.state=NSControlStateValueOn;[owner updateInvisibleCharacterControls:settings];Check(p.enabled,@"undo restores enabled state");
   for(id bad in @[@(-1),@99,@"junk"]){
    [settings setObject:bad forKey:keys[i]];[owner updateInvisibleCharacterControls:settings];
    Check(p.indexOfSelectedItem==0,@"invalid stored selection falls back");
    Check([TSInvisibleMarker(TSInvisibleMarkers(keys[i]),[bad integerValue]) isEqual:expected[i][0]],@"invalid rendering index is safe");
   }
   [settings setInteger:1 forKey:keys[i]];[owner updateInvisibleCharacterControls:settings];
  }
  // Repair a menu whose count is correct but contents are wrong.
  NSPopUpButton *tab=popups[3]; [tab itemAtIndex:0].title=@"wrong";
  [owner reloadControls:settings]; Check([tab.itemTitles isEqual:expected[3]],@"same-count damaged menu repaired");
  // A fresh profile removes extended values and updates both checkbox and selection.
  [((TSMemoryDefaults *)settings).values removeAllObjects];
  for(int i=0;i<4;i++){ [settings setObject:@"0" forKey:keys[i]]; [settings setObject:@"NO" forKey:show[i]]; }
  [owner reloadControls:settings];
  for(int i=0;i<4;i++)Check([(NSPopUpButton *)popups[i] selectedTag]==0 && ![(NSPopUpButton *)popups[i] isEnabled] && [(NSButton *)buttons[i] state]==NSControlStateValueOff,@"profile defaults reload all controls");
  // Extended choices round-trip and Cancel removes a newly-created key entirely.
  [owner->_undoManager beginUndoGrouping]; [tab selectItemAtIndex:2]; [owner invisibleCharacterChanged:tab]; [owner->_undoManager endUndoGrouping];
  Check([settings integerForKey:keys[3]]==0 && [settings integerForKey:TSInvisibleExtendedKey(keys[3])]==2,@"extended choice uses separate key");
  [owner->_undoManager undo]; Check([settings objectForKey:TSInvisibleExtendedKey(keys[3])]==nil,@"Cancel removes absent extended key");
  [settings setInteger:2 forKey:TSInvisibleExtendedKey(keys[3])]; [settings setInteger:1 forKey:keys[3]];
  [owner reloadControls:settings]; Check(tab.selectedTag==1,@"historical second choice overrides stale extended value");
  [((TSMemoryDefaults *)settings).values removeAllObjects];
  for(id o in objects)if([o isKindOfClass:NSWindow.class])[o orderOut:nil];
 }

 puts("PASS: all compiled nibs; historical choices, added glyphs, save/undo, disabled rows and invalid settings");
}return 0;}
'''.replace('CONSTANTS',constants).replace('IVARS',ivars).replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='texshop-invisible-') as td:
 t=Path(td);(t/'probe.m').write_text(program)
 subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-I',str(root/'Sources'),'-I',str(root/'Tests'),str(t/'probe.m'),'-o',str(t/'probe')],check=True)
 nibs=sorted((root/'Resources/Interfaces').glob('*.lproj/Preferences.nib/keyedobjects*.nib'))
 assert len(nibs)==24
 subprocess.run([str(t/'probe'),*map(str,nibs)],check=True)

with tempfile.TemporaryDirectory(prefix="texshop-marker-draw-") as td:
 subprocess.run(["/bin/bash",str(root/"Tests/run-invisible-baseline.sh"),str(Path(td)/"markers.png")],check=True)
