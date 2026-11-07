#!/usr/bin/env python3
"""Verify phase-independent live settings wiring in source and built nibs, without UI."""
from pathlib import Path
import subprocess,tempfile,sys,hashlib,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[1]
nibs=sorted((R/'Resources/Interfaces').glob('*.lproj/Preferences.nib'))
expected_category_objects={'Base': ['9', 'oKf-gv-Zsv', '8', '705', '179', '12', '415', 'oKY-XW-zh8', 'cCi-AG-dLh'], 'de': ['9', 'ojA-nd-9Bh', '8', '705', '179', '12', '415', '127', 'GZb-Wd-1z4'], 'es': ['9', '8Yq-tq-YHl', '8', '705', '179', '12', '415', '127', 'hg1-fQ-r8c'], 'fr': ['9', 'NRu-Ho-X2V', '8', '705', '179', '12', '415', '127', 'vC4-9I-kap'], 'it': ['9', 'fhj-gm-r8W', '8', '705', '179', '12', '415', '127', 'Ijc-4D-Pq3'], 'ja': ['9', 'cFa-nR-PWg', '8', '705', '179', '12', '415', '127', 'ily-wg-WCL'], 'ko': ['6', 'ZtK-zb-S7z', '109', '163', '191', '223', '274', '310', 'vRH-ih-Phg'], 'nl': ['9', 'ygL-Hz-cPs', '8', '705', '179', '12', '415', '127', 'Iko-Uy-1YZ'], 'pt-PT': ['9', 'vSl-aQ-Jem', '8', '705', '179', '12', '415', '127', 'BjP-aW-ZeK'], 'pt': ['9', 'Liu-Xu-uZ2', '8', '705', '179', '12', '415', '127', 'hFq-KW-LgH'], 'ro': ['9', 'bUk-zg-ezp', '8', '705', '179', '12', '415', '127', 'bbA-ns-GW7'], 'zh_CN': ['9', 'kRE-Gu-AaN', '8', '705', '179', '12', '415', '127', 'ILr-M7-I2L']}
for nib in nibs:
 tree=ET.parse(nib/'designable.nib');window=next(w for w in tree.iter('window') if w.find(".//tabView") is not None)
 tabs=next(t for t in tree.iter('tabView') if len(t.findall('tabViewItems/tabViewItem'))==9)
 assert [i.get('id') for i in tabs.findall('tabViewItems/tabViewItem')]==expected_category_objects[nib.parent.stem],nib
 assert window.find('windowStyleMask').get('closable')=='YES'
 assert window.find('windowStyleMask').get('resizable')!='YES'
 actions={a.get('selector') for a in tree.iter('action')}
 assert not actions.intersection({'okButtonPressed:','cancelButtonPressed:','SaveEditedStyle:'})
 assert 'themeSelectionChanged:' in actions
paths=[p for n in nibs for p in sorted(n.glob('keyedobjects*.nib'))]
if len(sys.argv)>1:
 product=Path(sys.argv[1])/'Contents/Resources'
 for n in nibs:
  built=product/n.parent.name/n.name
  for source in n.glob('keyedobjects*.nib'):
   p=built/source.name;assert p.is_file(),p
   assert hashlib.sha256(p.read_bytes()).digest()==hashlib.sha256(source.read_bytes()).digest(),p
   paths.append(p)
program=r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
@interface TSPreferences:NSObject { @public NSPopUpButton *LiteStyle,*DarkStyle; }
@property NSMutableDictionary *outlets;
@end
@implementation TSPreferences
- (void)themeSelectionChanged:(id)sender {}
- (void)setValue:(id)v forUndefinedKey:(NSString *)key {if(!self.outlets)self.outlets=[NSMutableDictionary dictionary];self.outlets[key]=v;}
@end
@interface TSPreferenceWindow:NSWindow @end
@implementation TSPreferenceWindow @end
static NSUInteger visit(NSView *v){
 NSUInteger tabs=0;
 if([v isKindOfClass:NSControl.class]){
  NSString *action=NSStringFromSelector([(NSControl *)v action]);
  NSCAssert((![@[@"okButtonPressed:",@"cancelButtonPressed:",@"SaveEditedStyle:"] containsObject:action]),@"obsolete action");
 }
 if([v isKindOfClass:NSTabView.class]){
  NSTabView *t=(id)v;if(t.numberOfTabViewItems==9)tabs++;
  for(NSTabViewItem *item in t.tabViewItems)tabs+=visit(item.view);
 }else for(NSView *c in v.subviews)tabs+=visit(c);
 return tabs;
}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 for(int i=1;i<argc;i++){
  TSPreferences *owner=[TSPreferences new];NSArray *objects;
  NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:@(argv[i])] bundle:nil];
  NSCAssert([nib instantiateWithOwner:owner topLevelObjects:&objects],@"load nib");
  NSUInteger windows=0;
  for(id obj in objects)if([obj isKindOfClass:NSWindow.class] && visit([obj contentView])==1){
   NSWindow *w=obj;windows++;NSCAssert((w.styleMask&NSWindowStyleMaskClosable) && !(w.styleMask&NSWindowStyleMaskResizable),@"close-only settings window");
   NSCAssert(w.defaultButtonCell==nil,@"no global Return action");
   NSCAssert(visit(w.contentView)==1,@"retain the existing nine tabs");
  }
  NSCAssert(windows==1,@"one settings window");
  for(NSString *key in @[@"LiteStyle",@"DarkStyle"]){NSPopUpButton *p=[key isEqual:@"LiteStyle"]?owner->LiteStyle:owner->DarkStyle;NSCAssert([NSStringFromSelector(p.action) isEqual:@"themeSelectionChanged:"],@"theme popup persists selection");}
 }
 printf("PASS: %d compiled nibs retain nine tabs, close button, immediate theme actions, no global OK/Cancel or Return\n",argc-1);
}return 0;}
'''
with tempfile.TemporaryDirectory(prefix='texshop-live-nibs-') as td:
 t=Path(td);(t/'probe.m').write_text(program)
 subprocess.run(['clang','-fobjc-arc','-I',str(R/'Tests'),'-framework','Cocoa',str(t/'probe.m'),'-o',str(t/'probe')],check=True)
 subprocess.run([str(t/'probe')]+list(map(str,paths)),check=True)
