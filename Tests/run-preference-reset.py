#!/usr/bin/env python3
"""Exercise all nine profile transactions and their production reflection path."""
from pathlib import Path
import subprocess,tempfile,sys,re
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'Sources/TSPreferences.m').read_text()
a=s.index('\n- (void)applyPreferenceProfile:')+1;body=s[a:s.index('\n}',a)+2]
mutation=sys.argv[1] if len(sys.argv)>1 else ''
mutations={
 'recolor':('@"MakeatletterEnabled",',''),
 'runtime':('[self refreshRuntimePreferences];',';'),
 'dock':('if ([changed containsObject:@"DockIconStyle"]) [[TSDockIconController sharedController] restoreSavedIcon];',';'),
 'spell':('[TSSpellSupport preferencesDidChange];',';'),
 'theme':('[[TSColorSupport sharedInstance] initializeColors];',';'),
 'no-change':('if (![changed intersectsSet:[NSSet setWithArray:groups[name]]]) continue;',';'),
}
if mutation:
 old,new=mutations[mutation];assert old in body;body=body.replace(old,new)
# The confirmation handler invokes this transaction only after explicit local confirmation.
assert '[strongSelf applyPreferenceProfile:proposal font:font];' in s
for old in ['undoDefaultPrefs:', 'cancelButtonPressed:', '_undoManager', 'MagnificationChangedNotification']:
 assert old not in re.sub(r"/\*.*?\*/", "", s, flags=re.S),old
