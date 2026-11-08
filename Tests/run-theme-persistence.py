#!/usr/bin/env python3
"""Test production theme save/clone/selection actions using temporary files and inert controls."""
from pathlib import Path
import tempfile,subprocess,sys
R=Path(__file__).resolve().parents[1];source=(R/'Sources/TSPreferences-Color.m').read_text()
def method(sig):
 a=source.index('\n'+sig)+1;return source[a:source.index('\n}',a)+2]
methods='\n'.join(map(method,['- (IBAction)SaveEditedStyle:', '- (void)saveNewTheme:', '- (IBAction)themeSelectionChanged:', '- (IBAction)EditingStyleChoice:', '- (IBAction)SaveNewStyle:', '- (void)requestNameForThemeColors:', '- (void)okForStylePanel:', '- (void)cancelForStylePanel:', '- (void)setThemeEditingEnabled:']))
mutation=sys.argv[1] if len(sys.argv)>1 else ''
mutations={
 'sheet-generation':('generation != self.themeOperationGeneration','NO'),
 'overwrite-generation':('answer == NSAlertFirstButtonReturn && generation == self.themeOperationGeneration','answer == NSAlertFirstButtonReturn'),
 'sheet-cancel':('response != NSModalResponseOK ||','NO ||'),
 'failure-dictionary':('EditingColors = [saved mutableCopy];',';'),
 'failure-fallback':('[[self themeStore] readTitle:title] ?: self.lastSavedEditingColors','[[self themeStore] readTitle:title]'),
 'save-notify':('[NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:self];',';'),
 'clone-early':('if (![[self themeStore] writeColors:colors title:title error:&error]) {','if (NO && ![[self themeStore] writeColors:colors title:title error:&error]) {'),
 'selection-store':('[SUD setObject:title forKey:popup == LiteStyle ? DefaultLiteThemeKey : DefaultDarkThemeKey];',';'),
}
if mutation:
 old,new=mutations[mutation];assert old in methods;methods=methods.replace(old,new)
