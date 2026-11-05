// Load compiled preferences without starting TeXShop or writing its settings.
#import <Cocoa/Cocoa.h>
@interface TSPreferences:NSObject { @public NSButton *_texAwareSpellCheckButton; }
@property NSUInteger clicks;
@end
@implementation TSPreferences
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
- (void)texAwareSpellCheckPressed:(NSButton *)sender { self.clicks++; }
- (void)editSpellingExclusions:(id)sender {}
@end
@interface TSPreferenceWindow:NSWindow
@end
@implementation TSPreferenceWindow
- (BOOL)setFrameAutosaveName:(NSString *)name { return NO; }
- (void)saveFrameUsingName:(NSString *)name {}
@end
static NSTabView *Tabs(NSView *v) {
 if([v isKindOfClass:NSTabView.class]) return (id)v;
 for(NSView *c in v.subviews){NSTabView *t=Tabs(c);if(t)return t;}return nil;
}
int main(int argc,char **argv){@autoreleasepool{
 [NSApplication sharedApplication];
 [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 for(int i=1;i<argc;i++){
  NSString *path=@(argv[i]), *lang=path.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.lastPathComponent;
  TSPreferences *owner=[TSPreferences new];
  NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:path] bundle:nil];
  NSArray *objects; if(![nib instantiateWithOwner:owner topLevelObjects:&objects])return 2;
  NSButton *b=owner->_texAwareSpellCheckButton;
  if(!b || ![NSStringFromSelector(b.action) isEqual:@"texAwareSpellCheckPressed:"])return 3;
  for(id o in objects) if([o isKindOfClass:NSWindow.class]) { [Tabs([o contentView]) selectTabViewItemWithIdentifier:@"Document"]; }
  b.state=NSControlStateValueOff;[b.cell setNextState]; [NSApp sendAction:b.action to:b.target from:b];
  if(b.state!=NSControlStateValueOn || owner.clicks!=1)return 4;
  [b.cell setNextState]; [NSApp sendAction:b.action to:b.target from:b];if(b.state!=NSControlStateValueOff || owner.clicks!=2)return 5;
  NSSize size=b.cell.cellSize;
  printf("%s: checkbox %s, size %.1fx%.1f, frame %.1fx%.1f\n",lang.UTF8String,b.title.UTF8String,size.width,size.height,b.frame.size.width,b.frame.size.height);
  if(size.width>b.frame.size.width+.5 || size.height>b.frame.size.height+.5)return 6;
  if(!NSContainsRect(b.superview.bounds,b.frame))return 7;
  for(id o in objects){
   if(![o isKindOfClass:NSWindow.class])continue;NSWindow *w=o;NSTabView *tabs=Tabs(w.contentView);
   if(tabs.numberOfTabViewItems!=9)continue;
   [tabs selectTabViewItemWithIdentifier:@"Document"];
   [w.contentView layoutSubtreeIfNeeded];
   [w orderOut:nil];
  }
 }
 puts("PASS: all localized nibs load; checkbox toggles, fits and connects");
}return 0;}
