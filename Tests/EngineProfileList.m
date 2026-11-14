// The sheet that applies an engine profile in Settings and the window of the second step of first launch
// (TSEngineProfileSheet in TSPreferences.m), with the list of what a profile sets (TSEngineProfileList), as the
// production code builds them, never shown. run-engine-profile-list.py compiles the production section between its
// BEGIN and END lines into ProductionList.inc, runs this probe in each language and compares what it reports with the
// profiles, the settings in use and the strings of each language.
// Usage: EngineProfileList <Interfaces folder> <settings.json> <language> ...
// Writes one JSON object per language to standard output.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "MemoryDefaults.h"
#import "TSPreferenceProfile.h"
#import "globals.h"

static NSString *Interfaces, *Language;
static NSMutableDictionary<NSString *, NSDictionary *> *Tables;
static IMP OriginalLocalized;
// The strings of the language under test: its own table, or, for English and a table it does not have, Base.
static NSString *Localized(NSBundle *self, SEL _cmd, NSString *key, NSString *value, NSString *table) {
    if (self != NSBundle.mainBundle) return ((NSString *(*)(id, SEL, NSString *, NSString *, NSString *))OriginalLocalized)(self, _cmd, key, value, table);
    NSString *name = table ?: @"Localizable", *id = [NSString stringWithFormat:@"%@/%@", Language, name];
    if (Tables[id] == nil) {
        NSString *folder = [Language isEqual:@"Base"] && ![name isEqual:@"SettingsCategories"] ? @"en" : Language;
        NSString *path = [NSString stringWithFormat:@"%@/%@.lproj/%@.strings", Interfaces, folder, name];
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) path = [NSString stringWithFormat:@"%@/Base.lproj/%@.strings", Interfaces, name];
        Tables[id] = [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] propertyListFromStringsFileFormat] ?: @{};
    }
    return Tables[id][key] ?: value ?: key;
}

#include "ProductionList.inc"

static NSView *Find(NSView *root, NSString *identifier) {
    if ([root.identifier isEqual:identifier]) return root;
    for (NSView *view in root.subviews) { NSView *found = Find(view, identifier); if (found) return found; }
    return nil;
}
// A frame in the coordinates of the window: x, y from the bottom, width, height.
static NSArray *Frame(NSView *view) {
    if (view == nil) return @[];
    NSRect r = [view convertRect:view.bounds toView:nil];
    return @[@(NSMinX(r)), @(NSMinY(r)), @(NSWidth(r)), @(NSHeight(r))];
}
static NSString *ColorName(NSColor *color) {
    if (color == nil) return @"none";
    if ([color isEqual:NSColor.labelColor]) return @"label";
    if ([color isEqual:NSColor.secondaryLabelColor]) return @"secondary";
    if ([color isEqual:NSColor.controlAccentColor] || [color isEqual:[NSColor.controlAccentColor colorWithAlphaComponent:color.alphaComponent]]) return @"accent";
    return color.description;
}
static NSDictionary *Field(NSTextField *field) {
    // What the field needs at its width; a field shorter or narrower than that cuts its text.
    NSSize needs = [field.cell cellSizeForBounds:NSMakeRect(0, 0, field.cell.wraps ? NSWidth(field.frame) : CGFLOAT_MAX, CGFLOAT_MAX)];
    NSAttributedString *shown = field.attributedStringValue;
    NSColor *drawn = shown.length ? [shown attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] : nil;
    return @{@"kind": @"text", @"text": [field.stringValue stringByReplacingOccurrencesOfString:@"\u2060" withString:@""],
             @"color": ColorName(field.textColor), @"drawnColor": ColorName(drawn ?: field.textColor), @"alpha": @((drawn ?: field.textColor).alphaComponent),
             @"struck": @(shown.length && [[shown attribute:NSStrikethroughStyleAttributeName atIndex:0 effectiveRange:NULL] integerValue] != 0),
             @"mono": @(field.font.isFixedPitch), @"wraps": @(field.cell.wraps),
             @"frame": Frame(field), @"cut": @(needs.height > NSHeight(field.frame) + 0.5 || needs.width > NSWidth(field.frame) + 0.5),
             @"hidden": @(field.hiddenOrHasHiddenAncestor)};
}

