// Production macro lookup and editor entry, using in-memory trees and inert collaborators.
#import "TSMacroSelection.h"
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSKeyboardShortcuts.m"
#import "TSMacroTreeNode.h"
#import "TSMacroMenuController.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
#include "MacroProviderFunction.inc"
@implementation TSMacroMenuController
#include "MacroProviderMethod.inc"
@end
#include "MacroKeyProduction.inc"
@interface EditorWindow:NSObject
@property BOOL valid;
@property id attachedSheet;
- (BOOL)makeFirstResponder:(id)sender;
@end
@implementation EditorWindow
- (BOOL)makeFirstResponder:(id)sender{return self.valid;}
@end
@interface Outline:NSObject
@property TSMacroTreeNode *rootOfTree;
@property TSMacroTreeNode *target;
@property NSMutableArray *expanded;
@property NSIndexSet *selected;
@property NSInteger scrolled;
@end
@implementation Outline
- (instancetype)init{if((self=[super init])){_expanded=[NSMutableArray new];_scrolled=-1;}return self;}
- (void)expandItem:(id)item{[self.expanded addObject:item];}
- (NSInteger)rowForItem:(id)item{return item==self.target?7:-1;}
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend{self.selected=indexes;}
- (void)scrollRowToVisible:(NSInteger)row{self.scrolled=row;}
@end
@interface TSMacroEditor:NSObject { @public EditorWindow *window; Outline *outlineView; Outline *outlineController; }
@property NSUInteger opened,committed;
@property (copy) void (^commitEdit)(void);
@end
@implementation TSMacroEditor
- (void)openMacroEditor:(id)sender{self.opened++;}
- (void)reflectChangesInEditor:(BOOL)force{self.committed++;if(self.commitEdit)self.commitEdit();}
#include "MacroSelectionEntry.inc"
@end
int main(void){@autoreleasepool{
 TSInstallAppKitIsolation();
 TSMacroMenuController *provider=[TSMacroMenuController new];
 provider.macroDict=@{@"name":@"root",@"submenu":@[@{@"name":@"Separator"},@{@"name":@"Group",@"submenu":@[@{@"name":@"First",@"key":@"A+ShiftKey+ControlKey"},@{@"name":@"Second",@"key":@"-+ShiftKey"}]},@{@"name":@"No key",@"key":@""}]};
 NSArray<TSShortcutMacro *> *entries=[provider shortcutEntries];
 REQUIRE(entries.count==2 && entries[0].indexPath.length==2 && [entries[0].indexPath indexAtPosition:0]==1 && [entries[0].indexPath indexAtPosition:1]==0);
 REQUIRE([entries[0].serializedKey isEqual:@"A+ShiftKey+ControlKey"] && [entries[0].key isEqual:@"a"] && entries[0].modifiers==(NSEventModifierFlagCommand|NSEventModifierFlagShift|NSEventModifierFlagControl));
 REQUIRE([entries[1].key isEqual:@"-"] && entries[1].modifiers==(NSEventModifierFlagCommand|NSEventModifierFlagShift));
 REQUIRE([entries[0].path containsString:@"Group"] && [entries[0].name isEqual:@"First"]);
 TSMacroTreeNode *tree=[TSMacroTreeNode nodeFromDictionary:provider.macroDict];
 TSMacroTreeNode *group=[tree childAtIndex:1],*first=[group childAtIndex:0];
 Outline *outline=[Outline new];outline.rootOfTree=tree;outline.target=first;
 EditorWindow *inert=[EditorWindow new];inert.valid=YES;
 TSMacroEditor *editor=[TSMacroEditor new];editor->window=inert;editor->outlineController=outline;editor->outlineView=outline;
 __block BOOL pending=YES;
 editor.commitEdit=^{if(pending){first.content=@"unsaved edit";pending=NO;}};
 [editor openMacroEditorSelectingMacroAtIndexPath:entries[0].indexPath name:entries[0].name key:entries[0].serializedKey];
 REQUIRE(editor.opened==1 && editor.committed==1 && !pending && [first.content isEqual:@"unsaved edit"]);
 REQUIRE(outline.expanded.count==1 && outline.expanded[0]==group && outline.selected.firstIndex==7 && outline.scrolled==7);
 [first removeFromParent];[group addChild:first];outline.selected=nil;
 [editor openMacroEditorSelectingMacroAtIndexPath:entries[0].indexPath name:entries[0].name key:entries[0].serializedKey];REQUIRE(outline.selected.firstIndex==7);
 [tree addChild:[TSMacroTreeNode nodeWithName:entries[0].name content:@"duplicate" key:entries[0].serializedKey]];
 outline.selected=[NSIndexSet indexSetWithIndex:3];
 [editor openMacroEditorSelectingMacroAtIndexPath:entries[0].indexPath name:entries[0].name key:entries[0].serializedKey];REQUIRE(outline.selected.firstIndex==3);
 NSUInteger commits=editor.committed;inert.valid=NO;
 [editor openMacroEditorSelectingMacroAtIndexPath:entries[1].indexPath name:entries[1].name key:entries[1].serializedKey];REQUIRE(editor.committed==commits && outline.selected.firstIndex==3);
 inert.valid=YES;inert.attachedSheet=[NSObject new];
 [editor openMacroEditorSelectingMacroAtIndexPath:entries[1].indexPath name:entries[1].name key:entries[1].serializedKey];REQUIRE(editor.committed==commits && outline.selected.firstIndex==3);
 REQUIRE([first.content isEqual:@"unsaved edit"]);
 puts("PASS: real macro provider preserves raw keys/file paths; editor entry reuses initialization, commits only in memory, expands/scrolls exact or unique targets and preserves ambiguous selection");
}}
