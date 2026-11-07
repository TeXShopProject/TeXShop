#!/usr/bin/env python3
"""Exercise editing and teardown with inert UI doubles and memory defaults."""
from pathlib import Path
import subprocess,tempfile,sys
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'Sources/TSPreferences.m').read_text()
def method(sig):
 a=source.index('\n'+sig)+1;return source[a:source.index('\n}',a)+2]
names=['- (void)presentInputErrorForField:', '- (BOOL)commitPreferenceField:', '- (void)controlTextDidBeginEditing:', '- (BOOL)control:', '- (BOOL)finishPreferenceEditing:', '- (BOOL)windowShouldClose:', '- (void)windowWillClose:', '- (BOOL)tabView:', '- (void)releasePreferencePanels', '- (void)tearDownPreferenceEditing', '- (void)finishPreferencesForTermination', '- (void)cancelEnginePathDiscovery']
methods='\n'.join(map(method,names))
mutation=sys.argv[1] if len(sys.argv)>1 else ''
mutations={
 'persist':('BOOL changed = [value storeInDefaults:SUD forKey:rule.key];','BOOL changed = NO;'),
 'close-validation':('window != _prefsWindow || [self finishPreferenceEditing:YES]','YES'),
 'tab-validation':('if (![self finishPreferenceEditing:YES]) return NO;',';'),
 'generation':('self.enginePathSearchGeneration++;',';'),
 'font-ownership':('self.ownsFontPanel && manager.target == nil','YES'),
 'terminate-ui':('[self finishPreferenceEditing:NO];','[self finishPreferenceEditing:YES];'),
 'terminate-abort':('for (NSControl *field in self.inputRules) [field abortEditing];',';'),
 'restore-field':('field.stringValue = original;','field.stringValue = @"wrong";'),
}
if mutation:
 old,new=mutations[mutation];assert old in methods;methods=methods.replace(old,new)