// What the window shows now: the rows of its list, and where its views are.
static NSDictionary *State(TSEngineProfileSheet *sheet) {
    NSView *content = sheet.window.contentView;
    [content layoutSubtreeIfNeeded];
    NSView *list = Find(content, @"settings.engine-profile-list");
    NSGridView *grid = (NSGridView *)Find(list, @"settings.engine-profile-list.rows");
    NSMutableArray *rows = [NSMutableArray array];
    for (NSInteger r = 0; r < grid.numberOfRows; r++) {
        NSMutableArray *cells = [NSMutableArray array];
        for (NSInteger c = 0; c < grid.numberOfColumns; c++) {
            NSView *view = [grid cellAtColumnIndex:c rowIndex:r].contentView;
            if ([view isKindOfClass:NSButton.class]) {
                NSButton *box = (NSButton *)view;
                [cells addObject:@{@"kind": @"check", @"check": @(box.state == NSControlStateValueOn), @"name": box.accessibilityLabel ?: @"",
                                   @"frame": Frame(box), @"small": @(box.controlSize == NSControlSizeSmall), @"title": box.title,
                                   @"targetIsList": @(box.target == list)}];
            } else if ([view isKindOfClass:NSTextField.class]) [cells addObject:Field((NSTextField *)view)];
            else [cells addObject:@{@"kind": @"empty"}];
        }
        [rows addObject:cells];
    }
    NSView *latexmk = Find(content, @"settings.engine-profile-latexmk");
    return @{@"rows": rows, @"content": @[@(NSWidth(content.bounds)), @(NSHeight(content.bounds))],
             @"ok": Frame(sheet.okButton), @"cancel": Frame(sheet.cancelButton), @"okEnabled": @(sheet.okButton.enabled),
             @"okTitle": sheet.okButton.title, @"cancelTitle": sheet.cancelButton.title,
             @"okKey": sheet.okButton.keyEquivalent, @"cancelKey": sheet.cancelButton.keyEquivalent,
             @"default": @(sheet.window.defaultButtonCell == sheet.okButton.cell),
             @"question": [(NSTextField *)Find(content, @"settings.engine-profile-question") stringValue] ?: @"",
             @"questionFrame": Frame(Find(content, @"settings.engine-profile-question")),
             @"heading": [(NSTextField *)Find(content, @"settings.engine-profile-heading") stringValue] ?: @"",
             @"headingFrame": Frame(Find(content, @"settings.engine-profile-heading")),
             @"box": Frame(Find(content, @"settings.engine-profile-box")), @"list": Frame(list), @"grid": Frame(grid),
             @"latexmk": Frame(latexmk), @"latexmkLabel": Frame(Find(content, @"settings.engine-profile-latexmk-label")),
             @"latexmkSegment": @([(NSSegmentedControl *)latexmk selectedSegment]),
             @"latexmkLabels": @[[(NSSegmentedControl *)latexmk labelForSegment:0] ?: @"", [(NSSegmentedControl *)latexmk labelForSegment:1] ?: @""],
             @"latexmkLabelText": [(NSTextField *)Find(content, @"settings.engine-profile-latexmk-label") stringValue] ?: @"",
             @"popup": Frame(Find(content, @"settings.choose-profile")),
             @"listIdentity": [NSString stringWithFormat:@"%p", list], @"latexmkTarget": [NSString stringWithFormat:@"%p", [(NSControl *)latexmk target]],
             @"toApply": sheet.valuesToApply};
}

