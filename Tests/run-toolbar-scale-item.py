#!/usr/bin/env python3
"""Check the Scale items of the preview toolbars with production toolbar code.

The Scale views of every localized TSDocument nib keep at least 10 points after their
arrows, so that the arrows do not sit against the label of the next item, and nothing
else in them moves. A click on their label opens a copy of Preview > Magnification from
the menu bar of the same language, below the label; its commands go to the first
responder, as those of the menu bar do. Preparing a view twice changes nothing more.
Nothing is shown on screen and no user settings are read.
"""
import argparse, os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['no-space', 'twice', 'same-menu', 'no-call', 'above'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
toolbar = (root/'Sources/Windows/TSToolbarController.m').read_text()

fragments = []
def method(signature):
    fragment = production_method(toolbar, signature)
    fragments.append(('complete method:'+signature, toolbar, fragment))
    return fragment
def span(first, last):
    start = toolbar.index(first); end = toolbar.index(last, start) + len(last)
    fragment = toolbar[start:end]
    assert toolbar.count(fragment) == 1
    fragments.append(('statements:'+first, toolbar, fragment))
    return fragment

constant = span('static const CGFloat TSScaleItemSpaceAfterArrows', ';')
methods = '\n'.join(method(s) for s in ['static NSMenu *TSPreviewMagnificationMenu(NSMenu *menu)',
                                        '- (void)prepareScaleToolbarView:(NSView *)scaleView',
                                        '- (NSMenu *)magnificationMenuForScaleLabel',
                                        '- (void)showMagnificationMenuFromScaleLabel:(NSClickGestureRecognizer *)recognizer'])

# Every Scale item, in the Preview window, the one window and the image window, prepares
# its view before the toolbar item takes it.
item_for = production_method(toolbar, '- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar itemForItemIdentifier:')
if args.mutation == 'no-call':
    item_for = item_for.replace('\t\t[self prepareScaleToolbarView:magnificationOutletKK];\n', '', 1)
for ident, outlet in [('kMagnificationKKTID', 'magnificationOutletKK'), ('skMagnificationKKTID', 'smagnificationOutletKK'),
                      ('kMagnificationTID', 'magnificationOutlet')]:
    branch = item_for[item_for.index('if ([itemIdent isEqual: %s]) {' % ident):]
    branch = branch[:branch.index('return toolbarItem;')]
    call = '[self prepareScaleToolbarView:%s];' % outlet
    assert branch.count(call) == 1 and branch.index(call) < branch.index('customView:%s]' % outlet), 'Scale item prepares its view: '+ident
assert item_for.count('prepareScaleToolbarView:') == 3, 'Only the Scale items are prepared'

if args.mutation == 'no-space':
    methods = methods.replace('+ TSScaleItemSpaceAfterArrows;', ';')
elif args.mutation == 'twice':
    methods = methods.replace('                return;\n        [label addGestureRecognizer', '                ;\n        [label addGestureRecognizer')
elif args.mutation == 'same-menu':
    methods = methods.replace('return [TSPreviewMagnificationMenu([NSApp mainMenu]) copy];', 'return TSPreviewMagnificationMenu([NSApp mainMenu]);')
elif args.mutation == 'above':
    methods = methods.replace('label.isFlipped ? NSMaxY(item) : NSMinY(item)', 'label.isFlipped ? NSMinY(item) : NSMaxY(item)')

program = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
CONSTANT
// The nib connects an outlet only when its owner has a setter for it.
@interface TSDocument : NSObject
@property (strong) id magnificationOutletKK, smagnificationOutletKK, magnificationOutlet;
@end
@implementation TSDocument
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
METHODS
@end
@interface MenuOwner : NSObject
@end
@implementation MenuOwner
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
@end
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } }
static NSMenu *shownMenu; static NSView *shownIn; static NSPoint shownAt; static NSUInteger shown;
static BOOL RecordPopUp(NSMenu *menu, SEL cmd, NSMenuItem *item, NSPoint location, NSView *view) {
 shownMenu = menu; shownIn = view; shownAt = location; shown++; return NO;
}
static NSArray *Facts(NSMenu *menu) {
 NSMutableArray *facts = [NSMutableArray array];
 for (NSMenuItem *item in menu.itemArray)
  [facts addObject:@[item.title, NSStringFromSelector(item.action) ?: @"", @(item.tag), item.keyEquivalent, @(item.keyEquivalentModifierMask),
                     @(item.isSeparatorItem), item.identifier ?: @"", item.target ?: NSNull.null]];
 return facts;
}
static NSArray *Frames(NSView *content) {
 NSMutableArray *frames = [NSMutableArray array];
 for (NSView *view in content.subviews) [frames addObject:[NSValue valueWithRect:view.frame]];
 return frames;
}
int main(int argc, char **argv) { @autoreleasepool {
 TSInstallAppKitIsolation(); [NSApplication sharedApplication];
 NSString *language = @(argv[1]);
 NSString *loaded = NSBundle.mainBundle.preferredLocalizations.firstObject;
 Check([loaded isEqual:[language isEqual:@"Base"] ? @"en" : language], [NSString stringWithFormat:@"Requested localization %@, got %@", language, loaded]);
 Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"org.texshop.ToolbarScaleTest."], @"Isolated test bundle");
 method_setImplementation(class_getInstanceMethod(NSMenu.class, @selector(popUpMenuPositioningItem:atLocation:inView:)), (IMP)RecordPopUp);

 NSArray *menuObjects = nil;
 Check([[[NSNib alloc] initWithNibNamed:@"MainMenu" bundle:nil] instantiateWithOwner:[MenuOwner new] topLevelObjects:&menuObjects], @"MainMenu loads");
 NSMenu *bar = nil;
 for (id object in menuObjects) if ([object isKindOfClass:NSMenu.class] && [(NSMenu *)object numberOfItems] > 5) bar = object;
 Check(bar != nil, @"Menu bar in MainMenu"); NSApp.mainMenu = bar;
 NSMenu *magnification = TSPreviewMagnificationMenu(bar);
 Check(magnification && magnification.supermenu && magnification != bar, @"Preview > Magnification found");
 NSMenuItem *preview = magnification.supermenu.supermenu ? [magnification.supermenu.supermenu itemAtIndex:[magnification.supermenu.supermenu indexOfItemWithSubmenu:magnification.supermenu]] : nil;
 Check(preview && [[magnification.supermenu itemAtIndex:[magnification.supermenu indexOfItemWithSubmenu:magnification]].title isEqual:magnification.title], @"The submenu of a menu item");
 NSMutableSet *tags = [NSMutableSet set];
 for (NSMenuItem *item in magnification.itemArray) if (item.action == @selector(changePDFViewSize:)) { [tags addObject:@(item.tag)]; Check(item.target == nil, @"Sent to the first responder"); }
 Check([tags isEqual:[NSSet setWithArray:@[@1, @2, @3, @6]]], [NSString stringWithFormat:@"Magnification modes: %@", tags]);
 NSUInteger zoom = 0;
 for (NSMenuItem *item in magnification.itemArray) if (item.action == @selector(zoomIn:) || item.action == @selector(zoomOut:)) zoom++;
 Check(zoom == 2, @"Zoom In and Zoom Out");

 TSDocument *d = [TSDocument new];
 NSArray *documentObjects = nil;
 Check([[[NSNib alloc] initWithNibNamed:@"TSDocument" bundle:nil] instantiateWithOwner:d topLevelObjects:&documentObjects], @"TSDocument loads");
 NSUInteger checked = 0;
 for (NSString *outlet in @[@"magnificationOutletKK", @"smagnificationOutletKK", @"magnificationOutlet"]) {
  NSBox *box = [d valueForKey:outlet];
  if (!box) { Check([outlet isEqual:@"smagnificationOutletKK"] && ![language isEqual:@"Base"], [@"Scale view in the nib: " stringByAppendingString:outlet]); continue; }
  NSString *where = [NSString stringWithFormat:@"%@ %@", language, outlet];
  Check([box isKindOfClass:NSBox.class], where);
  NSView *content = box.contentView;
  NSStepper *arrows = nil; NSTextField *label = nil, *field = nil;
  for (NSView *view in content.subviews) {
   if ([view isKindOfClass:NSStepper.class]) arrows = (NSStepper *)view;
   else if ([view isKindOfClass:NSTextField.class]) { if ([(NSTextField *)view isEditable]) field = (NSTextField *)view; else label = (NSTextField *)view; }
  }
  Check(arrows && label && field && content.subviews.count == 3, [@"Label, field and arrows: " stringByAppendingString:where]);
  Check(NSMidX(label.frame) < NSMinX(field.frame) && NSMaxX(field.frame) <= NSMinX(arrows.frame), [@"Label, field, arrows from left to right: " stringByAppendingString:where]);
  NSRect before = box.frame; NSArray *frames = Frames(content);
  CGFloat arrowsEnd = NSMaxX([content convertRect:arrows.frame toView:box]);
  Check(arrowsEnd <= NSWidth(before) + 0.5, [@"Arrows inside the view: " stringByAppendingString:where]);
  [d prepareScaleToolbarView:box];
  CGFloat expected = MAX(NSWidth(before), arrowsEnd + 10);
  Check(fabs(NSWidth(box.frame) - expected) < 0.01, [NSString stringWithFormat:@"%@: width %.1f -> %.1f, expected %.1f", where, NSWidth(before), NSWidth(box.frame), expected]);
  Check(NSWidth(box.frame) - arrowsEnd >= 10 - 0.01, [@"Room after the arrows: " stringByAppendingString:where]);
  Check(NSHeight(box.frame) == NSHeight(before) && NSEqualPoints(box.frame.origin, before.origin), [@"Only the width changes: " stringByAppendingString:where]);
  Check([Frames(content) isEqual:frames], [@"Label, field and arrows stay in place: " stringByAppendingString:where]);
  Check(fabs(NSWidth(content.frame) - NSWidth(box.frame)) < 0.01, [@"The content follows the view: " stringByAppendingString:where]);
  NSRect prepared = box.frame;
  [d prepareScaleToolbarView:box];
  Check(NSEqualRects(box.frame, prepared), [@"Preparing again keeps the width: " stringByAppendingString:where]);
  Check(label.gestureRecognizers.count == 1, [@"One click recognizer on the label: " stringByAppendingString:where]);
  Check(field.gestureRecognizers.count == 0 && arrows.gestureRecognizers.count == 0 && box.gestureRecognizers.count == 0, [@"Only the label opens the menu: " stringByAppendingString:where]);
  NSClickGestureRecognizer *click = (NSClickGestureRecognizer *)label.gestureRecognizers.firstObject;
  Check([click isKindOfClass:NSClickGestureRecognizer.class] && click.target == d && click.action == @selector(showMagnificationMenuFromScaleLabel:)
        && click.buttonMask == 1 && click.numberOfClicksRequired == 1, [@"A single click: " stringByAppendingString:where]);

  // Outside a window nothing opens.
  shown = 0; [d showMagnificationMenuFromScaleLabel:click];
  Check(shown == 0, [@"No menu outside a window: " stringByAppendingString:where]);
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
  window.releasedWhenClosed = NO; [window.contentView addSubview:box];
  [d showMagnificationMenuFromScaleLabel:click];
  Check(shown == 1 && shownIn == label, [@"The menu opens at the label: " stringByAppendingString:where]);
  NSRect labelInWindow = [label convertRect:label.bounds toView:nil], itemInWindow = [content convertRect:content.bounds toView:nil];
  NSPoint point = [label convertPoint:shownAt toView:nil];
  Check(fabs(point.x - NSMinX(labelInWindow)) < 0.01 && fabs(point.y - NSMinY(itemInWindow)) < 0.01, [NSString stringWithFormat:@"%@: menu below the item, from the left of the label (%@; label %@, item %@)", where, NSStringFromPoint(point), NSStringFromRect(labelInWindow), NSStringFromRect(itemInWindow)]);
  Check(shownMenu != magnification && ![magnification.itemArray containsObject:shownMenu.itemArray.firstObject], [@"A copy, not the menu bar's menu: " stringByAppendingString:where]);
  Check([Facts(shownMenu) isEqual:Facts(magnification)], [@"Same items as Preview > Magnification: " stringByAppendingString:where]);
  Check([shownMenu.title isEqual:magnification.title], where);
  [box removeFromSuperview];
  checked++;
 }
 Check(checked >= 2, @"Scale views of the Preview window checked");
 NSLog(@"%@ PASS: %lu Scale views keep 10 points after the arrows; their label opens Preview > Magnification", language, (unsigned long)checked);
}}
'''
languages = sorted(p.parent.stem for p in (root/'Resources/Interfaces').glob('*.lproj/TSDocument.nib'))
assert len(languages) == 12 and 'Base' in languages, languages
program = program.replace('CONSTANT', constant).replace('METHODS', methods)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory(prefix='TeXShop-toolbar-scale-') as tmp:
    tmp = Path(tmp)
    app = tmp/'ToolbarScaleTest.app'; mac = app/'Contents/MacOS'; mac.mkdir(parents=True)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.texshop.ToolbarScaleTest.'+tmp.name,
        'CFBundleExecutable': 'ToolbarScaleTest', 'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'CFBundleDevelopmentRegion': 'en'}))
    for language in languages:
        res = app/f'Contents/Resources/{language}.lproj'; res.mkdir(parents=True)
        for nib in ('TSDocument.nib', 'MainMenu.nib'):
            source = root/f'Resources/Interfaces/{language}.lproj/{nib}'
            if source.exists():
                (res/nib).mkdir()
                shutil.copy(source/'keyedobjects.nib', res/nib)
    source = tmp/'Test.m'; source.write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', *include_args(root), '-I'+str(root/'Tests'),
                    '-framework', 'Cocoa', '-framework', 'PDFKit', str(source), '-o', str(mac/'ToolbarScaleTest')], check=True)
    home = tmp/'Home'; (home/'Library/Preferences').mkdir(parents=True)
    try:
        for language in languages:
            locale = 'en' if language == 'Base' else language
            result = subprocess.run([str(mac/'ToolbarScaleTest'), language, '-AppleLanguages', f'({locale})'],
                                    env={**os.environ, 'CFFIXED_USER_HOME': str(home), 'TMPDIR': str(tmp)}, capture_output=True, text=True)
            sys.stderr.write('\n'.join(line for line in result.stderr.splitlines() if 'PASS' in line or 'FAIL' in line) + '\n')
            if result.returncode:
                sys.stderr.write(result.stderr)
                sys.exit(result.returncode)
    finally:
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(app)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