names=['DocumentFontChangedNotification','ConsoleFontChangedNotification','DocumentSyntaxColorNotification','DocumentAutoCompleteNotification','DocumentBibDeskCompleteNotification','ExternalEditorNotification','SourceColorChangedNotification']
program=r'''
#import <Cocoa/Cocoa.h>
#import "MemoryDefaults.h"
#import "TSPreferenceProfile.h"
static TSMemoryDefaults *memory;
#define SUD memory
CONSTANTS
static NSUInteger dock,spell,colors,encoding;
@interface TSDockIconController:NSObject @end
@implementation TSDockIconController
+ (id)sharedController {static id v;if(!v)v=[self new];return v;}
- (void)restoreSavedIcon {dock++;}
@end
@interface TSSpellSupport:NSObject @end
@implementation TSSpellSupport
+ (void)preferencesDidChange {spell++;}
@end
@interface TSColorSupport:NSObject @end
@implementation TSColorSupport
+ (id)sharedInstance {static id v;if(!v)v=[self new];return v;}
- (void)initializeColors {colors++;}
@end
@interface TSEncodingSupport:NSObject @end
@implementation TSEncodingSupport
+ (id)sharedInstance {static id v;if(!v)v=[self new];return v;}
- (void)setupForEncoding {encoding++;}
@end
@interface TSAppDelegate:NSObject
@property NSUInteger copies;
- (void)changeImageCopyType:(id)item;
@end
@implementation TSAppDelegate
- (void)changeImageCopyType:(id)item { self.copies++; }
@end
@interface FakeApp:NSObject
@property TSAppDelegate *delegate;
@end
@implementation FakeApp @end
static FakeApp *app;
#undef NSApp
#define NSApp app
@interface Popup:NSObject @end
@implementation Popup
- (id)selectedItem {return self;}
@end
@interface Probe:NSObject { @public Popup *_imageCopyTypePopup; }
@property id documentFont,fontAttributes;
@property NSUInteger runtime,controls,themes;
@end
@implementation Probe
- (void)refreshRuntimePreferences {self.runtime++;}
- (void)updateControlsFromUserDefaults:(id)d {self.controls++;}
- (void)PrepareColorPane:(id)d {self.themes++;}
BODY
@end
static void check(BOOL ok,const char *msg){if(!ok){fprintf(stderr,"FAIL: %s\n",msg);exit(1);}}
int main(int argc,char **argv){@autoreleasepool{
 NSData *font=[@"font" dataUsingEncoding:NSUTF8StringEncoding];
 for(int n=1;n<argc;n++) {
  NSDictionary *profile=[NSDictionary dictionaryWithContentsOfFile:@(argv[n])];
  TSPreferenceProfile *proposal=[[TSPreferenceProfile alloc]initWithProfile:profile documentFont:font];check(proposal!=nil,"valid profile");
  memory=[TSMemoryDefaults new];Probe *p=[Probe new];p->_imageCopyTypePopup=[Popup new];app=[FakeApp new];app.delegate=[TSAppDelegate new];
  NSMutableArray *notes=[NSMutableArray new];
  id token=[NSNotificationCenter.defaultCenter addObserverForName:nil object:p queue:nil usingBlock:^(NSNotification *note){[notes addObject:note.name];check(note.userInfo==nil,"no transient theme dictionary");}];
  [p applyPreferenceProfile:proposal font:nil];
  check(p.runtime==1 && p.controls==1 && p.themes==1,"runtime and loaded controls refresh exactly once");
  [notes removeAllObjects];NSUInteger d=dock,sp=spell,c=colors;
  [p applyPreferenceProfile:proposal font:nil];
  check(notes.count==0 && d==dock && sp==spell && c==colors,"unchanged profile does not broadcast or touch Dock/spelling/themes");
  [SUD setBool:![profile[@"MakeatletterEnabled"] boolValue] forKey:@"MakeatletterEnabled"];
  [p applyPreferenceProfile:proposal font:nil];
  check([notes containsObject:@"NeedsForRecolorNotification"],"makeatletter refreshes existing text");
  [notes removeAllObjects];
  for (NSString *key in @[@"AlwaysHighlightEnabled",@"ShowIndicatorForMoveEnabled",@"HighlightContentEnabled",@"BeepEnabled",@"FlashBackgroundEnabled",@"CheckBraceEnabled",@"CheckBracketEnabled",@"CheckSquareBracketEnabled",@"CheckParenEnabled",@"SyntaxColorEntryLine"]) {
    [notes removeAllObjects];[SUD setBool:![SUD boolForKey:key] forKey:key];
    [p applyPreferenceProfile:proposal font:nil];
    check([notes containsObject:[key isEqual:@"SyntaxColorEntryLine"] ? DocumentSyntaxColorNotification : @"NeedsForRecolorNotification"],"profile reflects every highlighting key");
  }
  NSUInteger copies=app.delegate.copies;
  [SUD setInteger:999 forKey:@"PdfCopyType"];[p applyPreferenceProfile:proposal font:nil];
  check(app.delegate.copies==copies+1,"profile reflects PDF copy menu");
  [notes removeAllObjects];
  [SUD setObject:@"round" forKey:@"DockIconStyle"];
  [SUD setBool:NO forKey:@"TeXAwareSpellChecking"];
  [SUD setObject:@"other" forKey:@"DefaultDarkTheme"];
  d=dock;sp=spell;c=colors;
  [p applyPreferenceProfile:proposal font:nil];
  check(dock==d+1 && spell==sp+1 && colors==c+1,"changed Dock/spelling/theme reflect once");
  check([notes containsObject:SourceColorChangedNotification],"theme notification uses actual saved themes");
  check(![notes containsObject:@"MagnificationChangedNotification"],"open PDFs keep their magnification");
  check([SUD objectForKey:@"DockIconStyle"]==nil,"Dock reset survives control refresh");
  [NSNotificationCenter.defaultCenter removeObserver:token];
 }
 puts("PASS: nine profile transactions, changed-only reflection, Dock reset, spelling invalidation and no PDF zoom broadcast");
}return 0;}
'''.replace('CONSTANTS','\n'.join(f'NSString *const {n}=@"{n}";' for n in names)).replace('BODY',body)
with tempfile.TemporaryDirectory(prefix='texshop-profile-live-') as td:
 t=Path(td);(t/'probe.m').write_text(program)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-deprecated-declarations','-I',str(ROOT/'Sources'),'-I',str(ROOT/'Tests'),'-framework','Cocoa',str(t/'probe.m'),str(ROOT/'Sources/TSPreferenceProfile.m'),'-o',str(t/'probe')],check=True)
 subprocess.run([str(t/'probe'),*map(str,sorted((ROOT/'Resources/Shellscripts').glob('*Defaults*.plist')))],check=True)