// Stands in for the sheet as the target of a button: counts the times a key chooses it.
@interface KeyCounter : NSObject
@property NSUInteger count;
- (void)choose:(id)sender;
@end
@implementation KeyCounter
- (void)choose:(id)sender { self.count++; }
@end
static BOOL KeyChooses(TSEngineProfileSheet *sheet, NSButton *button, NSString *key, unsigned short code) {
    id target = button.target; SEL action = button.action;
    KeyCounter *counter = [KeyCounter new];
    button.target = counter; button.action = @selector(choose:);
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                  windowNumber:sheet.window.windowNumber context:nil characters:key charactersIgnoringModifiers:key isARepeat:NO keyCode:code];
    [sheet.window performKeyEquivalent:event];
    button.target = target; button.action = action;
    return counter.count > 0;
}
static NSDictionary *Keys(TSEngineProfileSheet *sheet) {
    return @{@"return": @(KeyChooses(sheet, sheet.okButton, @"\r", 36)), @"escape": @(KeyChooses(sheet, sheet.cancelButton, @"\e", 53))};
}
// The checkboxes of the list, by row.
static NSDictionary<NSNumber *, NSButton *> *Boxes(TSEngineProfileSheet *sheet) {
    NSGridView *grid = (NSGridView *)Find(sheet.list, @"settings.engine-profile-list.rows");
    NSMutableDictionary *boxes = [NSMutableDictionary dictionary];
    for (NSInteger r = 0; r < grid.numberOfRows; r++) {
        NSView *view = [grid cellAtColumnIndex:0 rowIndex:r].contentView;
        if ([view isKindOfClass:NSButton.class]) boxes[@(r)] = (NSButton *)view;
    }
    return boxes;
}
static NSArray *Sorted(NSDictionary *boxes) { return [boxes.allKeys sortedArrayUsingSelector:@selector(compare:)]; }
static void ChooseLatexmk(TSEngineProfileSheet *sheet, NSInteger segment) {
    sheet.latexmkChoice.selectedSegment = segment;
    [sheet.latexmkChoice sendAction:sheet.latexmkChoice.action to:sheet.latexmkChoice.target];
}

// The parent a sheet ends on: records the answer the buttons give.
@interface RecordingParent : NSObject
@property NSModalResponse answer;
@property NSUInteger answers;
- (void)endSheet:(NSWindow *)sheet returnCode:(NSModalResponse)code;
@end
@implementation RecordingParent
- (void)endSheet:(NSWindow *)sheet returnCode:(NSModalResponse)code { self.answer = code; self.answers++; }
@end
static NSWindow *ParentedSheet;
static RecordingParent *Parent;
static IMP OriginalSheetParent;
static id SheetParent(NSWindow *self, SEL _cmd) {
    if (self == ParentedSheet) return Parent;
    return ((id (*)(id, SEL))OriginalSheetParent)(self, _cmd);
}

