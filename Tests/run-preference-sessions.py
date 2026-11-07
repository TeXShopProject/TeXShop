#!/usr/bin/env python3
"""Exercise production input rules, font ownership, reopening, and profile entry with inert UI."""
from pathlib import Path
import re, subprocess, tempfile
R=Path(__file__).resolve().parents[1]
s=(R/'Sources/TSPreferences.m').read_text()
def method(sig):
 a=s.index('\n'+sig)+1;return s[a:s.index('\n}',a)+2]
methods='\n'.join(method(sig) for sig in ['- (void)addPreferenceField:', '- (void)configurePreferenceInputs', '- (IBAction)showPreferences:', '- (IBAction)setDefaults:', '- (IBAction)changeDocumentFont:', '- (IBAction)changeConsoleFont:', '- (void)changeFont:'])
methods=methods.replace('TSPreferences *','Probe *').replace('NSFontManager sharedFontManager','FontManager sharedFontManager').replace('[NSAlert new]','[Alert new]').replace('NSBundle.mainBundle', 'Bundle.mainBundle').replace('NSAlert *alert','Alert *alert')
fields=re.findall(r'\[self addPreferenceField:(\w+) rule:',method('- (void)configurePreferenceInputs'))
keys=re.findall(r'initWithKey:(\w+)',method('- (void)configurePreferenceInputs'))
constants=keys+['DocumentFontKey','SaveDocumentFontKey','ConsoleFontNameKey','ConsoleFontSizeKey','ConsoleFontChangedNotification','DocumentFontChangedNotification']
constants=list(dict.fromkeys(constants))
program=r'''
#import <Cocoa/Cocoa.h>
#import "MemoryDefaults.h"
#import "TSPreferenceInput.h"
#import "TSPreferenceProfile.h"
#import "TestAppKitIsolation.h"
static TSMemoryDefaults *memory;
#define SUD memory
CONSTANTS
@interface Window:NSObject
@property BOOL visible,isKeyWindow,isMainWindow;
@property id delegate;
@property NSUInteger fronts;
- (void)makeKeyAndOrderFront:(id)sender;
- (BOOL)makeFirstResponder:(id)sender;
@end
@implementation Window
- (void)makeKeyAndOrderFront:(id)sender {self.fronts++;}
- (BOOL)makeFirstResponder:(id)sender {return YES;}
@end
@interface Tab:NSObject
@property id delegate;
@property(copy) NSString *identifier;
- (id)selectedTabViewItem;
@end
@implementation Tab
- (id)selectedTabViewItem {return self;}
@end
@interface Field:NSObject
@property id formatter;
@end
@implementation Field @end
@interface FontManager:NSObject
@property id target;
@property NSUInteger fronts,conversions;
+ (instancetype)sharedFontManager;
- (NSFont *)convertFont:(NSFont *)font;
- (void)setSelectedFont:(NSFont *)font isMultiple:(BOOL)multiple;
- (void)orderFrontFontPanel:(id)sender;
@end
@implementation FontManager
+ (instancetype)sharedFontManager {static id x;if(!x)x=[self new];return x;}
- (NSFont *)convertFont:(NSFont *)font {self.conversions++;return font;}
- (void)setSelectedFont:(NSFont *)font isMultiple:(BOOL)multiple {}
- (void)orderFrontFontPanel:(id)sender {self.fronts++;}
@end
@interface NSObject (SettingsTest)
- (id)legacyViewForCategoryIdentifier:(NSString *)identifier;
@end
@interface TSDockIconController:NSObject @end
@implementation TSDockIconController
+ (id)sharedController {static id x;if(!x)x=[self new];return x;}
- (void)installInPreferencesPane:(id)pane {}
- (void)restoreSavedIcon {}
@end
static NSUInteger resourceLookups, confirmations;
@interface TSPreferenceProfile (FactoryTest)
- (instancetype)checkedProfile:(NSDictionary *)p documentFont:(NSData *)f registeredDefaults:(NSDictionary *)d;
@end
@implementation TSPreferenceProfile (FactoryTest)
- (instancetype)checkedProfile:(NSDictionary *)p documentFont:(NSData *)f registeredDefaults:(NSDictionary *)d {
 if(d.count<100 || !d[@"TetexBinPath"]) {fprintf(stderr,"FAIL: full factory defaults supplied\n");exit(1);}
 return [self checkedProfile:p documentFont:f registeredDefaults:d];
}
@end
static NSString *resources;
@interface Bundle:NSObject @end
@implementation Bundle
+ (id)mainBundle {static id x;if(!x)x=[self new];return x;}
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)ext {resourceLookups++;return [NSURL fileURLWithPath:[resources stringByAppendingPathComponent:[name stringByAppendingPathExtension:ext]]];}
@end
@interface Button:NSObject
@property(copy) NSString *keyEquivalent;
@end
@implementation Button @end
@interface Alert:NSObject
@property(copy) NSString *messageText,*informativeText;
@property NSMutableArray *buttons;
- (NSButton *)addButtonWithTitle:(NSString *)title;
- (void)beginSheetModalForWindow:(id)window completionHandler:(void (^)(NSModalResponse))block;
@end
@implementation Alert
- (NSButton *)addButtonWithTitle:(NSString *)title {if(!self.buttons)self.buttons=[NSMutableArray new];Button *b=[Button new];[self.buttons addObject:b];return (id)b;}
- (void)beginSheetModalForWindow:(id)window completionHandler:(void (^)(NSModalResponse))block {if(![self.buttons[0] keyEquivalent] || ![[self.buttons[0] keyEquivalent] isEqual:@""] || ![[self.buttons[1] keyEquivalent] isEqual:@"\e"] || ![self.informativeText containsString:@"/Library/TeX/texbin"]) {fprintf(stderr,"FAIL: profile confirmation keys and engine path\n");exit(1);} confirmations++;block(NSAlertSecondButtonReturn);}
@end
@interface Probe:NSObject <NSControlTextEditingDelegate> { @public Window *_prefsWindow; Tab *_tabView; FIELDS }
@property NSMapTable *inputRules;
@property id settingsController;
@property(copy) NSString *fontEditingContext;
@property BOOL endingPreferences,inputErrorPresented,initialEnginePathSearchPending,ownsFontPanel,valid;
@property NSUInteger finishCalls;
@property NSFont *documentFont,*consoleFont;
@end
@implementation Probe
- (BOOL)finishPreferenceEditing:(BOOL)show {self.finishCalls++;return self.valid;}
- (void)cancelEnginePathDiscovery {}
- (BOOL)prepareSettingsWindow {return YES;}
- (void)beginSession {}
- (void)releasePreferencePanels {}
- (void)updateControlsFromUserDefaults:(id)d {}
- (void)PrepareColorPane:(id)d {}
- (void)showPreferenceError:(NSString *)message {abort();}
- (void)applyPreferenceProfile:(id)p font:(id)f {abort();}
- (void)updateDocumentFontTextField {}
- (void)updateConsoleFontTextField {}
METHODS
@end
static void check(BOOL ok,const char *message){if(!ok){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
int main(int argc,char **argv){@autoreleasepool{
 resources=@(argv[1]);
 method_exchangeImplementations(class_getInstanceMethod(TSPreferenceProfile.class,@selector(initWithProfile:documentFont:registeredDefaults:)),class_getInstanceMethod(TSPreferenceProfile.class,@selector(checkedProfile:documentFont:registeredDefaults:)));
 TSInstallAppKitIsolation();memory=[TSMemoryDefaults new];Probe *p=[Probe new];p.valid=YES;
 p->_prefsWindow=[Window new];p->_tabView=[Tab new];p->_tabView.identifier=@"Document";
 INITFIELDS
 [p configurePreferenceInputs];check(p.inputRules.count==19,"all nineteen production rules");
 RULECHECKS
 for (Field *field in p.inputRules) check(field.formatter==nil,"common validation replaces nib formatter");
 TSPreferenceInput *path=[p.inputRules objectForKey:p->_tetexBinPathField];
 check([path validatedValue:@"  "]==nil,"production engine path rejects empty");
 TSPreferenceInput *tabs=[p.inputRules objectForKey:p->tabIndentField];
 check([tabs validatedValue:@"501"].numberValue.integerValue==50,"production tabs maximum");
 TSPreferenceInput *zoom=[p.inputRules objectForKey:p->_magTextField];
 check(fabs([zoom validatedValue:@"125"].numberValue.doubleValue-1.25)<0.0001,"production PDF percentage");
 p.endingPreferences=YES;p.inputErrorPresented=YES;[p showPreferences:nil];
 check(!p.endingPreferences && !p.inputErrorPresented && p->_prefsWindow.fronts==1,"reopen resets ending state before editing");
 NSMenuItem *invalid=[[NSMenuItem alloc]initWithTitle:@"invalid" action:NULL keyEquivalent:@""];invalid.tag=0;
 NSUInteger count=p.finishCalls;[p setDefaults:invalid];
 check(p.finishCalls==count+1,"profile entry first commits pending field before resolving profile");
 invalid.tag=1;p.valid=NO;count=p.finishCalls;NSUInteger looked=resourceLookups;[p setDefaults:invalid];
 check(p.finishCalls==count+1 && resourceLookups==looked && confirmations==0,"invalid pending input aborts profile before resources and confirmation");
 p.valid=YES;[p setDefaults:invalid];check(confirmations==1 && resourceLookups==looked+2,"valid profile loads its values and factory fallbacks after commit");
 FontManager *fm=[FontManager sharedFontManager];NSObject *documentTarget=[NSObject new];fm.target=documentTarget;
 p.documentFont=[NSFont systemFontOfSize:12];[SUD setObject:@"Helvetica" forKey:ConsoleFontNameKey];[SUD setObject:@12 forKey:ConsoleFontSizeKey];
 [p changeDocumentFont:nil];[p changeConsoleFont:nil];
 check(fm.target==documentTarget && fm.fronts==2,"settings do not capture global font target");
 [SUD.values removeAllObjects];fm.target=nil;
 for(NSNumber *owns in @[@NO,@YES]) {p.ownsFontPanel=owns.boolValue;[p changeFont:(id)fm];}
 check(fm.conversions==0 && SUD.values.count==0,"document-main font operations never change preference defaults");
 p->_prefsWindow.isMainWindow=YES;p.ownsFontPanel=NO;[p changeFont:(id)fm];check(fm.conversions==0,"font session must be owned");
 p.ownsFontPanel=YES;p.fontEditingContext=@"Document";[p changeFont:(id)fm];check(fm.conversions==1 && [SUD objectForKey:DocumentFontKey]!=nil,"active owned font session persists");
 p.endingPreferences=YES;[p changeFont:(id)fm];check(fm.conversions==1,"ending session ignores font action");
 puts("PASS: nineteen production rules, formatter removal, reopen, profile precommit and responder-based font ownership");
}return 0;}
'''
# Independent expectations: do not derive limits or empty policy from production.
expected=[('Integer',2,50,False),('Integer',0,100,False),('Integer',0,100,False),('Integer',1,20,False),('Percentage',20,400,False),('Text',0,0,True),('Text',0,0,False),('Text',0,0,False),('Text',0,0,False),('Text',0,0,False),('Text',0,0,False),('Text',0,0,False),('Text',0,0,False),('Text',0,0,True),('Text',0,0,False),('Text',0,0,False),('Text',0,0,True),('Text',0,0,True),('Text',0,0,True)]
assert len(fields)==len(expected)==19
expected_keys=['tabs','SourceFirstLineHeadIndent','SourceHeadIndent','SourceInterlineSpace','PdfMagnification','HtmlHome','DefaultEngine','TexCommand','LatexCommand','TexGSCommand','LatexGSCommand','TetexBinPath','GSBinPath','AltPath','Kpsetool','BibTeXengine','TexScriptCommand','LatexScriptCommand','AlternateEngine']
globals_source=(R/'Sources/globals.m').read_bytes().decode('latin1')
constant_values={k:re.search(r'\b'+re.escape(k)+r'\s*=\s*@"([^"\n]*)"',globals_source).group(1) for k in constants}
checks=[]
for i,(f,(kind,low,high,empty)) in enumerate(zip(fields,expected)):
 notification='[v.notification isEqual:DocumentFontChangedNotification]' if i<4 else 'v.notification==nil'
 checks.append('{TSPreferenceInput *v=[p.inputRules objectForKey:p->%s];check([v.key isEqual:@"%s"] && %s && v.kind==TSPreferenceInput%s && v.minimum==%s && v.maximum==%s && v.allowsEmpty==%s,"rule %s");}'%(f,expected_keys[i],notification,kind,low,high,'YES' if empty else 'NO',f))
program=program.replace('INITFIELDS','\n'.join('p->%s=[Field new];p->%s.formatter=[NSObject new];'%(f,f) for f in fields)).replace('FIELDS',' '.join('Field *%s;'%f for f in fields)).replace('CONSTANTS','\n'.join('static NSString *%s=@"%s";'%(k,constant_values[k]) for k in constants)).replace('RULECHECKS','\n'.join(checks)).replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='texshop-settings-sessions-') as td:
 p=Path(td);(p/'test.m').write_text(program)
 subprocess.run(['xcrun','clang','-w','-fobjc-arc','-I',str(R/'Sources'),'-I',str(R/'Tests'),'-framework','Cocoa',str(p/'test.m'),str(R/'Sources/TSPreferenceInput.m'),str(R/'Sources/TSPreferenceProfile.m'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test'),str(R/'Resources/Shellscripts')],check=True)