methods=methods.replace('NSPopUpButton *popup', 'Popup *popup')
program=r'''
#import <Cocoa/Cocoa.h>
#import "MemoryDefaults.h"
#import "TestAppKitIsolation.h"
#import "TSThemeFileStore.h"
static TSMemoryDefaults *memory;
#define SUD memory
static NSString *DefaultLiteThemeKey=@"DefaultLiteTheme",*DefaultDarkThemeKey=@"DefaultDarkTheme",*SourceColorChangedNotification=@"ColorsChanged";
static NSUInteger reloads;
@interface TSColorSupport:NSObject @end
@implementation TSColorSupport
+ (id)sharedInstance {static id instance;if(!instance)instance=[self new];return instance;}
- (void)initializeColors {reloads++;}
@end
@interface Popup:NSObject
@property NSMutableArray<NSString *> *items;
@property(copy) NSString *titleOfSelectedItem;
- (id)itemWithTitle:(NSString *)title;
- (void)addItemWithTitle:(NSString *)title;
- (void)selectItemWithTitle:(NSString *)title;
@end
@implementation Popup
- (instancetype)init {if((self=[super init]))_items=[NSMutableArray new];return self;}
- (id)itemWithTitle:(NSString *)title{return [self.items containsObject:title]?title:nil;}
- (void)addItemWithTitle:(NSString *)title{[self.items addObject:title];}
- (void)selectItemWithTitle:(NSString *)title{self.titleOfSelectedItem=title;}
@end
static NSString *ColorPath;
@interface FakePanel:NSObject
@property FakePanel *attachedSheet;
@property FakePanel *sheetParent;
@property NSView *contentView;
@property(copy) void (^completion)(NSModalResponse);
- (void)beginSheet:(FakePanel *)sheet completionHandler:(void (^)(NSModalResponse))handler;
- (void)endSheet:(FakePanel *)sheet returnCode:(NSModalResponse)response;
- (void)setContentSize:(NSSize)size;
@end
@implementation FakePanel
- (void)beginSheet:(FakePanel *)sheet completionHandler:(void (^)(NSModalResponse))handler { self.attachedSheet=sheet;sheet.sheetParent=self;self.completion=handler; }
- (void)endSheet:(FakePanel *)sheet returnCode:(NSModalResponse)response { void (^done)(NSModalResponse)=self.completion;self.completion=nil;self.attachedSheet=nil;sheet.sheetParent=nil;if(done)done(response); }
- (void)setContentSize:(NSSize)size {}
@end
static void (^alertCompletion)(NSModalResponse);
@interface FakeAlert:NSObject
@property(copy) NSString *messageText;
- (void)addButtonWithTitle:(NSString *)title;
- (void)beginSheetModalForWindow:(FakePanel *)parent completionHandler:(void (^)(NSModalResponse))handler;
@end
@implementation FakeAlert
- (void)addButtonWithTitle:(NSString *)title {}
- (void)beginSheetModalForWindow:(FakePanel *)parent completionHandler:(void (^)(NSModalResponse))handler { alertCompletion=[handler copy]; }
@end
#define NSAlert FakeAlert
@interface Field:NSObject
@property(copy) NSString *stringValue;
@end
@implementation Field @end
@interface Probe:NSObject { @public NSMutableDictionary *EditingColors; Popup *EditingStyle,*LiteStyle,*DarkStyle; Field *styleTitle; FakePanel *stylePanel,*_prefsWindow; }
@property(copy) NSDictionary *lastSavedEditingColors;
@property NSUInteger themeOperationGeneration;
@property TSThemeFileStore *store;
@property NSUInteger errors,fills;
@end
@implementation Probe
- (TSThemeFileStore *)themeStore{return self.store;}
- (void)showPreferenceError:(NSString *)message{self.errors++;}
- (void)FillInColorWells{self.fills++;}
METHODS
@end
static void check(BOOL ok,const char *why){if(!ok){fprintf(stderr,"FAIL: %s\n",why);exit(1);}}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();memory=[TSMemoryDefaults new];Probe *p=[Probe new];
 NSURL *root=[NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
 p.store=[[TSThemeFileStore alloc]initWithDirectory:root];ColorPath=root.path;p->_prefsWindow=[FakePanel new];p->stylePanel=[FakePanel new];p->styleTitle=[Field new];
 NSDictionary *original=@{@"Title":@"Original",@"EditorText":@[@0.1,@0.2,@0.3,@1]};
 check([p.store writeColors:original title:@"Original" error:NULL],"seed file");
 p->EditingStyle=[Popup new];p->LiteStyle=[Popup new];p->DarkStyle=[Popup new];
 p->EditingStyle.titleOfSelectedItem=@"Original";p->LiteStyle.titleOfSelectedItem=@"Light";p->DarkStyle.titleOfSelectedItem=@"Dark";
 [p EditingStyleChoice:nil];check([p->EditingColors isEqual:original] && reloads==0,"selecting editing theme does not apply it to documents");
 __block NSUInteger notifications=0;
 id token=[NSNotificationCenter.defaultCenter addObserverForName:SourceColorChangedNotification object:p queue:nil usingBlock:^(NSNotification *n){notifications++;check(n.userInfo==nil,"document notifications have no transient editing dictionary");}];
 p->EditingColors[@"EditorText"]=@[@0.8,@0.7,@0.6,@1];
 [p SaveEditedStyle:nil];
 NSDictionary *saved=[p.store readTitle:@"Original"];
 check([saved isEqual:p->EditingColors] && [saved isEqual:p.lastSavedEditingColors] && notifications==1 && reloads==1,"save disk before refreshing documents");
 NSURL *file=[root URLByAppendingPathComponent:@"Original.plist"];
 check([NSFileManager.defaultManager removeItemAtURL:file error:NULL],"remove fixture");
 check([NSFileManager.defaultManager createDirectoryAtURL:file withIntermediateDirectories:NO attributes:nil error:NULL],"force write and reload failure");
 p->EditingColors[@"EditorText"]=@[@0.9,@0.9,@0.9,@1];
 [p SaveEditedStyle:nil];
 check(p.errors==1 && [p->EditingColors isEqual:saved] && notifications==1 && reloads==1,"failed save restores last successful dictionary without applying it");
 p->EditingColors[@"EditorText"]=@[@0.4,@0.4,@0.4,@1];
 [p SaveNewStyle:nil];
 check(p->_prefsWindow.attachedSheet==p->stylePanel && [p->styleTitle.stringValue isEqual:@""],"clone uses a cleared name sheet");
 p->styleTitle.stringValue=@"Clone";
 [p okForStylePanel:nil];
 check([[[p.store readTitle:@"Clone"] objectForKey:@"EditorText"] isEqual:saved[@"EditorText"]],"clone after failed save excludes unsaved colors");
 check([p->EditingStyle.titleOfSelectedItem isEqual:@"Clone"] && [p->LiteStyle.items containsObject:@"Clone"],"successful clone updates all lists and editing selection");
 NSDictionary *before=[p->EditingColors copy];NSArray *items=[p->LiteStyle.items copy];
 [p saveNewTheme:p.lastSavedEditingColors title:@"Original"];
 check(p.errors==2 && [p->EditingColors isEqual:before] && [p->EditingStyle.titleOfSelectedItem isEqual:@"Clone"] && [items isEqual:p->LiteStyle.items],"failed clone leaves original dictionary and lists intact");

 NSUInteger errors=p.errors; NSDictionary *clone=[p.store readTitle:@"Clone"];
 [p SaveNewStyle:nil];p->styleTitle.stringValue=@"Cancelled";[p cancelForStylePanel:nil];
 check([p.store readTitle:@"Cancelled"]==nil,"cancel creates no file");
 [p SaveNewStyle:nil];p->styleTitle.stringValue=@"../Bad";[p okForStylePanel:nil];
 check(p.errors==errors+1,"invalid title rejected before saving");
 [p SaveNewStyle:nil];p->styleTitle.stringValue=@"Clone";[p okForStylePanel:nil];
 check(alertCompletion!=nil,"collision asks on a sheet");alertCompletion(NSAlertSecondButtonReturn);alertCompletion=nil;
 check([[p.store readTitle:@"Clone"] isEqual:clone],"overwrite cancellation leaves disk intact");
 NSDictionary *replacement=@{@"Title":@"Snapshot",@"EditorText":@[@0.2,@0.5,@0.8,@1]};
 p.lastSavedEditingColors=replacement;[p SaveNewStyle:nil];p.lastSavedEditingColors=clone;
 p->styleTitle.stringValue=@"Snapshot";[p okForStylePanel:nil];
 check([[[p.store readTitle:@"Snapshot"] objectForKey:@"EditorText"] isEqual:replacement[@"EditorText"]],"in-flight clone keeps the captured saved colors");
 [p SaveNewStyle:nil];p->styleTitle.stringValue=@"Clone";[p okForStylePanel:nil];
 check(alertCompletion!=nil,"overwrite awaits confirmation");p.themeOperationGeneration++;
 alertCompletion(NSAlertFirstButtonReturn);alertCompletion=nil;
 check([[p.store readTitle:@"Clone"] isEqual:clone],"late overwrite after teardown does not save");
 [p SaveNewStyle:nil];p->styleTitle.stringValue=@"Late";p.themeOperationGeneration++;[p okForStylePanel:nil];
 check([p.store readTitle:@"Late"]==nil,"late name completion after teardown does not save");
 [p SaveNewStyle:nil];p->styleTitle.stringValue=@"Clone";[p okForStylePanel:nil];
 alertCompletion(NSAlertFirstButtonReturn);alertCompletion=nil;
 check([[[p.store readTitle:@"Clone"] objectForKey:@"EditorText"] isEqual:replacement[@"EditorText"]],"confirmed overwrite saves the snapshot");
 NSUInteger count=notifications,reloaded=reloads;
 p->DarkStyle.titleOfSelectedItem=nil;[SUD setObject:@"Missing" forKey:DefaultDarkThemeKey];
 [p themeSelectionChanged:p->LiteStyle];
 check([[SUD stringForKey:DefaultLiteThemeKey] isEqual:@"Light"] && [[SUD stringForKey:DefaultDarkThemeKey] isEqual:@"Missing"] && notifications==count+1 && reloads==reloaded+1,"valid popup persists and reloads despite missing other theme");
 p->DarkStyle.titleOfSelectedItem=@"Dark";[p themeSelectionChanged:p->DarkStyle];
 check([[SUD stringForKey:DefaultDarkThemeKey] isEqual:@"Dark"] && reloads==reloaded+2,"dark popup persists independently");
 NSView *view=[[NSView alloc]initWithFrame:NSZeroRect];
 NSColorWell *theme=[[NSColorWell alloc]initWithFrame:NSZeroRect],*cursor=[[NSColorWell alloc]initWithFrame:NSZeroRect];
 cursor.action=@selector(BlockCursorColorChanged:);[view addSubview:theme];[view addSubview:cursor];
 [p setThemeEditingEnabled:NO inView:view];check(!theme.enabled && cursor.enabled,"unreadable theme does not disable cursor color");
 [NSNotificationCenter.defaultCenter removeObserver:token];
 puts("PASS: theme selection, save failure, last-success fallback, clone after failure and unchanged failed-clone UI");
}return 0;}
'''.replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='texshop-theme-persistence-') as td:
 t=Path(td);(t/'probe.m').write_text(program);(t/'Colors').mkdir()
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-deprecated-declarations','-I',str(R/'Sources'),'-I',str(R/'Tests'),'-framework','Cocoa',str(t/'probe.m'),str(R/'Sources/TSThemeFileStore.m'),'-o',str(t/'probe')],check=True)
 subprocess.run([str(t/'probe'),str(t/'Colors')],check=True,timeout=60)