int main(int argc, char **argv) { @autoreleasepool {
    Method localized = class_getInstanceMethod(NSBundle.class, @selector(localizedStringForKey:value:table:));
    OriginalLocalized = method_setImplementation(localized, (IMP)Localized);
    OriginalSheetParent = method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(sheetParent)), (IMP)SheetParent);
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    Interfaces = @(argv[1]);
    Tables = [NSMutableDictionary dictionary];
    NSDictionary *input = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] options:0 error:NULL];
    for (int i = 3; i < argc; i++) {
        Language = @(argv[i]);
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        // The sheet in Settings: each profile in each form, against each of the settings in use; latexmk chosen the
        // other way and back.
        NSMutableArray *sheets = [NSMutableArray array];
        for (NSString *name in input[@"scenarios"]) {
            if (![input[@"scenarioLanguages"][name] containsObject:Language]) continue;
            TSMemoryDefaults *inUse = [TSMemoryDefaults new];
            [inUse registerDefaults:input[@"factory"]];
            [inUse.values addEntriesFromDictionary:input[@"scenarios"][name]];
            for (NSArray<NSNumber *> *section in TSEngineProfileMenuSections()) for (NSNumber *profile in section) for (NSNumber *on in @[@NO, @YES]) {
                TSEngineProfileSheet *sheet = [[TSEngineProfileSheet alloc] initWithProfile:profile.integerValue latexmk:on.boolValue settings:inUse];
                NSMutableArray *states = [NSMutableArray arrayWithObject:State(sheet)];
                ChooseLatexmk(sheet, !on.boolValue); [states addObject:State(sheet)];
                ChooseLatexmk(sheet, on.boolValue); [states addObject:State(sheet)];
                NSDictionary *keys = Keys(sheet);
                // Values turned off: the first two that change; latexmk chosen the other way and back; then every one
                // off, and the first turned on again. Each step says which rows it clicked.
                NSMutableArray *steps = [NSMutableArray array];
                if ([input[@"stepLanguages"] containsObject:Language]) {
                    NSArray *rows = Sorted(Boxes(sheet));
                    NSArray *first = [rows subarrayWithRange:NSMakeRange(0, MIN(2, rows.count))];
                    for (NSNumber *r in first) [Boxes(sheet)[r] performClick:nil];
                    [steps addObject:@{@"clicked": first, @"state": State(sheet), @"keys": Keys(sheet)}];
                    ChooseLatexmk(sheet, !on.boolValue); [steps addObject:@{@"clicked": @[], @"state": State(sheet), @"keys": Keys(sheet)}];
                    ChooseLatexmk(sheet, on.boolValue); [steps addObject:@{@"clicked": @[], @"state": State(sheet), @"keys": Keys(sheet)}];
                    NSMutableArray *rest = [NSMutableArray array];
                    NSDictionary *boxes = Boxes(sheet);
                    for (NSNumber *r in Sorted(boxes)) if ([(NSButton *)boxes[r] state] == NSControlStateValueOn) { [rest addObject:r]; [boxes[r] performClick:nil]; }
                    [steps addObject:@{@"clicked": rest, @"state": State(sheet), @"keys": Keys(sheet)}];
                    NSArray *again = rows.count ? @[rows[0]] : @[];
                    for (NSNumber *r in again) [Boxes(sheet)[r] performClick:nil];
                    [steps addObject:@{@"clicked": again, @"state": State(sheet), @"keys": Keys(sheet)}];
                }
                [sheets addObject:@{@"scenario": name, @"profile": profile, @"latexmk": on, @"states": states, @"steps": steps, @"keys": keys}];
            }
        }
        result[@"sheets"] = sheets;
        // OK and Cancel end the sheet on its parent with their answers.
        TSEngineProfileSheet *answering = [[TSEngineProfileSheet alloc] initWithProfile:TSEngineProfilePdfLaTeX latexmk:NO settings:[TSMemoryDefaults new]];
        ParentedSheet = answering.window; Parent = [RecordingParent new];
        [answering.okButton performClick:nil];
        NSModalResponse okAnswer = Parent.answer;
        [answering.cancelButton performClick:nil];
        result[@"answers"] = @{@"ok": @(okAnswer), @"cancel": @(Parent.answer), @"count": @(Parent.answers)};
        ParentedSheet = nil;
        // First launch: the profile chosen beforehand, then each profile in the menu, with latexmk chosen and not.
        TSEngineProfileSheet *choice = [[TSEngineProfileSheet alloc] initChoosingProfile:TSEngineProfileUpLaTeXDvipdfmx];
        NSPopUpButton *popup = choice.profileMenu;
        NSMutableArray *menu = [NSMutableArray array];
        for (NSMenuItem *item in popup.itemArray) if (!item.isSeparatorItem) [menu addObject:@(item.tag)];
        NSMutableArray *choices = [NSMutableArray arrayWithObject:@{@"profile": @(popup.selectedTag), @"states": @[State(choice)], @"keys": Keys(choice)}];
        for (NSNumber *tag in input[@"choiceOrder"]) {
            [popup selectItemWithTag:tag.integerValue];
            [popup sendAction:popup.action to:popup.target];
            NSMutableArray *states = [NSMutableArray arrayWithObject:State(choice)];
            ChooseLatexmk(choice, 1); [states addObject:State(choice)];
            ChooseLatexmk(choice, 0); [states addObject:State(choice)];
            [choices addObject:@{@"profile": tag, @"selected": @(popup.selectedTag), @"states": states}];
        }
        result[@"choices"] = choices;
        result[@"menu"] = menu;
        result[@"language"] = Language;
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
        fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout); fflush(stdout);
    }
} return 0; }
