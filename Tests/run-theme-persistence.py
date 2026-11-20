#!/usr/bin/env python3
"""Test production theme save/clone/selection actions using temporary files and inert controls."""
from pathlib import Path
import tempfile,subprocess,sys
from source_tree import include_args
R=Path(__file__).resolve().parents[1];source=(R/'Sources/Settings/TSPreferences-Color.m').read_text()
def method(sig):
 a=source.index('\n'+sig)+1;return source[a:source.index('\n}',a)+2]
methods='\n'.join(map(method,['- (IBAction)SaveEditedStyle:', '- (IBAction)themeSelectionChanged:', '- (void)themeListDidChooseTitle:', '- (void)loadEditingTheme', '- (void)themeListDidChangeTitle:', '- (void)fillThemeMenus', '- (void)setThemeEditingEnabled:']))
def line(sig):
 a=source.index('\n'+sig)+1;return source[a:source.index('\n',a)]
# The one-line methods and the function that composes the names stored in the settings.
methods=line('static NSString *TSThemeTitle(')+'\n'+methods+'\n'+line('- (nullable NSString *)lightThemeTitle')+'\n'+line('- (nullable NSString *)darkThemeTitle')
mutation=sys.argv[1] if len(sys.argv)>1 else ''
mutations={
 'failure-dictionary':('EditingColors = [saved mutableCopy];\n        self.lastSavedEditingColors = saved;\n        [self FillInColorWells];\n        [self showPreferenceError',';\n        self.lastSavedEditingColors = saved;\n        [self FillInColorWells];\n        [self showPreferenceError'),
 'failure-fallback':('[[self themeStore] readTitle:title] ?: self.lastSavedEditingColors','[[self themeStore] readTitle:title]'),
 'save-notify':('    [self applyEffectsForPreferenceKeys:[NSSet setWithArray:@[DefaultLiteThemeKey, DefaultDarkThemeKey]]];\n}\n- (IBAction)themeSelectionChanged',';\n}\n- (IBAction)themeSelectionChanged'),
 'selection-store':('[SUD setObject:title forKey:popup == LiteStyle ? DefaultLiteThemeKey : DefaultDarkThemeKey];',';'),
 'compose-settings':('{ return title.precomposedStringWithCanonicalMapping; }','{ return title; }'),
 'rename-follows':('[SUD setObject:newTitle ?: @"LiteTheme" forKey:DefaultLiteThemeKey];',';'),
 'delete-fallback':('newTitle ?: @"DarkTheme"','newTitle'),
 'rename-editing':('if ([self.editingThemeTitle isEqualToString:oldTitle] && newTitle != nil) self.editingThemeTitle = newTitle;',';'),
 'restore-reload':('if ([self.editingThemeTitle isEqualToString:oldTitle]) [self loadEditingTheme];',';'),
}
# Mutations of the theme file store: the whole edited dictionary written over the file, and the file read outside the
# coordinated write.
store=(R/'Sources/Settings/TSThemeFileStore.m').read_text()
store_mutations={
 'compose-titles':('NSString *title = name.stringByDeletingPathExtension.precomposedStringWithCanonicalMapping;','NSString *title = name.stringByDeletingPathExtension;'),
 'only-changed':('NSMutableDictionary<NSString *, id> *colors = [([self readTitle:title] ?: before) mutableCopy];','NSMutableDictionary<NSString *, id> *colors = [after mutableCopy];'),
 'read-outside':('    __block NSDictionary<NSString *, id> *written = nil;\n','    NSDictionary *early = [self readTitle:title];\n    __block NSDictionary<NSString *, id> *written = nil;\n'),
}
if mutation=='read-outside':
 store=store.replace(store_mutations[mutation][0],store_mutations[mutation][1]).replace('[([self readTitle:title] ?: before) mutableCopy]','[(early ?: before) mutableCopy]')
elif mutation in store_mutations:
 old,new=store_mutations[mutation];assert old in store;store=store.replace(old,new)
elif mutation:
 old,new=mutations[mutation];assert old in methods;methods=methods.replace(old,new)
