#!/usr/bin/env python3
"""Load every compiled preferences nib and exercise marker choices with isolated defaults."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'Sources/TSPreferences.m').read_text()
def method(sig):
 a=source.index("\n"+sig)+1;b=source.index('\n}',a)+2;return source[a:b]
methods='\n'.join(method(s) for s in ['- (void)updateInvisibleCharacterControls:', '- (IBAction)invisibleCharacterChanged:'])
keys=['Space','FullwidthSpace','NewLine','Tab']
constants='\n'.join(f'static NSString *{k}CharacterKindKey=@"{k}CharacterKind", *show{k}CharacterKey=@"Show{k}Character";' for k in keys)
ivars='\n'.join(f'NSPopUpButton *_{k}CharacterKindPopup; NSButton *_show{k}CharacterButton;' for k in keys)
program=r'''
#import <Cocoa/Cocoa.h>
#import "TSInvisibleCharacters.h"
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
 NSString *domain=[@"org.texshop.invisible-test." stringByAppendingString:NSUUID.UUID.UUIDString];
 settings=[[NSUserDefaults alloc]initWithSuiteName:domain];
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
    Check([settings integerForKey:keys[i]]==j,@"each choice saves");
    Check([TSInvisibleMarker(TSInvisibleMarkers(keys[i]),j) isEqual:p.title],@"saved value renders selected glyph");
    [owner->_undoManager undo];[owner updateInvisibleCharacterControls:settings];
    Check(p.selectedTag==1 && [settings integerForKey:keys[i]]==1,@"cancel/undo restores prior choice");
   }
   [owner->_undoManager beginUndoGrouping];b.state=NSControlStateValueOff;[NSApp sendAction:b.action to:b.target from:b];[owner->_undoManager endUndoGrouping];
   Check(!p.enabled && p.selectedTag==1,@"disabled row retains selection");
   [owner->_undoManager undo];b.state=NSControlStateValueOn;[owner updateInvisibleCharacterControls:settings];Check(p.enabled,@"undo restores enabled state");
   for(NSNumber *bad in @[@(-1),@99]){
    [settings setInteger:bad.integerValue forKey:keys[i]];[owner updateInvisibleCharacterControls:settings];
    Check(p.indexOfSelectedItem==0,@"invalid stored selection falls back");
    Check([TSInvisibleMarker(TSInvisibleMarkers(keys[i]),bad.integerValue) isEqual:expected[i][0]],@"invalid rendering index is safe");
   }
   [settings setInteger:1 forKey:keys[i]];[owner updateInvisibleCharacterControls:settings];
  }
  for(id o in objects)if([o isKindOfClass:NSWindow.class])[o orderOut:nil];
 }
 [settings removePersistentDomainForName:domain];
 puts("PASS: all compiled nibs; historical choices, added glyphs, save/undo, disabled rows and invalid settings");
}return 0;}
'''.replace('CONSTANTS',constants).replace('IVARS',ivars).replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='texshop-invisible-') as td:
 t=Path(td);(t/'probe.m').write_text(program)
 subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-I',str(root/'Sources'),str(t/'probe.m'),'-o',str(t/'probe')],check=True)
 nibs=sorted((root/'Resources/Interfaces').glob('*.lproj/Preferences.nib/keyedobjects*.nib'))
 assert len(nibs)==24
 subprocess.run([str(t/'probe'),*map(str,nibs)],check=True)