methods=methods.replace('TSPreferences', 'Probe').replace('(NSWindow *)window', '(id)window').replace('NSFontManager *manager = [NSFontManager sharedFontManager]', 'FakeFontManager *manager = [FakeFontManager sharedFontManager]').replace('[NSAlert new]','[FakeAlert new]').replace('NSAlert *alert','FakeAlert *alert')
program=r'''
#import <Cocoa/Cocoa.h>
#import "MemoryDefaults.h"
#import "TSPreferenceInput.h"
static TSMemoryDefaults *memory;
#define SUD memory
@interface Editor : NSObject @property(copy) NSString *string; @end
@implementation Editor @end
@interface Field : NSObject
@property(copy) NSString *stringValue;
@property Editor *currentEditor;
@property NSUInteger aborts;
@property BOOL enabled;
- (void)abortEditing;
@end
@implementation Field
- (void)abortEditing {self.aborts++;self.currentEditor=nil;}
@end
@interface Window : NSObject
@property id attachedSheet;
@property BOOL isKeyWindow,isMainWindow;
@property NSUInteger resigns,closes;
- (BOOL)makeFirstResponder:(id)object;
- (void)close;
@end
@implementation Window
- (BOOL)makeFirstResponder:(id)object {self.resigns++;return YES;}
- (void)close {self.closes++;}
@end
@interface FakeFontManager : NSObject
@property id target;
@property Window *panel;
+ (instancetype)sharedFontManager;
- (Window *)fontPanel:(BOOL)create;
@end
@implementation FakeFontManager
+ (instancetype)sharedFontManager {static id manager; if(!manager)manager=[self new];return manager;}
- (Window *)fontPanel:(BOOL)create {if(create)abort();return self.panel;}
@end
static NSUInteger alerts;
@interface FakeAlert : NSObject
@property(copy) NSString *messageText,*informativeText;
@property(copy) void (^completion)(NSModalResponse);
- (void)addButtonWithTitle:(NSString *)title;
- (void)beginSheetModalForWindow:(id)window completionHandler:(void (^)(NSModalResponse))handler;
@end
static FakeAlert *shown;
@implementation FakeAlert
- (void)addButtonWithTitle:(NSString *)title {}
- (void)beginSheetModalForWindow:(id)window completionHandler:(void (^)(NSModalResponse))handler {alerts++;shown=self;self.completion=handler;}
@end
@interface Probe : NSObject <NSControlTextEditingDelegate> { @public Window *_prefsWindow; }
@property NSMapTable *inputRules;
@property id settingsController;
@property(copy) NSString *fontEditingContext;
@property(weak) NSControl *editingField;
@property(copy) NSString *editingOriginalText;
@property BOOL inputErrorPresented,ownsFontPanel,endingPreferences,initialEnginePathSearchPending;
@property NSUInteger enginePathSearchGeneration,colorTeardowns;
@property Field *enginePathSearchButton;
@end
@implementation Probe
- (void)endSession {}
- (void)deactivatePreferenceColorWells {self.colorTeardowns++;}
METHODS
@end
static void check(BOOL ok,const char *msg){if(!ok){fprintf(stderr,"FAIL: %s\n",msg);exit(1);}}
static Field *edit(Probe *p,NSString *key,NSString *value) {
 Field *field=[Field new];field.stringValue=[SUD stringForKey:key] ?: @"8";
 field.currentEditor=[Editor new];field.currentEditor.string=value;
 TSPreferenceInput *rule=[[TSPreferenceInput alloc]initWithKey:key kind:TSPreferenceInputInteger minimum:2 maximum:50 allowsEmpty:NO notification:@"FontUpdated"];
 [p.inputRules setObject:rule forKey:field];
 [p controlTextDidBeginEditing:[NSNotification notificationWithName:@"begin" object:field]];
 return field;
}
int main(void){@autoreleasepool{
 memory=[TSMemoryDefaults new]; [SUD setInteger:8 forKey:@"tabs"];
 Probe *p=[Probe new];p->_prefsWindow=[Window new];p.inputRules=[NSMapTable strongToStrongObjectsMapTable];
 __block NSUInteger changes=0;
 id token=[NSNotificationCenter.defaultCenter addObserverForName:@"FontUpdated" object:nil queue:nil usingBlock:^(NSNotification *n){changes++;}];
 Field *f=edit(p,@"tabs",@"20");
 check([p control:(id)f textShouldEndEditing:(id)f.currentEditor] && [SUD integerForKey:@"tabs"]==20 && changes==1,"focus commits exactly once");
 [p commitPreferenceField:(id)f showError:YES reflect:YES];check(changes==1,"Return action does not duplicate reflection");
 p->_prefsWindow.attachedSheet=[NSObject new];
 check(![p windowShouldClose:(id)p->_prefsWindow] && ![p tabView:nil shouldSelectTabViewItem:nil],"attached sheet blocks close and tab even with valid input");
 p->_prefsWindow.attachedSheet=nil;
 f.currentEditor.string=@"99";
 check([p windowShouldClose:(id)p->_prefsWindow] && [SUD integerForKey:@"tabs"]==50 && [f.stringValue isEqual:@"50"] && p->_prefsWindow.resigns==1,"close clamps saves and ends field editing");
 f.currentEditor.string=@"";
 check(![p windowShouldClose:(id)p->_prefsWindow] && [SUD integerForKey:@"tabs"]==50 && alerts==1,"invalid input cannot close or overwrite saved value");
 [p windowShouldClose:(id)p->_prefsWindow];check(alerts==1,"only one validation alert");
 shown.completion(NSAlertSecondButtonReturn);
 check([f.stringValue isEqual:@"50"] && [f.currentEditor.string isEqual:@"50"],"restore just the invalid field");
 f.currentEditor.string=@"bad";
 check(![p tabView:nil shouldSelectTabViewItem:nil],"invalid input prevents navigation");
 shown.completion(NSAlertFirstButtonReturn);
 check([f.currentEditor.string isEqual:@"bad"],"continue editing retains unfinished input");
 f.currentEditor.string=@"7";
 check([p tabView:nil shouldSelectTabViewItem:nil] && [SUD integerForKey:@"tabs"]==7 && p.colorTeardowns==1,"valid navigation commits and detaches panels");
 FakeFontManager *manager=[FakeFontManager sharedFontManager];manager.panel=[Window new];
 manager.target=[NSObject new];p.ownsFontPanel=YES;p->_prefsWindow.isMainWindow=YES;
 [p releasePreferencePanels];check(manager.panel.closes==0 && manager.target!=nil,"document-owned font panel untouched");
 manager.target=nil;p.ownsFontPanel=YES;p->_prefsWindow.isMainWindow=NO;p->_prefsWindow.isKeyWindow=NO;
 [p releasePreferencePanels];check(manager.panel.closes==0,"inactive settings never close document font panel");
 manager.target=nil;p.ownsFontPanel=YES;p->_prefsWindow.isMainWindow=YES;
 [p releasePreferencePanels];check(manager.panel.closes==1 && manager.target==nil,"only owned font session closed");
 p.initialEnginePathSearchPending=YES;p.enginePathSearchButton=[Field new];p.enginePathSearchButton.enabled=NO;
 [p windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:p->_prefsWindow]];
 check(p.enginePathSearchGeneration==1 && !p.initialEnginePathSearchPending && p.endingPreferences,"close invalidates asynchronous results");
 check([SUD integerForKey:@"tabs"]==7,"closing keeps saved values");
 [p tearDownPreferenceEditing];check(manager.panel.closes==1,"teardown is idempotent for owned panels");
 p.endingPreferences=NO;f.currentEditor.string=@"bad";
 Field *valid=edit(p,@"second",@"12");NSUInteger before=alerts, beforeChanges=changes, beforeResigns=p->_prefsWindow.resigns;
 [p finishPreferencesForTermination];
 check(alerts==before && [SUD integerForKey:@"tabs"]==7 && [SUD integerForKey:@"second"]==12,"termination commits only valid fields without UI");
 check(changes==beforeChanges && p->_prefsWindow.resigns==beforeResigns,"termination performs no reflection or responder transition");
 check(f.aborts==1 && valid.aborts==1 && p.endingPreferences,"termination discards active editors");
 [NSNotificationCenter.defaultCenter removeObserver:token];
 puts("PASS: input validation, Return/focus/close/navigation, local restore, owned panels, generation and no-UI termination");
}return 0;}
'''.replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='texshop-live-lifecycle-') as td:
 t=Path(td);(t/'probe.m').write_text(program)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I',str(ROOT/'Sources'),'-I',str(ROOT/'Tests'),'-framework','Cocoa',str(t/'probe.m'),str(ROOT/'Sources/TSPreferenceInput.m'),'-o',str(t/'probe')],check=True)
 subprocess.run([str(t/'probe')],check=True)