methods=methods.replace('NSPopUpButton *popup', 'Popup *popup').replace('for (NSPopUpButton *popup in @[LiteStyle, DarkStyle])','for (Popup *popup in @[LiteStyle, DarkStyle])')
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
- (void)removeAllItems;
- (void)addItemsWithTitles:(NSArray<NSString *> *)titles;
@end
@implementation Popup
- (instancetype)init {if((self=[super init]))_items=[NSMutableArray new];return self;}
- (id)itemWithTitle:(NSString *)title{return [self.items containsObject:title]?title:nil;}
- (void)addItemWithTitle:(NSString *)title{[self.items addObject:title];}
- (void)selectItemWithTitle:(NSString *)title{self.titleOfSelectedItem=[self.items containsObject:title]?title:nil;}
- (void)removeAllItems{[self.items removeAllObjects];self.titleOfSelectedItem=nil;}
- (void)addItemsWithTitles:(NSArray<NSString *> *)titles{for(NSString *t in titles)if(![self.items containsObject:t])[self.items addObject:t];}
@end
static NSString *ColorPath;
// A theme store that runs a block once, right after it has read a theme file.
@interface HookStore:TSThemeFileStore
@property(copy) void (^afterRead)(void);
@end
@implementation HookStore
- (NSDictionary *)readTitle:(NSString *)title {NSDictionary *colors=[super readTitle:title];void (^hook)(void)=self.afterRead;self.afterRead=nil;if(hook)hook();return colors;}
@end
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
static NSString *alertMessage;
static NSMutableArray *alertButtons;
@interface FakeAlert:NSObject
@property(copy) NSString *messageText;
- (NSButton *)addButtonWithTitle:(NSString *)title;
- (void)beginSheetModalForWindow:(FakePanel *)parent completionHandler:(void (^)(NSModalResponse))handler;
@end
@implementation FakeAlert
- (instancetype)init { if ((self=[super init])) alertButtons=[NSMutableArray new]; return self; }
- (NSButton *)addButtonWithTitle:(NSString *)title { [alertButtons addObject:title]; return [NSButton new]; }
- (void)beginSheetModalForWindow:(FakePanel *)parent completionHandler:(void (^)(NSModalResponse))handler { alertMessage=[self.messageText copy];alertCompletion=[handler copy]; }
@end
#define NSAlert FakeAlert
@interface Field:NSObject
@property(copy) NSString *stringValue;
@end
@implementation Field @end
@interface ListStub:NSObject
@property NSUInteger reloads;
- (void)reload;
@end
@implementation ListStub
- (void)reload{self.reloads++;}
@end
@interface Probe:NSObject { @public NSMutableDictionary *EditingColors; Popup *LiteStyle,*DarkStyle; FakePanel *_prefsWindow; }
@property(copy) NSDictionary *lastSavedEditingColors;
@property(copy) NSString *editingThemeTitle;
@property ListStub *themeList;
@property TSThemeFileStore *store;
@property NSUInteger errors,fills;
@end
@implementation Probe
- (TSThemeFileStore *)themeStore{return self.store;}
- (void)showPreferenceError:(NSString *)message{self.errors++;}
- (void)FillInColorWells{self.fills++;}
// The file test observes the coordinator boundary; SettingsOwnerEffects tests
// the complete production preparation and notification dispatcher independently.
- (void)applyEffectsForPreferenceKeys:(NSSet<NSString *> *)keys {
    if (![keys isEqualToSet:[NSSet setWithArray:@[DefaultLiteThemeKey, DefaultDarkThemeKey]]]) abort();
    [[TSColorSupport sharedInstance] initializeColors];
    [NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:self];
}
METHODS
@end
static void check(BOOL ok,const char *why){if(!ok){fprintf(stderr,"FAIL: %s\n",why);exit(1);}}
static NSData *plist(NSDictionary *d){return [NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();memory=[TSMemoryDefaults new];Probe *p=[Probe new];
 NSURL *root=[NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
 p.store=[[TSThemeFileStore alloc]initWithDirectory:root];ColorPath=root.path;p->_prefsWindow=[FakePanel new];
 NSDictionary *original=@{@"Title":@"Original",@"EditorText":@[@0.1,@0.2,@0.3,@1]};
 check([p.store writeColors:original title:@"Original" error:NULL],"seed file");
 p->LiteStyle=[Popup new];p->DarkStyle=[Popup new];
 [p themeListDidChooseTitle:@"Original"];check([p.editingThemeTitle isEqual:@"Original"] && [p->EditingColors isEqual:original] && reloads==0,"choosing the theme to edit does not apply it to documents");
 __block NSUInteger notifications=0;
 id token=[NSNotificationCenter.defaultCenter addObserverForName:SourceColorChangedNotification object:p queue:nil usingBlock:^(NSNotification *n){notifications++;check(n.userInfo==nil,"document notifications have no transient editing dictionary");}];
 p->EditingColors[@"EditorText"]=@[@0.8,@0.7,@0.6,@1];
 [p SaveEditedStyle:nil];
 NSDictionary *saved=[p.store readTitle:@"Original"];
 check([saved isEqual:p->EditingColors] && [saved isEqual:p.lastSavedEditingColors] && notifications==1 && reloads==1,"save disk before refreshing documents");
 // Another TeXShop (or the one-time update of the bundled colors) changes another color of the file: a change here
 // writes only its own color, keeps the other one, and the wells show it.
 NSMutableDictionary *elsewhere=[saved mutableCopy];elsewhere[@"EditorBackground"]=@[@0.5,@0.5,@0.5,@1];
 check([p.store writeColors:elsewhere title:@"Original" error:NULL],"another TeXShop writes the theme");
 NSUInteger fills=p.fills;
 p->EditingColors[@"EditorText"]=@[@0.7,@0.6,@0.5,@1];
 [p SaveEditedStyle:nil];
 saved=[p.store readTitle:@"Original"];
 check([saved[@"EditorText"] isEqual:(@[@0.7,@0.6,@0.5,@1])] && [saved[@"EditorBackground"] isEqual:elsewhere[@"EditorBackground"]],"a color change keeps a color changed elsewhere in the file");
 check([saved isEqual:p->EditingColors] && [saved isEqual:p.lastSavedEditingColors] && p.fills==fills+1 && notifications==2 && reloads==2,"the wells show the color changed elsewhere");
 p->EditingColors[@"EditorText"]=@[@0.8,@0.7,@0.6,@1];
 [p SaveEditedStyle:nil];
 saved=[p.store readTitle:@"Original"];
 check([saved isEqual:p->EditingColors] && [saved[@"EditorText"] isEqual:(@[@0.8,@0.7,@0.6,@1])] && p.fills==fills+1 && notifications==3,"the wells are not filled again when nothing changed elsewhere");
 // Two saves at once, of different colors of the same file: B saves its background while A has just read the file to
 // save its text color. Both colors stay.
 {
  Probe *a=[Probe new],*b=[Probe new];
  HookStore *hooked=[[HookStore alloc]initWithDirectory:root];a.store=hooked;b.store=[[TSThemeFileStore alloc]initWithDirectory:root];
  for(Probe *x in @[a,b]){x->_prefsWindow=[FakePanel new];[x themeListDidChooseTitle:@"Original"];}
  a->EditingColors[@"EditorText"]=@[@1,@1,@1,@1];
  b->EditingColors[@"EditorBackground"]=@[@0,@0,@0,@1];
  dispatch_group_t group=dispatch_group_create();
  hooked.afterRead=^{
   dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[b SaveEditedStyle:nil];});
   [NSThread sleepForTimeInterval:0.4];
  };
  [a SaveEditedStyle:nil];
  check(dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(10*NSEC_PER_SEC)))==0,"the other save ends");
  NSDictionary *both=[p.store readTitle:@"Original"];
  check([both[@"EditorText"] isEqual:(@[@1,@1,@1,@1])] && [both[@"EditorBackground"] isEqual:(@[@0,@0,@0,@1])] && a.errors==0 && b.errors==0,"two saves of different colors at once keep both");
  check([a->EditingColors[@"EditorText"] isEqual:(@[@1,@1,@1,@1])] && [b->EditingColors isEqual:both] && [b.lastSavedEditingColors isEqual:both],"each save keeps what it wrote as its last saved colors");
  [p.store writeColors:saved title:@"Original" error:NULL];
 }
 NSUInteger reloadsBeforeFailure=reloads;
 NSURL *file=[root URLByAppendingPathComponent:@"Original.plist"];
 check([NSFileManager.defaultManager removeItemAtURL:file error:NULL],"remove fixture");
 check([NSFileManager.defaultManager createDirectoryAtURL:file withIntermediateDirectories:NO attributes:nil error:NULL],"force write and reload failure");
 p->EditingColors[@"EditorText"]=@[@0.9,@0.9,@0.9,@1];
 [p SaveEditedStyle:nil];
 check(p.errors==1 && [p->EditingColors isEqual:saved] && notifications==3 && reloads==reloadsBeforeFailure,"failed save restores last successful dictionary without applying it");
 [NSFileManager.defaultManager removeItemAtURL:file error:NULL];
 check([p.store writeColors:saved title:@"Original" error:NULL],"restore fixture");

 // The theme list's file operations (TSThemeFileStore).
 for(NSString *t in @[@"Light",@"Dark",@"theme 10",@"theme 9"])check([p.store writeColors:@{@"EditorText":@[@0,@0,@0,@1]} title:t error:NULL],"seed themes");
 NSArray *titles=[p.store titles];
 check([titles isEqual:(@[@"Dark",@"Light",@"Original",@"theme 9",@"theme 10"])],"themes are listed in Finder order");
 check([[p.store availableTitleForTitle:@"light"] isEqual:@"light 2"] && [[p.store availableTitleForTitle:@"New"] isEqual:@"New"],"a free title ignores case and numbers from 2");
 NSError *error=nil;
 check(![p.store renameTitle:@"theme 9" to:@"DARK" error:&error] && error.code==NSFileWriteFileExistsError && [p.store readTitle:@"theme 9"]!=nil,"renaming never replaces another theme");
 check(![p.store renameTitle:@"theme 9" to:@"a/b" error:&error] && error.code==NSFileWriteInvalidFileNameError,"a title with a path separator is refused");
 check([p.store renameTitle:@"theme 9" to:@"Nine" error:NULL] && [[p.store readTitle:@"Nine"][@"Title"] isEqual:@"Nine"] && [p.store readTitle:@"theme 9"]==nil,"renaming moves the file and the title inside it");
 check([p.store renameTitle:@"Nine" to:@"NINE" error:NULL] && [[p.store titles] containsObject:@"NINE"] && ![[p.store titles] containsObject:@"Nine"],"a change of case only renames");
 NSURL *outside=[[root URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"out" isDirectory:YES];
 [NSFileManager.defaultManager createDirectoryAtURL:outside withIntermediateDirectories:YES attributes:nil error:NULL];
 NSURL *exported=[outside URLByAppendingPathComponent:@"Original.plist"];
 check([p.store exportTitle:@"Original" toURL:exported error:NULL] && [[NSData dataWithContentsOfURL:exported] isEqual:[NSData dataWithContentsOfURL:[p.store URLForTitle:@"Original"]]],"export copies the file as it is");
 BOOL (^accept)(NSData *)=^BOOL(NSData *d){return YES;};
 NSString *imported=[p.store importFileAtURL:exported check:accept error:NULL];
 check([imported isEqual:@"Original 2"] && [[p.store readTitle:@"Original 2"][@"EditorText"] isEqual:[p.store readTitle:@"Original"][@"EditorText"]] && [[p.store readTitle:@"Original 2"][@"Title"] isEqual:@"Original 2"],"an imported theme with a taken name gets a free one");
 NSURL *junk=[outside URLByAppendingPathComponent:@"Junk.plist"];[plist(@{@"EditorText":@"red"}) writeToURL:junk atomically:YES];
 check([p.store importFileAtURL:junk check:^BOOL(NSData *d){return NO;} error:&error]==nil && error.code==NSFileReadCorruptFileError && [p.store readTitle:@"Junk"]==nil,"a file the check refuses is not imported");
 NSURL *array=[outside URLByAppendingPathComponent:@"Array.plist"];[[NSPropertyListSerialization dataWithPropertyList:@[@1] format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL] writeToURL:array atomically:YES];
 check([p.store importFileAtURL:array check:accept error:&error]==nil && [p.store readTitle:@"Array"]==nil,"a property list that is not a dictionary is not imported");

 // The list tells Settings of a renamed or deleted theme: Light and Dark Mode follow a rename and fall back to TeXShop's
 // own themes when theirs is deleted; restored colors are shown again.
 [SUD setObject:@"Light" forKey:DefaultLiteThemeKey];[SUD setObject:@"Dark" forKey:DefaultDarkThemeKey];
 [p themeListDidChooseTitle:@"Light"];
 check([p.store renameTitle:@"Light" to:@"Bright" error:NULL],"rename the light theme");
 NSUInteger before=reloads;
 [p themeListDidChangeTitle:@"Light" to:@"Bright"];
 check([[SUD stringForKey:DefaultLiteThemeKey] isEqual:@"Bright"] && [p.editingThemeTitle isEqual:@"Bright"] && [p->LiteStyle.titleOfSelectedItem isEqual:@"Bright"] && ![p->LiteStyle.items containsObject:@"Light"] && reloads==before+1,"Light Mode follows its renamed theme and documents are recolored");
 [NSFileManager.defaultManager removeItemAtURL:[p.store URLForTitle:@"Dark"] error:NULL];
 [p themeListDidChangeTitle:@"Dark" to:nil];
 check([[SUD stringForKey:DefaultDarkThemeKey] isEqual:@"DarkTheme"] && [[SUD stringForKey:DefaultLiteThemeKey] isEqual:@"Bright"] && reloads==before+2,"Dark Mode gives way to DarkTheme when its theme is deleted");
 before=reloads;[p themeListDidChangeTitle:@"NINE" to:@"Nine"];
 check(reloads==before,"renaming a theme in use by neither mode does not recolor documents");
 NSUInteger fillsBefore=p.fills;NSMutableDictionary *bright=[[p.store readTitle:@"Bright"] mutableCopy];bright[@"EditorText"]=@[@1,@0,@0,@1];[p.store writeColors:bright title:@"Bright" error:NULL];
 [p themeListDidChangeTitle:@"Bright" to:@"Bright"];
 check([p->EditingColors[@"EditorText"] isEqual:(@[@1,@0,@0,@1])] && p.fills==fillsBefore+1 && reloads==before+1,"restored colors of the theme being edited are shown and applied");

 // Names come composed from the folder, and a name an earlier version stored decomposed still follows a rename.
 NSString *nfc=@"\u30d1\u30d1",*nfd=nfc.decomposedStringWithCanonicalMapping;
 [plist(@{@"EditorText":@[@0,@0,@0,@1]}) writeToURL:[root URLByAppendingPathComponent:[nfd stringByAppendingString:@".plist"]] atomically:YES];
 check([[p.store titles] containsObject:nfc] && ![[p.store titles] containsObject:nfd] && [p.store readTitle:nfc]!=nil,"a decomposed file name is listed composed");
 [SUD setObject:nfd forKey:DefaultLiteThemeKey];
 check([p.store renameTitle:nfc to:@"Papa" error:NULL],"rename the decomposed theme");
 [p themeListDidChangeTitle:nfc to:@"Papa"];
 check([[SUD stringForKey:DefaultLiteThemeKey] isEqual:@"Papa"],"a decomposed stored name follows the rename");
 [SUD setObject:@"Bright" forKey:DefaultLiteThemeKey];
 NSUInteger count=notifications,reloaded=reloads;
 p.themeList=[ListStub new];
 p->DarkStyle.titleOfSelectedItem=nil;[SUD setObject:@"Missing" forKey:DefaultDarkThemeKey];
 p->LiteStyle.titleOfSelectedItem=@"Original";
 [p themeSelectionChanged:p->LiteStyle];
 check([[SUD stringForKey:DefaultLiteThemeKey] isEqual:@"Original"] && [[SUD stringForKey:DefaultDarkThemeKey] isEqual:@"Missing"] && notifications==count+1 && reloads==reloaded+1 && p.themeList.reloads==1,"valid popup persists, reloads despite missing other theme, and the list shows it");
 p->DarkStyle.titleOfSelectedItem=@"Bright";[p themeSelectionChanged:p->DarkStyle];
 check([[SUD stringForKey:DefaultDarkThemeKey] isEqual:@"Bright"] && reloads==reloaded+2,"dark popup persists independently");
 NSView *view=[[NSView alloc]initWithFrame:NSZeroRect];
 NSColorWell *theme=[[NSColorWell alloc]initWithFrame:NSZeroRect],*cursor=[[NSColorWell alloc]initWithFrame:NSZeroRect];
 cursor.action=@selector(BlockCursorColorChanged:);[view addSubview:theme];[view addSubview:cursor];
 [p setThemeEditingEnabled:NO inView:view];check(!theme.enabled && cursor.enabled,"unreadable theme does not disable cursor color");
 [NSNotificationCenter.defaultCenter removeObserver:token];
 puts("PASS: theme selection, save failure, last-success fallback, the theme list's file operations, and renamed or deleted themes in use");
}return 0;}
'''.replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='texshop-theme-persistence-') as td:
 t=Path(td);(t/'probe.m').write_text(program);(t/'TSThemeFileStore.m').write_text(store);(t/'Colors').mkdir()
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-deprecated-declarations',*include_args(R),'-I',str(R/'Tests'),'-framework','Cocoa',str(t/'probe.m'),str(t/'TSThemeFileStore.m'),'-o',str(t/'probe')],check=True)
 subprocess.run([str(t/'probe'),str(t/'Colors')],check=True,timeout=60)
