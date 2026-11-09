// SPDX-License-Identifier: GPL-2.0-or-later
#import "TestAppKitIsolation.h"
#import "TSPreferenceInput.h"
static void Check(BOOL ok,const char *message){if(!ok){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
static TSPreferenceInput *Rule(NSString *key,TSPreferenceInputKind kind,BOOL empty){return [[TSPreferenceInput alloc]initWithKey:key kind:kind minimum:kind==TSPreferenceInputInteger?2:20 maximum:kind==TSPreferenceInputInteger?50:400 allowsEmpty:empty notification:nil];}
int main(void){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];
 TSMemoryDefaults *defaults=[TSMemoryDefaults new];TSPreferenceEditing *session=[TSPreferenceEditing new];NSObject *owner=[NSObject new];
 NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,500,250) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 NSTextField *tabs=[NSTextField textFieldWithString:@"20"],*gs=[NSTextField textFieldWithString:@""];
 tabs.frame=NSMakeRect(10,120,150,24);gs.frame=NSMakeRect(10,80,350,24);
 [window.contentView addSubview:tabs];[window.contentView addSubview:gs];
 TSPreferenceInput *tabRule=Rule(@"tabs",TSPreferenceInputInteger,NO),*gsRule=Rule(@"GSBinPath",TSPreferenceInputText,NO);
 [defaults setInteger:8 forKey:@"tabs"];[defaults setObject:@"" forKey:@"GSBinPath"];
 [session markEdited:tabs];Check([session commitField:tabs rule:tabRule defaults:defaults reflect:YES sender:owner],"tab width commits");
 Check([defaults integerForKey:@"tabs"]==20,"step 1: tab width 20 saved");
 NSDictionary *saved=[defaults dictionaryRepresentation];
 [window makeFirstResponder:gs]; // Focus alone must not turn a saved empty path into an edit.
 Check([session commitField:gs rule:gsRule defaults:defaults reflect:YES sender:owner],"step 2/3: untouched empty GS path does not block navigation");
 Check([[defaults dictionaryRepresentation]isEqual:saved],"focus/navigation writes no settings");
 [window makeFirstResponder:nil];
 // Exercise the restore branch as well: it must fetch GS's saved value, never tabs' 20.
 gs.stringValue=@" ";[session markEdited:gs];
 Check(![session commitField:gs rule:gsRule defaults:defaults reflect:YES sender:owner],"invalid actual edit requests validation");
 [session restoreField:gs rule:gsRule defaults:defaults];
 Check([gs.stringValue isEqual:@""],"step 4: restore GS's saved empty value, not the previous field's 20");
 Check([session commitField:gs rule:gsRule defaults:defaults reflect:YES sender:owner],"step 5: restored invalid legacy value does not trap navigation");
 Check([[defaults dictionaryRepresentation]isEqual:saved],"restoring and leaving never writes GSBinPath=20");
 NSArray *cases=@[@[@"Kpsetool",@"kpsetool -w -n latex tex",@0],@[@"PdfMagnification",@"126",@2],@[@"TexScriptCommand",@"",@0]];
 [defaults setDouble:1.255 forKey:@"PdfMagnification"];[defaults setObject:@" " forKey:@"TexScriptCommand"];
 saved=[defaults dictionaryRepresentation];
 for(NSArray *item in cases){NSTextField *field=[NSTextField textFieldWithString:item[1]];TSPreferenceInput *rule=Rule(item[0],[item[2]integerValue],YES);
  Check([session commitField:field rule:rule defaults:defaults reflect:YES sender:owner],"untouched default display is accepted");
  Check([[defaults dictionaryRepresentation]isEqual:saved],"opening, navigation and termination preserve absent/raw/precision values");}
 NSTextField *magnification=[NSTextField textFieldWithString:@"999"];TSPreferenceInput *magRule=Rule(@"PdfMagnification",TSPreferenceInputPercentage,NO);
 [session markEdited:magnification];Check([session commitField:magnification rule:magRule defaults:defaults reflect:YES sender:owner],"Return path validates magnification");
 Check([defaults doubleForKey:@"PdfMagnification"]==4 && [magnification.stringValue isEqual:@"400"],"magnification is clamped and reflected");
 gs.stringValue=@"/changed";[session markEdited:gs];tabs.stringValue=@"30";
 Check([session commitField:tabs rule:tabRule defaults:defaults reflect:NO sender:owner] && [defaults integerForKey:@"tabs"]==20,"only the edited field may commit");
 Check([session commitField:gs rule:gsRule defaults:defaults reflect:NO sender:owner] && [[defaults stringForKey:@"GSBinPath"]isEqual:@"/changed"],"edited termination path saves without UI");
 [defaults setObject:@" " forKey:@"GSBinPath"];gs.stringValue=@"bad";[session restoreField:gs rule:gsRule defaults:defaults];Check([gs.stringValue isEqual:@" "],"restore preserves the saved text exactly");
 Check(!window.visible,"no window displayed");
 puts("PASS: field-specific restore, untouched focus, absent defaults, raw whitespace, numeric precision, Return clamp, edited-only commit");
}return 0;}
