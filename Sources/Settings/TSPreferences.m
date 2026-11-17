/*
 * SUUpdate = KOCHSU
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2007 Richard Koch
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * $Id: TSPreferences.m 254 2007-06-03 21:09:25Z fingolfin $
 *
 * Created by dirk on Thu Dec 07 2000.
 *
 */
#import "TSShortcutPaneController.h"
#import "TSPreferences+Panes.h"


#import "UseMitsu.h"
#import "UseSparkle.h"

#import "TSPreferences+LiveSettings.h"
#import "TSSettingsWindowController.h"
#import "TSEnginePathDiscovery.h"
#import "TSPreferenceProfile.h"
#import "TSPreferenceInput.h"
#import "TSAdvancedFindSettings.h"
#import "TSSourceFormatRanges.h"
#import "TSColorSupport.h"
#import "TSInvisibleCharacters.h"
#import "TSDockIconController.h"
#import "TSKeyboardShortcuts.h"
#import "TSSpellSupport.h"
#import "TSSpellingLanguage.h"
#import "TSWindowManager.h"
#import "TSEncodingSupport.h"
#import "globals.h"
#import "HelpDocuments.h"
#import "TSPreviewWindow.h"
#import "TSSettingsChangeNote.h"
#import "TSPreferenceEffects.h"
#import "TSAppDelegate.h" // mitsu 1.29 (O)
#import "TSDocument.h"
#import "TSConsoleWindow.h"
#ifdef USESPARKLE
    #import "TSSparkleController.h"
#endif

//#import "MyPDFView.h" // mitsu 1.29 (O)

// SUD reads the domain named by the bundle identifier, so whole-domain writes
// must target that same domain. A fixed @"TeXShop" overwrote the official
// build's settings whenever a build with another identifier ran for the first time.
static NSString *TSPreferencesDomainName(void)
{
	return [[NSBundle mainBundle] bundleIdentifier] ?: @"TeXShop";
}


typedef NS_CLOSED_ENUM(NSUInteger, TSSettingsFontDestination) {
    TSSettingsFontNone, TSSettingsFontDocument, TSSettingsFontConsole
};

@interface TSPreferences () <NSWindowDelegate, NSTextFieldDelegate, NSMenuDelegate, TSSettingsWindowDelegate>
@property (strong) TSSettingsWindowController *settingsController;
@property (copy) NSArray<TSPrefPaneController *> *preferencePanes;
@property TSSettingsFontDestination fontEditingContext;
@property (strong) NSMapTable<NSControl *, TSPreferenceInput *> *inputRules;
@property (strong) TSPreferenceEditing *inputEditing;
@property BOOL inputErrorPresented;
@property BOOL ownsFontPanel;
@property BOOL endingPreferences;
@property BOOL quittingPreferences;
@property NSUInteger enginePathSearchGeneration;
@property BOOL initialEnginePathSearchPending;
@property (weak) NSButton *enginePathSearchButton;
// The settings a profile left when it was applied with a value that changes turned off. While the settings stay so,
// the menu shows Custom, even when they happen to be those of another profile.
@property (copy) NSDictionary<TSPreferenceKey, id> *engineProfileLeftSettings;
- (void)searchEnginePathsForInitialSetup:(BOOL)initial sender:(NSButton *)sender;
- (void)chooseInitialEngineProfileModal:(BOOL)modal;
- (void)refreshRuntimePreferences;
@end

// BEGIN engine profile list
// The settings an engine profile sets, as Settings names them, each with the value the profile gives it. Shown in
// the sheet that applies a profile, where it is compared with the settings in use: each value that changes has a
// checkbox before its name, on at first, and a dot before the value; the others are dimmed. A value turned off is
// gray and struck through, its dot faint, and keeps the setting in use; with every one of them off the sheet cannot
// apply. On first launch nothing is marked and everything is set. The latexmk choice, and on first launch the
// profile menu, replace the list at once; the values turned off stay off.
@interface TSEngineProfileList : NSView
- (instancetype)initWithProfile:(TSEngineProfile)profile latexmk:(BOOL)latexmk settings:(NSUserDefaults *)settings;
@property (readonly) TSEngineProfile profile;
@property (readonly) BOOL latexmk;
// The button that applies: it cannot be chosen while every value that changes is turned off.
@property (nonatomic, weak) NSButton *applyButton;
// Called when the list changes its height.
@property (copy) void (^heightChanged)(void);
// What applying writes: the values of the profile in the form chosen, but for those turned off.
@property (readonly) NSDictionary<TSPreferenceKey, id> *valuesToApply;
// Whether a value that changes is turned off: then the settings no longer follow the profile.
@property (readonly) BOOL keepsChangedValues;
- (IBAction)changeLatexmk:(NSSegmentedControl *)sender;
- (IBAction)changeProfile:(NSPopUpButton *)sender;
@end

static CGFloat const TSEngineProfileListWidth = 450, TSEngineProfileListNameWidth = 200, TSEngineProfileListDotWidth = 12;

// One row: the name of the setting, the value shown, whether the value is a command, whether applying the profile
// changes the setting, and the keys the row writes. In Settings order: Typesetting, then Documents and Spelling for
// the Japanese profiles. The names are short forms of those in Settings, each on one line.
static NSArray<NSArray *> *TSEngineProfileListRows(TSEngineProfile profile, BOOL latexmk, NSUserDefaults *settings)
{
    NSDictionary<TSPreferenceKey, id> *values = TSEngineProfileValues(profile, latexmk);
    if (values.count == 0) return @[];
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *(^name)(NSString *) = ^NSString *(NSString *key) { return [bundle localizedStringForKey:key value:nil table:@"SettingsCategories"]; };
    NSString *(^onOff)(TSPreferenceKey) = ^NSString *(TSPreferenceKey key) {
        return [values[key] boolValue] ? NSLocalizedString(@"On", @"Engine profile list: a setting turned on") : NSLocalizedString(@"Off", @"Engine profile list: a setting turned off");
    };
    NSMutableArray *rows = [NSMutableArray array];
    void (^add)(NSString *, NSString *, BOOL, TSPreferenceKey) = ^(NSString *setting, NSString *shown, BOOL command, TSPreferenceKey key) {
        [rows addObject:@[setting, shown, @(command), @(settings != nil && !TSEngineProfileSame([settings objectForKey:key], values[key])), @[key]]];
    };
    // Only the commands of the method the profile chooses are written.
    BOOL direct = values[LatexCommandKey] != nil;
    TSPreferenceKey tex = direct ? TexCommandKey : TexGSCommandKey, latex = direct ? LatexCommandKey : LatexGSCommandKey;
    add(NSLocalizedString(@"Engine profile row: Typesetting Method", @"Engine profile list: Typesetting Method of Settings > Typesetting"),
        name(direct ? @"group.typesetting.4.title" : @"group.typesetting.5.title"), NO, DefaultScriptKey);
    add(NSLocalizedString(@"Engine profile row: plain TeX", @"Engine profile list: the plain TeX command"), values[tex], YES, tex);
    add(NSLocalizedString(@"Engine profile row: LaTeX", @"Engine profile list: the LaTeX command"), values[latex], YES, latex);
    add(NSLocalizedString(@"Engine profile row: kpsewhich", @"Engine profile list: the kpsewhich command of Settings > Typesetting, named as there"), values[KpsetoolKey], YES, KpsetoolKey);
    add(NSLocalizedString(@"Engine profile row: BibTeX Engine", @"Engine profile list: BibTeX Engine of Settings > Typesetting"), values[BibTeXengineKey], YES, BibTeXengineKey);
    add(NSLocalizedString(@"Engine profile row: Index Program", @"Engine profile list: Index Program of Settings > Typesetting"), values[MakeIndexEngineKey], YES, MakeIndexEngineKey);
    add(NSLocalizedString(@"Engine profile row: MetaPost", @"Engine profile list: the MetaPost command"), values[MetaPostEngineKey], YES, MetaPostEngineKey);
    add(NSLocalizedString(@"Engine profile row: Convert to \\UTF / \\CID", @"Engine profile list: the conversion to the \\UTF and \\CID commands of the otf package, of Settings > Typesetting"),
        onOff(ptexUtfOutputEnabledKey), NO, ptexUtfOutputEnabledKey);
    NSString *encoding = values[EncodingKey];
    if (encoding != nil) {
        add(NSLocalizedString(@"Engine profile row: New Document Encoding", @"Engine profile list: the encoding for new documents of Settings > Documents"),
            NSLocalizedStringFromTable(encoding, @"Encodings", @"Fetch localized encoding name"), NO, EncodingKey);
        add(NSLocalizedString(@"Engine profile row: UTF-8-MAC Conversion", @"Engine profile list: the automatic conversion of UTF-8-MAC to UTF-8 of Settings > Documents"),
            onOff(AutomaticUTF8MACtoUTF8ConversionKey), NO, AutomaticUTF8MACtoUTF8ConversionKey);
    }
    if (values[spellingAutomaticDefaultKey] != nil) {
        // The dictionary menu shows Automatic Language whenever the automatic choice is on, whatever language is stored.
        [rows addObject:@[NSLocalizedString(@"Engine profile row: Dictionary", @"Engine profile list: Dictionary of Settings > Spelling"), NSLocalizedString(@"Automatic Language", @""), @NO,
                          @(settings != nil && ![settings boolForKey:spellingAutomaticDefaultKey]), @[spellingAutomaticDefaultKey, spellingLanguageDefaultKey]]];
    }
    return rows;
}

static NSTextField *TSEngineProfileListField(NSString *text, NSFont *font, CGFloat width)
{
    NSTextField *field = [NSTextField wrappingLabelWithString:text];
    field.font = font;
    field.selectable = NO;
    field.preferredMaxLayoutWidth = width;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

@implementation TSEngineProfileList {
    NSUserDefaults *_settings;
    NSGridView *_grid;
    // The keys of the values turned off, kept while latexmk is turned on and off.
    NSMutableSet<TSPreferenceKey> *_kept;
    // For each row: its keys, and its checkbox, dot, name and value, to show whether it is set.
    NSArray<NSArray *> *_rows;
    NSArray<NSDictionary<NSString *, id> *> *_rowViews;
}

static CGFloat const TSEngineProfileListPadding = 12;
// How far the dot of 7 points is raised to stand at the middle of a line of 11 points.
static CGFloat const TSEngineProfileListDotRaise = 1.5;

- (instancetype)initWithProfile:(TSEngineProfile)profile latexmk:(BOOL)latexmk settings:(NSUserDefaults *)settings
{
    self = [super initWithFrame:NSMakeRect(0, 0, TSEngineProfileListWidth + 2 * TSEngineProfileListPadding, 0)];
    if (self == nil) return nil;
    self.identifier = @"settings.engine-profile-list";
    _profile = profile;
    _latexmk = latexmk;
    _settings = settings;
    _kept = [NSMutableSet set];
    [self showRows];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setApplyButton:(NSButton *)button
{
    _applyButton = button;
    [self enableApply];
}

- (NSDictionary<TSPreferenceKey, id> *)valuesToApply
{
    NSMutableDictionary *values = [TSEngineProfileValues(_profile, _latexmk) mutableCopy];
    [values removeObjectsForKeys:_kept.allObjects];
    return values;
}

- (BOOL)keepsChangedValues
{
    for (NSUInteger i = 0; i < _rows.count; i++)
        if ([_rows[i][3] boolValue] && ![self rowIsSet:i]) return YES;
    return NO;
}

- (BOOL)rowIsSet:(NSUInteger)index
{
    return ![_kept intersectsSet:[NSSet setWithArray:_rows[index][4]]];
}

// The grid of the rows, and, for each row, its views by role.
- (NSGridView *)gridForProfile:(TSEngineProfile)profile latexmk:(BOOL)latexmk rows:(NSArray<NSArray *> **)rowsOut views:(NSArray **)viewsOut
{
    NSArray<NSArray *> *rows = TSEngineProfileListRows(profile, latexmk, _settings);
    CGFloat size = NSFont.smallSystemFontSize;
    NSFont *font = [NSFont systemFontOfSize:size], *mono = [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
    BOOL marks = _settings != nil;
    CGFloat nameWidth = 0;
    for (NSArray *row in rows) nameWidth = MAX(nameWidth, ceil([row[0] sizeWithAttributes:@{NSFontAttributeName: font}].width) + 4);
    nameWidth = MIN(nameWidth, TSEngineProfileListNameWidth);
    CGFloat const spacing = 12, checkWidth = marks ? 20 : 0, dotWidth = TSEngineProfileListDotWidth;
    CGFloat valueWidth = TSEngineProfileListWidth - checkWidth - (marks ? dotWidth : 0) - nameWidth - spacing;
    NSMutableArray *gridRows = [NSMutableArray array], *views = [NSMutableArray array];
    for (NSArray *row in rows) {
        BOOL command = [row[2] boolValue], changes = [row[3] boolValue];
        // A command breaks only at its spaces: a word joiner after each hyphen and slash keeps an option whole.
        NSString *value = command ? [[row[1] stringByReplacingOccurrencesOfString:@"-" withString:@"-\u2060"]
                                        stringByReplacingOccurrencesOfString:@"/" withString:@"/\u2060"] : row[1];
        NSMutableDictionary *rowViews = [NSMutableDictionary dictionary];
        NSMutableArray *cells = [NSMutableArray array];
        // A name stands on one line.
        NSTextField *nameField = [NSTextField labelWithString:row[0]];
        nameField.font = font;
        nameField.selectable = NO;
        nameField.translatesAutoresizingMaskIntoConstraints = NO;
        rowViews[@"name"] = nameField;
        NSTextField *valueField = TSEngineProfileListField(value, command ? mono : font, valueWidth);
        rowViews[@"value"] = valueField;
        if (marks) {
            if (changes) {
                NSButton *check = [NSButton checkboxWithTitle:@"" target:self action:@selector(changeRow:)];
                check.controlSize = NSControlSizeSmall;
                [check sizeToFit];
                check.identifier = @"settings.engine-profile-list.set";
                check.tag = (NSInteger)views.count;
                check.accessibilityLabel = row[0];
                check.state = [_kept intersectsSet:[NSSet setWithArray:row[4]]] ? NSControlStateValueOff : NSControlStateValueOn;
                check.translatesAutoresizingMaskIntoConstraints = NO;
                rowViews[@"check"] = check;
                [cells addObject:check];
            } else [cells addObject:NSGridCell.emptyContentView];
        }
        NSTextField *dot = nil;
        if (marks) {
            dot = TSEngineProfileListField(changes ? @"\u25CF" : @"", [NSFont systemFontOfSize:7], dotWidth);
            dot.identifier = changes ? @"settings.engine-profile-list.changes" : @"settings.engine-profile-list.same";
            // VoiceOver reads the checkbox of the row; the dot only repeats it.
            dot.accessibilityElement = NO;
            rowViews[@"dot"] = dot;
        }
        [cells addObject:nameField];
        if (marks) [cells addObject:dot];
        [cells addObject:valueField];
        [gridRows addObject:cells];
        [views addObject:rowViews];
    }
    NSGridView *grid = [NSGridView gridViewWithViews:gridRows];
    grid.identifier = @"settings.engine-profile-list.rows";
    grid.rowSpacing = 5;
    grid.columnSpacing = 0;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    NSInteger column = 0;
    if (marks) [grid columnAtIndex:column++].width = checkWidth;
    NSInteger nameColumn = column++;
    [grid columnAtIndex:nameColumn].width = nameWidth;
    [grid columnAtIndex:nameColumn].trailingPadding = spacing;
    if (marks) [grid columnAtIndex:column++].width = dotWidth;
    [grid columnAtIndex:column].width = valueWidth;
    // The checkbox stands at the middle of the first line of its row; the dot is raised there from the baseline.
    CGFloat middle = (font.ascender + font.descender) / 2;
    for (NSDictionary *rowViews in views) {
        NSView *check = rowViews[@"check"];
        NSTextField *nameField = rowViews[@"name"];
        if (check == nil) continue;
        NSGridCell *cell = [grid cellForView:check];
        cell.yPlacement = NSGridCellPlacementNone;
        cell.customPlacementConstraints = @[[check.centerYAnchor constraintEqualToAnchor:nameField.firstBaselineAnchor constant:-middle]];
    }
    grid.translatesAutoresizingMaskIntoConstraints = YES;
    [grid layoutSubtreeIfNeeded];
    [grid setFrameSize:NSMakeSize(TSEngineProfileListWidth, grid.fittingSize.height)];
    [grid layoutSubtreeIfNeeded];
    if (rowsOut) *rowsOut = rows;
    if (viewsOut) *viewsOut = views;
    return grid;
}

// A row that is set shows its value as the others do; a row turned off is gray, its value struck through.
- (void)styleRow:(NSUInteger)index
{
    NSArray *row = _rows[index];
    NSDictionary *views = _rowViews[index];
    BOOL marks = _settings != nil, changes = [row[3] boolValue], set = [self rowIsSet:index];
    NSColor *color = !marks || (changes && set) ? NSColor.labelColor : NSColor.secondaryLabelColor;
    NSTextField *name = views[@"name"], *value = views[@"value"];
    name.textColor = color;
    NSFont *valueFont = value.font ?: [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    NSMutableDictionary *attributes = [@{NSFontAttributeName: valueFont, NSForegroundColorAttributeName: color} mutableCopy];
    if (changes && !set) attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    value.attributedStringValue = [[NSAttributedString alloc] initWithString:value.stringValue attributes:attributes];
    value.textColor = color;
    NSTextField *dot = views[@"dot"];
    if (dot.stringValue.length) {
        NSColor *dotColor = set ? NSColor.controlAccentColor : [NSColor.controlAccentColor colorWithAlphaComponent:0.35];
        NSFont *dotFont = dot.font ?: [NSFont systemFontOfSize:7];
        dot.attributedStringValue = [[NSAttributedString alloc] initWithString:dot.stringValue attributes:@{NSFontAttributeName: dotFont,
            NSForegroundColorAttributeName: dotColor, NSBaselineOffsetAttributeName: @(TSEngineProfileListDotRaise)}];
        dot.textColor = dotColor;
    }
}

// The list is as tall as its rows; the sheet follows its height.
- (void)showRows
{
    [_grid removeFromSuperview];
    NSArray *rows = nil, *views = nil;
    _grid = [self gridForProfile:_profile latexmk:_latexmk rows:&rows views:&views];
    _rows = rows;
    _rowViews = views;
    [_grid setFrameOrigin:NSMakePoint(TSEngineProfileListPadding, TSEngineProfileListPadding)];
    [self addSubview:_grid];
    for (NSUInteger i = 0; i < _rows.count; i++) [self styleRow:i];
    [self enableApply];
    CGFloat height = NSHeight(_grid.frame) + 2 * TSEngineProfileListPadding;
    if (height == NSHeight(self.frame)) return;
    [self setFrameSize:NSMakeSize(NSWidth(self.frame), height)];
    if (self.heightChanged) self.heightChanged();
}

// Applying writes nothing when every value that changes is turned off, and cannot be chosen then, by Return either.
- (void)enableApply
{
    BOOL changes = NO, set = NO;
    for (NSUInteger i = 0; i < _rows.count; i++) {
        if (![_rows[i][3] boolValue]) continue;
        changes = YES;
        if ([self rowIsSet:i]) set = YES;
    }
    self.applyButton.enabled = set || !changes;
}

- (IBAction)changeRow:(NSButton *)sender
{
    NSUInteger index = (NSUInteger)sender.tag;
    if (index >= _rows.count) return;
    if (sender.state == NSControlStateValueOn) [_kept minusSet:[NSSet setWithArray:_rows[index][4]]];
    else [_kept addObjectsFromArray:_rows[index][4]];
    [self styleRow:index];
    [self enableApply];
}

- (IBAction)changeLatexmk:(NSSegmentedControl *)sender
{
    _latexmk = sender.selectedSegment == 1;
    [self showRows];
}

- (IBAction)changeProfile:(NSPopUpButton *)sender
{
    if (TSEngineProfileTitle(sender.selectedTag) == nil) return;
    _profile = sender.selectedTag;
    [self showRows];
}
@end

// The engine profiles offered to choose on first launch: every profile but those under Other.
static NSPopUpButton *TSEngineProfileChoicePopup(TSEngineProfile selected)
{
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.identifier = @"settings.choose-profile";
    popup.autoenablesItems = NO;
    NSArray *sections = TSEngineProfileMenuSections();
    for (NSUInteger i = 0; i + 1 < sections.count; i++) {
        if (i > 0) { NSMenuItem *separator = NSMenuItem.separatorItem; separator.tag = -1; [popup.menu addItem:separator]; }
        for (NSNumber *profile in sections[i]) {
            NSString *title = TSEngineProfileTitle(profile.integerValue);
            if (title == nil) continue;
            NSMenuItem *item = [popup.menu addItemWithTitle:title action:NULL keyEquivalent:@""];
            item.tag = profile.integerValue;
        }
    }
    [popup selectItemWithTag:selected];
    [popup sizeToFit];
    return popup;
}

@interface TSEngineProfileSheetContent : NSView
@end
@implementation TSEngineProfileSheetContent
- (BOOL)isFlipped { return YES; }
@end

// The sheet that applies an engine profile in Settings, and the window of the second step of first launch. From the
// top: the question, on first launch the profile menu, the latexmk choice, the list under its heading in a box like
// the groups of Settings, and Cancel and OK at the bottom right, OK the default button. The window is as tall as the
// list, which changes with latexmk and the profile.
@interface TSEngineProfileSheet : NSObject
// The sheet in Settings: the list compared with the settings in use.
- (instancetype)initWithProfile:(TSEngineProfile)profile latexmk:(BOOL)latexmk settings:(NSUserDefaults *)settings;
// First launch: the profiles in a menu, the profile chosen beforehand selected, latexmk off.
- (instancetype)initChoosingProfile:(TSEngineProfile)profile;
@property (readonly) NSWindow *window;
@property (readonly) TSEngineProfileList *list;
@property (readonly) NSSegmentedControl *latexmkChoice;
// The profile menu of first launch; nil in Settings.
@property (readonly) NSPopUpButton *profileMenu;
@property (readonly) NSButton *okButton, *cancelButton;
// What OK writes.
@property (readonly) NSDictionary<TSPreferenceKey, id> *valuesToApply;
- (void)beginSheetForWindow:(NSWindow *)parent completionHandler:(void (^)(NSModalResponse response))handler;
- (NSModalResponse)runModal;
@end

@implementation TSEngineProfileSheet {
    NSTextField *_question, *_latexmkLabel, *_heading;
    NSBox *_box;
}

static CGFloat const TSEngineProfileSheetMargin = 20;

- (instancetype)initWithQuestion:(NSString *)question profile:(TSEngineProfile)profile latexmk:(BOOL)latexmk
                        settings:(NSUserDefaults *)settings menu:(BOOL)menu
{
    self = [super init];
    if (self == nil) return nil;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200)
                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:YES];
    _window.identifier = @"settings.engine-profile-sheet";
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.releasedWhenClosed = NO;
    _window.title = question;
    // On first launch it stands alone, as an alert does: no title and no window buttons.
    for (NSNumber *kind in @[@(NSWindowCloseButton), @(NSWindowMiniaturizeButton), @(NSWindowZoomButton)])
        [_window standardWindowButton:kind.unsignedIntegerValue].hidden = YES;
    _window.contentView = [[TSEngineProfileSheetContent alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    NSView *content = _window.contentView;

    _question = [NSTextField wrappingLabelWithString:question];
    _question.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    _question.selectable = NO;
    _question.identifier = @"settings.engine-profile-question";
    [content addSubview:_question];
    if (menu) {
        _profileMenu = TSEngineProfileChoicePopup(profile);
        [content addSubview:_profileMenu];
        profile = _profileMenu.selectedTag;
    }
    _latexmkLabel = [NSTextField labelWithString:NSLocalizedString(@"Run LaTeX:", @"Engine profile sheet: label of the latexmk choice")];
    _latexmkLabel.identifier = @"settings.engine-profile-latexmk-label";
    [content addSubview:_latexmkLabel];
    _latexmkChoice = [NSSegmentedControl segmentedControlWithLabels:@[NSLocalizedString(@"Without latexmk", @"Engine profile sheet: run the engine once"),
                                                                      NSLocalizedString(@"With latexmk", @"Engine profile sheet: run latexmk")]
                                                        trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:NULL];
    _latexmkChoice.identifier = @"settings.engine-profile-latexmk";
    _latexmkChoice.selectedSegment = latexmk ? 1 : 0;
    _latexmkChoice.accessibilityLabel = _latexmkLabel.stringValue;
    [content addSubview:_latexmkChoice];
    _heading = [NSTextField labelWithString:NSLocalizedString(@"Values to Set", @"Engine profile sheet: heading of the list")];
    _heading.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    _heading.identifier = @"settings.engine-profile-heading";
    [content addSubview:_heading];
    _list = [[TSEngineProfileList alloc] initWithProfile:profile latexmk:latexmk settings:settings];
    _box = [[NSBox alloc] initWithFrame:NSZeroRect];
    _box.identifier = @"settings.engine-profile-box";
    _box.titlePosition = NSNoTitle;
    _box.boxType = NSBoxCustom;
    _box.borderWidth = 0;
    _box.contentViewMargins = NSZeroSize;
    // As the groups of Settings.
    _box.fillColor = [NSColor colorWithName:@"EngineProfileListFill" dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
        return [NSColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.055 : 0.04];
    }];
    _box.cornerRadius = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 12 : 10;
    [_box.contentView addSubview:_list];
    [content addSubview:_box];
    _latexmkChoice.target = _list;
    _latexmkChoice.action = @selector(changeLatexmk:);
    _profileMenu.target = _list;
    _profileMenu.action = @selector(changeProfile:);

    _cancelButton = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"") target:self action:@selector(finish:)];
    _cancelButton.keyEquivalent = @"\e";
    _cancelButton.identifier = @"settings.engine-profile-cancel";
    _okButton = [NSButton buttonWithTitle:NSLocalizedString(@"OK", @"") target:self action:@selector(finish:)];
    _okButton.keyEquivalent = @"\r";
    _okButton.identifier = @"settings.engine-profile-ok";
    [content addSubview:_cancelButton];
    [content addSubview:_okButton];
    _window.defaultButtonCell = _okButton.cell;
    _list.applyButton = _okButton;
    __weak __typeof(self) weakSelf = self;
    _list.heightChanged = ^{ [weakSelf layOut]; };
    [self layOut];
    return self;
}

- (instancetype)initWithProfile:(TSEngineProfile)profile latexmk:(BOOL)latexmk settings:(NSUserDefaults *)settings
{
    NSString *question = [NSString stringWithFormat:NSLocalizedString(@"Apply the “%@” profile?", @"Engine profile sheet"), TSEngineProfileTitle(profile)];
    return [self initWithQuestion:question profile:profile latexmk:latexmk settings:settings menu:NO];
}

- (instancetype)initChoosingProfile:(TSEngineProfile)profile
{
    return [self initWithQuestion:NSLocalizedString(@"Choose an Engine Profile", @"") profile:profile latexmk:NO settings:nil menu:YES];
}

// From the top down, as wide as the box of the list; the top of the window stays where it is.
- (void)layOut
{
    CGFloat const margin = TSEngineProfileSheetMargin;
    CGFloat inner = NSWidth(_list.frame), width = inner + 2 * margin;
    CGFloat y = margin;
    _question.preferredMaxLayoutWidth = inner;
    _question.frame = NSMakeRect(margin, y, inner, _question.fittingSize.height);
    y = NSMaxY(_question.frame) + 14;
    if (_profileMenu != nil) {
        [_profileMenu sizeToFit];
        [_profileMenu setFrameOrigin:NSMakePoint(margin - 2, y)];
        y = NSMaxY(_profileMenu.frame) + 10;
    }
    [_latexmkLabel sizeToFit];
    [_latexmkChoice sizeToFit];
    CGFloat choiceHeight = NSHeight(_latexmkChoice.frame);
    [_latexmkLabel setFrameOrigin:NSMakePoint(margin, y + round((choiceHeight - NSHeight(_latexmkLabel.frame)) / 2))];
    [_latexmkChoice setFrameOrigin:NSMakePoint(NSMaxX(_latexmkLabel.frame) + 8, y)];
    y += choiceHeight + 16;
    [_heading sizeToFit];
    [_heading setFrameOrigin:NSMakePoint(margin, y)];
    y = NSMaxY(_heading.frame) + 6;
    _box.frame = NSMakeRect(margin, y, inner, NSHeight(_list.frame));
    [_list setFrameOrigin:NSZeroPoint];
    y = NSMaxY(_box.frame) + 20;
    for (NSButton *button in @[_okButton, _cancelButton]) {
        [button sizeToFit];
        [button setFrameSize:NSMakeSize(MAX(NSWidth(button.frame), 80), NSHeight(button.frame))];
    }
    [_okButton setFrameOrigin:NSMakePoint(width - margin - NSWidth(_okButton.frame), y)];
    [_cancelButton setFrameOrigin:NSMakePoint(NSMinX(_okButton.frame) - 12 - NSWidth(_cancelButton.frame), y)];
    y = NSMaxY(_okButton.frame) + margin;
    NSRect frame = [_window frameRectForContentRect:NSMakeRect(0, 0, width, y)];
    frame.origin = NSMakePoint(NSMinX(_window.frame), NSMaxY(_window.frame) - NSHeight(frame));
    [_window setFrame:frame display:_window.visible];
}

- (NSDictionary<TSPreferenceKey, id> *)valuesToApply { return _list.valuesToApply; }

- (IBAction)finish:(NSButton *)sender
{
    NSModalResponse response = sender == _okButton ? NSModalResponseOK : NSModalResponseCancel;
    if (_window.sheetParent != nil) [_window.sheetParent endSheet:_window returnCode:response];
    else if (NSApp.modalWindow == _window) [NSApp stopModalWithCode:response];
}

- (void)beginSheetForWindow:(NSWindow *)parent completionHandler:(void (^)(NSModalResponse))handler
{
    [parent beginSheet:_window completionHandler:handler];
}

- (NSModalResponse)runModal
{
    [_window center];
    NSModalResponse response = [NSApp runModalForWindow:_window];
    [_window orderOut:nil];
    return response;
}
@end
// END engine profile list

@implementation TSPreferences
@synthesize legacySpellCheckButton = _legacySpellCheckButton, settingsHelpDocuments = _settingsHelpDocuments;
/*"
Format of the original prefs file:

_{#position #value}
_{0 version number}
_{1 textView's font}
_{2 pdfView's slider value}
_{3-6 textWindow's frame}
_{7-10 pdfWindow's frame}
_{11 TeX command}
_{12 LaTeX command}
_{13 display method (Apple or GS)}
_{14 GS color}
_{15 preferred TeX command}
"*/

static id _sharedInstance = nil;

/*" This class is implemented as singleton, i.e. there is only one single instance in the runtime. This is the designated accessor method to get the shared instance of the Preferences class.
"*/
+ (id)sharedInstance
{
	if (_sharedInstance == nil)
	{
		_sharedInstance = [[TSPreferences alloc] init];
	}
	return _sharedInstance;
}

- (id)init
{
	if (_sharedInstance != nil) {
//		[super dealloc]; // huh? Weird code; Feb 24, 2009, RMK
		return _sharedInstance;
	}
	_sharedInstance = self;
	// setup the default font here so it's defined when we run for the first time.
	self.documentFont = [NSFont userFontOfSize:12.0];
    self.fontAttributes = nil;
	// self.consoleFont = [NSFont userFixedPitchedFontOfSize:10.0];

	// register for changes in the user defaults
	
	// I now believe this is not needed; Feb 24, 2009 RMK
	// [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDefaultsChanged:) name:NSUserDefaultsDidChangeNotification object:nil];

	return self;
}



//==============================================================================
// target/action methods
//==============================================================================
/*" Connected to the "Preferences..." menu item in Application's main menu.

Loads the .nib file if necessary, fills all the controls with the values from the user defaults and makes the window visible.
"*/
- (IBAction)showPreferences:(id)sender
{
    if ((_prefsWindow.visible || _prefsWindow.miniaturized)) { [_prefsWindow makeKeyAndOrderFront:sender]; return; }
    if (!self.initialEnginePathSearchPending) [self cancelEnginePathDiscovery];
    if (![self prepareSettingsWindow]) return;
    self.endingPreferences = NO;
    self.inputErrorPresented = NO;
    _prefsWindow.delegate = self;
    [self configurePreferenceInputs];
    [[TSDockIconController sharedController] installInPreferencesPane:[self.settingsController viewForCategoryIdentifier:TSSettingsCategoryGeneral]];
    [[TSDockIconController sharedController] restoreSavedIcon];
    [self updateControlsFromUserDefaults:SUD];
    [self PrepareColorPane:SUD];
    [self.settingsController beginSession];
    [_prefsWindow makeKeyAndOrderFront:self];
}

- (void)showKeyboardSettings:(id)sender
{
    [self showPreferences:sender];
    if (self.settingsController == nil) { return; }
    [self.settingsController selectCategoryIdentifier:TSSettingsCategoryKeyboard];
}

- (BOOL)prepareSettingsWindow
{
    if (self.settingsController != nil) return YES;
    self.preferencePanes = [self makeSettingsPanes];
    TSSettingsWindowController *controller = [[TSSettingsWindowController alloc] initWithDefaults:SUD];
    NSWindow *newWindow = controller.window;
    if (newWindow == nil) return NO;
    controller.settingsDelegate = self;
    NSDictionary<TSSettingsCategoryID, NSViewController *> *panes = [self classifySettingsPanes:self.preferencePanes];
    self.settingsChangeNotes = [[TSSettingsChangeNotes alloc] initWithDefaults:SUD launchValues:TSSettingsLaunchValues() bundle:NSBundle.mainBundle];
    self.settingsChangeNotes.hasSourceWindow = ^BOOL { return [[TSWindowManager sharedInstance] activeTextWindow] != nil; };
    self.settingsChangeNotes.hasPDFWindow = ^BOOL {
        for (id document in NSDocumentController.sharedDocumentController.documents)
            if ([document isKindOfClass:TSDocument.class]) {
                NSWindow *preview = ((TSDocument *)document).pdfKitWindow;
                NSWindow *combined = [document fullSplitWindow];
                if (preview.visible || preview.miniaturized || combined.visible || combined.miniaturized) return YES;
            }
        return NO;
    };
    [self.settingsChangeNotes attachToPanes:panes];
    controller.changeNotes = self.settingsChangeNotes;
    NSView *keyboardOptions = panes[TSSettingsCategoryKeyboard].view;
    controller.commandNamesProvider = ^NSArray<NSString *> * {
        return [[TSKeyboardShortcuts sharedController].store settingsSearchCommandNames] ?: @[];
    };
    controller.keyboardPaneProvider = ^NSViewController<TSSettingsKeyboardPane> * {
        TSShortcutPaneController *keyboard = [[TSShortcutPaneController alloc] initWithShortcuts:[TSKeyboardShortcuts sharedController]];
        keyboard.settingsHeader = keyboardOptions;
        return keyboard;
    };
    [controller hostPaneControllers:panes footer:nil];
    _prefsWindow = newWindow;
    self.settingsController = controller;
    // The profile menu follows every change of a profile's settings, wherever it is made.
    if (self.engineProfileWatcher == nil) {
        __weak TSPreferences *weakSelf = self;
        self.engineProfileWatcher = [[TSEngineProfileWatcher alloc] initWithDefaults:SUD handler:^{ [weakSelf refreshEngineProfileFromDefaults:SUD]; }];
    }
    return YES;
}
- (BOOL)settingsMayChangeCategory
{
    if (![self finishPreferenceEditing:YES]) return NO;
    [self releasePreferencePanels];
    return YES;
}
- (void)settingsWillDisplayCategory:(TSSettingsCategoryID)identifier
{
    [self updateSettingsCategory:identifier fromDefaults:SUD];
}
- (void)settingsChangeFont:(NSFontManager *)sender
{
    [self changeFont:sender];
}

//==============================================================================
// Engine file
//==============================================================================

// The engine files that a document's toolbar lists, by name and in the same order.
NSArray<NSString *> *TSEngineFileNames(NSString *folder)
{
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSArray *files = [[fileManager contentsOfDirectoryAtPath:folder error:NULL] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *file in files) {
        BOOL isDirectory = NO;
        if (![file.pathExtension.lowercaseString isEqualToString:@"engine"]) continue;
        if (![fileManager fileExistsAtPath:[folder stringByAppendingPathComponent:file] isDirectory:&isDirectory] || isDirectory) continue;
        [names addObject:file.stringByDeletingPathExtension];
    }
    return names;
}

// Fills an engine menu: the built-in programs given as name and title pairs, then the engine
// files. A document finds an engine file by its name in any case, and a built-in program by its
// name in lowercase. A name that is in neither stays shown until another is chosen: as itself when
// it is one of otherPrograms, which the typesetting also understands, and otherwise as not found.
// No name is shown as None when showsNone. The stored value itself is never changed here.
static void TSFillEngineMenu(NSPopUpButton *popup, NSArray<NSArray<NSString *> *> *programs, NSSet<NSString *> *otherPrograms, NSString *stored, BOOL trims, BOOL showsNone)
{
    NSString *current = trims ? [stored stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : stored;
    NSMenu *menu = popup.menu;
    [menu removeAllItems];
    popup.autoenablesItems = NO;
    NSMenuItem *selected = nil;
    for (NSArray<NSString *> *program in programs) {
        NSMenuItem *item = [menu addItemWithTitle:program[1] action:NULL keyEquivalent:@""];
        item.representedObject = program[0];
        if (selected == nil && [program[0] isEqualToString:current.lowercaseString]) selected = item;
    }
    NSArray<NSString *> *files = TSEngineFileNames([EnginePath stringByStandardizingPath]);
    if (programs.count > 0 && files.count > 0) [menu addItem:NSMenuItem.separatorItem];
    for (NSString *name in files) {
        NSMenuItem *item = [menu addItemWithTitle:name action:NULL keyEquivalent:@""];
        item.representedObject = name;
        if (selected == nil && [name caseInsensitiveCompare:current] == NSOrderedSame) selected = item;
    }
    if (selected == nil && (current.length > 0 || showsNone)) {
        if (menu.numberOfItems > 0) [menu insertItem:NSMenuItem.separatorItem atIndex:0];
        NSString *title = current.length == 0 ? NSLocalizedString(@"None", @"No engine is set")
            : [otherPrograms containsObject:current.lowercaseString] ? current
            : [NSString stringWithFormat:NSLocalizedString(@"%@ (Not Found)", @"An engine file that is not in the Engines folder"), current];
        selected = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
        selected.representedObject = stored;
        [menu insertItem:selected atIndex:0];
    }
    if (selected != nil) [popup selectItem:selected];
}

- (void)refreshDefaultEngineFromDefaults:(NSUserDefaults *)defaults
{
    NSPopUpButton *popup = self.defaultEnginePopup;
    if (popup == nil) return;
    TSFillEngineMenu(popup, @[], [NSSet set], [defaults stringForKey:DefaultEngineKey] ?: @"", NO, NO);
}

// The programs that the Alternate Engine can name besides the engine files, with the names
// that the typesetting understands (TSDocument-Jobs.m), plain TeX before LaTeX.
NSArray<NSArray<NSString *> *> *TSAlternateEnginePrograms(void)
{
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *(^method)(NSString *) = ^NSString *(NSString *key) { return [bundle localizedStringForKey:key value:key table:@"SettingsCategories"]; };
    NSString *format = NSLocalizedString(@"%1$@ (%2$@)", @"A program and its typesetting method, as in plain TeX (Direct PDF)");
    NSArray *methods = @[@[@"pdf", method(@"group.typesetting.4.title")], @[@"", method(@"group.typesetting.5.title")], @[@"personal", method(@"group.typesetting.6.title")]];
    NSMutableArray *programs = [NSMutableArray array];
    for (NSArray *m in methods) {
        [programs addObject:@[[m[0] stringByAppendingString:@"tex"], [NSString stringWithFormat:format, @"plain TeX", m[1]]]];
        [programs addObject:@[[m[0] stringByAppendingString:@"latex"], [NSString stringWithFormat:format, @"LaTeX", m[1]]]];
    }
    return programs;
}

- (void)refreshAlternateEngineFromDefaults:(NSUserDefaults *)defaults
{
    NSPopUpButton *popup = self.alternateEnginePopup;
    if (popup == nil) return;
    // The typesetting trims the setting and also understands bibtex, makeindex and metapost.
    TSFillEngineMenu(popup, TSAlternateEnginePrograms(), [NSSet setWithArray:@[@"bibtex", @"makeindex", @"metapost"]], [defaults stringForKey:AlternateEngineKey] ?: @"", YES, YES);
}

- (IBAction)alternateEngineChosen:(NSPopUpButton *)sender
{
    NSString *name = sender.selectedItem.representedObject;
    if (name.length == 0) return;
    [SUD setObject:name forKey:AlternateEngineKey];
    [self refreshAlternateEngineFromDefaults:SUD];
}

// The menu item that typesets with the Alternate Engine, wherever its shortcut puts it.
static NSMenuItem *TSAlternateTypesetItem(NSMenu *menu)
{
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(doAlternateTypeset:)) return item;
        NSMenuItem *found = item.submenu ? TSAlternateTypesetItem(item.submenu) : nil;
        if (found) return found;
    }
    return nil;
}

// What the info button of the Alternate Engine says: where the command is, its key as the menu
// has it now, and what it does.
NSArray<NSString *> *TSAlternateEngineInfoLines(NSMenu *mainMenu)
{
    NSMenuItem *item = TSAlternateTypesetItem(mainMenu);
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:item.title.length ? item.title : NSLocalizedString(@"Typeset with Alternate Engine", @"")];
    if (item != nil) {
        NSString *menuTitle = item.menu.title;
        NSMenuItem *base = nil;
        if (item.isAlternate)
            for (NSInteger i = [item.menu indexOfItem:item] - 1; i >= 0 && base == nil; i--)
                if (![item.menu itemAtIndex:i].isAlternate) base = [item.menu itemAtIndex:i];
        NSEventModifierFlags held = base ? (item.keyEquivalentModifierMask & ~base.keyEquivalentModifierMask) & (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagCommand) : 0;
        if (base != nil && held != 0) {
            NSMutableString *keys = [NSMutableString string];
            if (held & NSEventModifierFlagControl) [keys appendString:@"⌃"];
            if (held & NSEventModifierFlagOption) [keys appendString:@"⌥"];
            if (held & NSEventModifierFlagShift) [keys appendString:@"⇧"];
            if (held & NSEventModifierFlagCommand) [keys appendString:@"⌘"];
            [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"In the %1$@ menu, this item appears in place of %2$@ while you hold %3$@.", @""), menuTitle, base.title, keys]];
        } else {
            [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"This item is in the %@ menu.", @""), menuTitle]];
        }
        [lines addObject:item.keyEquivalent.length
            ? [NSString stringWithFormat:NSLocalizedString(@"Key: %@", @"The shortcut of a menu item"), TSShortcutDisplayKey(item.keyEquivalent, item.keyEquivalentModifierMask)]
            : NSLocalizedString(@"No key is assigned.", @"")];
    }
    [lines addObject:NSLocalizedString(@"Typesets once with this engine instead of the one chosen in the toolbar.", @"")];
    [lines addObject:NSLocalizedString(@"A % !TEX TS-program line at the top of the document takes precedence.", @"")];
    return lines;
}

// The first line is the heading; each following line is a paragraph.
- (NSViewController *)alternateEngineInfoController
{
    NSArray<NSString *> *lines = TSAlternateEngineInfoLines(NSApp.mainMenu);
    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.alignment = NSLayoutAttributeLeading; stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(14, 16, 16, 16); stack.identifier = @"settings.alternate-engine-info.content";
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSTextField *text = [NSTextField wrappingLabelWithString:lines[i]];
        text.font = i == 0 ? [NSFont boldSystemFontOfSize:NSFont.systemFontSize] : [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        text.textColor = i == 0 ? NSColor.labelColor : NSColor.secondaryLabelColor;
        text.preferredMaxLayoutWidth = 300; text.selectable = NO;
        [text.widthAnchor constraintEqualToConstant:300].active = YES;
        [stack addArrangedSubview:text];
    }
    NSViewController *controller = [NSViewController new];
    controller.view = stack;
    return controller;
}

- (IBAction)showAlternateEngineInfo:(NSButton *)sender
{
    NSPopover *popover = [NSPopover new];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.contentViewController = [self alternateEngineInfoController];
    [popover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMaxY];
}

- (IBAction)defaultEngineChosen:(NSPopUpButton *)sender
{
    NSString *name = sender.selectedItem.representedObject;
    if (name.length == 0) return;
    [SUD setObject:name forKey:DefaultEngineKey];
    [self refreshDefaultEngineFromDefaults:SUD];
}

- (IBAction)openEnginesFolder:(id)sender
{
    NSString *folder = [EnginePath stringByStandardizingPath];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:folder isDirectory:YES]];
}

// The list follows the folder, which can change while Settings is open.
- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (menu == self.defaultEnginePopup.menu) [self refreshDefaultEngineFromDefaults:SUD];
    if (menu == self.alternateEnginePopup.menu) [self refreshAlternateEngineFromDefaults:SUD];
}

//==============================================================================
// Engine profile
//==============================================================================

// The profile menu of Settings > Typesetting shows the profile all of whose settings are set
// now, or Custom when none is.
// Every setting some profile writes, as stored now.
static NSDictionary<TSPreferenceKey, id> *TSEngineProfileSettingsNow(NSUserDefaults *defaults)
{
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (TSPreferenceKey key in TSEngineProfileKeys()) settings[key] = [defaults objectForKey:key] ?: NSNull.null;
    return settings;
}

- (void)refreshEngineProfileFromDefaults:(NSUserDefaults *)defaults
{
    NSPopUpButton *popup = self.engineProfilePopup;
    if (popup == nil) return;
    // While the sheet asks, the menu keeps showing the profile chosen; it shows the settings again
    // when the sheet ends.
    if (self.engineProfileAsked != TSEngineProfileNone && [popup indexOfItemWithTag:self.engineProfileAsked] >= 0) {
        [popup selectItemWithTag:self.engineProfileAsked];
        return;
    }
    TSEngineProfile current = TSEngineProfileMatchingSettings(defaults, NULL);
    if (self.engineProfileLeftSettings != nil) {
        if ([TSEngineProfileSettingsNow(defaults) isEqual:self.engineProfileLeftSettings]) current = TSEngineProfileNone;
        else self.engineProfileLeftSettings = nil;
    }
    // The menu is built again only when what it shows changes.
    BOOL hasCustom = [popup indexOfItemWithTag:TSEngineProfileNone] >= 0;
    if (popup.numberOfItems > 0 && popup.selectedItem != nil && popup.selectedTag == current && hasCustom == (current == TSEngineProfileNone)) return;
    [popup removeAllItems];
    popup.autoenablesItems = NO;
    NSMenu *menu = popup.menu;
    NSArray *sections = TSEngineProfileMenuSections();
    // Separators and the heading get a tag no profile has, so that a tag selects only a profile.
    void (^add)(NSMenuItem *) = ^(NSMenuItem *item) { item.tag = -1; [menu addItem:item]; };
    for (NSUInteger i = 0; i < sections.count; i++) {
        if (i > 0) add(NSMenuItem.separatorItem);
        if (i == sections.count - 1) add([NSMenuItem sectionHeaderWithTitle:NSLocalizedString(@"Other", @"Engine profile section")]);
        for (NSNumber *profile in sections[i]) {
            NSString *title = TSEngineProfileTitle(profile.integerValue);
            if (title == nil) continue;
            NSMenuItem *item = [menu addItemWithTitle:title action:NULL keyEquivalent:@""];
            item.tag = profile.integerValue;
        }
    }
    if (current == TSEngineProfileNone) {
        add(NSMenuItem.separatorItem);
        NSMenuItem *custom = [menu addItemWithTitle:NSLocalizedString(@"Custom", @"Engine profile matching no settings") action:NULL keyEquivalent:@""];
        custom.tag = TSEngineProfileNone;
        custom.enabled = NO;
        [popup selectItem:custom];
    } else {
        [popup selectItemWithTag:current];
    }
}

// Choosing a profile in the menu asks at once whether to apply it, with latexmk or without, and
// lists what it sets; a value turned off in the list keeps the setting in use. The paths are set
// apart, with Detect Paths. Cancel changes nothing, and the menu shows the settings again, as it
// does after Apply: Custom when a value was turned off.
- (IBAction)applyEngineProfile:(id)sender
{
    // Read the choice first: committing a command being edited refreshes the menu.
    TSEngineProfile profile = self.engineProfilePopup.selectedTag;
    if (![self finishPreferenceEditing:YES] || TSEngineProfileTitle(profile) == nil || _prefsWindow == nil || _prefsWindow.attachedSheet != nil) {
        [self refreshEngineProfileFromDefaults:SUD];
        return;
    }
    // The commit may have shown the settings again; the menu shows the choice while the sheet asks.
    self.engineProfileAsked = profile;
    [self.engineProfilePopup selectItemWithTag:profile];
    TSEngineProfileSheet *sheet = [[TSEngineProfileSheet alloc] initWithProfile:profile latexmk:TSEngineProfileSettingsUseLatexmk(SUD) settings:SUD];
    [sheet beginSheetForWindow:_prefsWindow completionHandler:^(NSModalResponse response) {
        self.engineProfileAsked = TSEngineProfileNone;
        // The list leaves out the values turned off; with one of them turned off, the menu shows Custom.
        if (response == NSModalResponseOK && !self.endingPreferences) {
            [self applyEngineProfileValues:sheet.valuesToApply];
            self.engineProfileLeftSettings = sheet.list.keepsChangedValues ? TSEngineProfileSettingsNow(SUD) : nil;
        }
        [self refreshEngineProfileFromDefaults:SUD];
    }];
}

// Writes the values of a profile and refreshes what depends on them.
- (void)applyEngineProfileValues:(NSDictionary<NSString *, id> *)values
{
    NSSet *changed = TSEngineProfileApply(SUD, values);
    [self.settingsChangeNotes valuesReplaced];
    [self refreshRuntimePreferences];
    [self updateControlsFromUserDefaults:SUD];
    [self applyEffectsForPreferenceKeys:changed];
}

- (void)applyEffectsForPreferenceKeys:(NSSet<NSString *> *)changed
{
    TSPreferencePreparation preparations = TSPreferencePreparationsForKeys(changed);
    if (preparations & TSPreferencePreparePDFCopy) [(TSAppDelegate *)NSApp.delegate syncImageCopyTypeMenu];
    if (preparations & TSPreferencePrepareDock) [[TSDockIconController sharedController] restoreSavedIcon];
    if (preparations & TSPreferencePrepareEncoding) [[TSEncodingSupport sharedInstance] setupForEncoding];
    if (preparations & TSPreferencePrepareSpelling) [TSSpellSupport preferencesDidChange];
    if (preparations & TSPreferencePrepareTheme) [[TSColorSupport sharedInstance] initializeColors];
    TSPostPreferenceNotifications(changed, self);
}

// Refresh the process-wide copies after a group of settings has changed.
// Individual controls update their own copy at the point of persistence.
- (void)refreshRuntimePreferences
{
    editorCanAddBrackets = [SUD boolForKey:EditorCanAddBracketsKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
    [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"")] setHidden:![SUD boolForKey:TagMenuInMenuBarKey]];
}

//==============================================================================
// Document pane
//==============================================================================
/*" This method is connected to the 'Set...' button on the 'Document' pane.

Clicking this button will bring up the font panel.
"*/

- (IBAction)changeDocumentFont:sender
{
    // self.documentFont = [fontManager convertFont:self.documentFont];
    if (![self finishPreferenceEditing:YES]) return;
    self.ownsFontPanel = YES;
    self.fontEditingContext = TSSettingsFontDocument;
    [_prefsWindow makeFirstResponder:_prefsWindow];
    [[NSFontManager sharedFontManager] setSelectedFont:self.documentFont isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (IBAction)changeConsoleResize:sender
{
	if ([[_consoleResizeMatrix selectedCell] tag] == 0) 
		[SUD setBool:YES forKey:ConsoleWidthResizeKey];	
	else 
		[SUD setBool:NO forKey:ConsoleWidthResizeKey];
}



- (IBAction)changeConsoleFont:sender
{
	self.consoleFont = [NSFont fontWithName: [SUD stringForKey:ConsoleFontNameKey] size:[SUD floatForKey:ConsoleFontSizeKey]];
	
	// become first responder so we will see the envents that NSFontManager sends
	// up the responder chain
	if (![self finishPreferenceEditing:YES]) return;
    self.ownsFontPanel = YES;
    self.fontEditingContext = TSSettingsFontConsole;
	[_prefsWindow makeFirstResponder:_prefsWindow];
	[[NSFontManager sharedFontManager] setSelectedFont:self.consoleFont isMultiple:NO];
	[[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}



/*" This method is sent down the responder chain by the font manager when changing fonts in the font panel. Since this class is delegate of the Window, we will receive this method and we can reflect the changes in the textField accordingly.
"*/
- (void)changeFont:(id)fontManager
{
    if (!self.ownsFontPanel || self.endingPreferences ||
        !(_prefsWindow.isKeyWindow || _prefsWindow.isMainWindow)) return;
    
    NSData    *fontData;
    TSSettingsFontDestination destination = self.fontEditingContext;

	if (destination == TSSettingsFontDocument)
		{

		self.documentFont = [fontManager convertFont:self.documentFont];


		[self updateDocumentFontTextField];

		// update the userDefaults
		fontData = [NSArchiver archivedDataWithRootObject:self.documentFont];
		[SUD setObject:fontData forKey:DocumentFontKey];
		[SUD setBool:YES forKey:SaveDocumentFontKey];

		// post a notification so all open documents can change their font
		TSPostPreferenceNotifications([NSSet setWithObject:DocumentFontKey], self);

		}
		
	else if (destination == TSSettingsFontConsole)
		{
		self.consoleFont = [fontManager convertFont:self.consoleFont];
		[SUD setObject: [self.consoleFont fontName] forKey:ConsoleFontNameKey];
		[SUD setFloat: [self.consoleFont pointSize] forKey: ConsoleFontSizeKey];
		[self updateConsoleFontTextField];
		TSPostPreferenceNotifications([NSSet setWithObject:ConsoleFontNameKey], self);
		}
}

/*" This method is connected to the "Source Window Position" Matrix.

This method will be called when the matrix changes. Target 0 means 'all windows start at a fixed position', target 1 means 'remember window position'.
"*/
- (IBAction)sourceWindowPosChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:DocumentWindowPosModeKey];
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryGeneral defaults:SUD];
}

/*" This method is connected to the 'use current pos as default' button on the 'Document' pane.
"*/
- (IBAction)currentDocumentWindowPosDefault:sender
{
	NSWindow	*activeWindow;

	activeWindow = [[TSWindowManager sharedInstance] activeTextWindow];

	if (activeWindow != nil) {
		[SUD setObject:[activeWindow stringWithSavedFrame] forKey:DocumentWindowFixedPosKey];

		// just in case: the radio button must be checked as well.
		/* koch: the code below is harmless but probably unnecessary since the button can only
			be pressed if the radio button is in the fixed position mode */
		[SUD setInteger:DocumentWindowPosFixed forKey:DocumentWindowPosModeKey];
		[_sourceWindowPosMatrix selectCellWithTag:DocumentWindowPosFixed];
	}
}

// added by Terada( - (IBAction)highlightChanged: )
- (IBAction)highlightChanged:(id)sender
{
	[SUD setBool:![_alwaysHighlightButton state] forKey:AlwaysHighlightEnabledKey];
	
	[SUD setBool:[_showIndicatorForMoveButton state] forKey:ShowIndicatorForMoveEnabledKey];
	
	[SUD setBool:[_highlightContentButton state] forKey:HighlightContentEnabledKey];
	
	[SUD setBool:[_beepButton state] forKey:BeepEnabledKey];
	
	[SUD setBool:[_flashBackgroundButton state] forKey:FlashBackgroundEnabledKey];
	
	[SUD setBool:[_checkBraceButton state] forKey:CheckBraceEnabledKey];
	
	[SUD setBool:[_checkBracketButton state] forKey:CheckBracketEnabledKey];
	
	[SUD setBool:[_checkSquareBracketButton state] forKey:CheckSquareBracketEnabledKey];
	
	[SUD setBool:[_checkParenButton state] forKey:CheckParenEnabledKey];
	
	TSPostPreferenceNotifications([NSSet setWithArray:@[AlwaysHighlightEnabledKey, ShowIndicatorForMoveEnabledKey, HighlightContentEnabledKey, BeepEnabledKey, FlashBackgroundEnabledKey, CheckBraceEnabledKey, CheckBracketEnabledKey, CheckSquareBracketEnabledKey, CheckParenEnabledKey]], self);
}

- (void)updateInvisibleCharacterControls:(NSUserDefaults *)defaults
{
    NSArray *popups = @[_SpaceCharacterKindPopup, _FullwidthSpaceCharacterKindPopup,
                        _NewLineCharacterKindPopup, _TabCharacterKindPopup];
    NSArray *buttons = @[_showSpaceCharacterButton, _showFullwidthSpaceCharacterButton,
                         _showNewLineCharacterButton, _showTabCharacterButton];
    NSArray *keys = @[SpaceCharacterKindKey, FullwidthSpaceCharacterKindKey,
                      NewLineCharacterKindKey, TabCharacterKindKey];
    for (NSUInteger n = 0; n < popups.count; n++) {
        NSPopUpButton *popup = popups[n];
        NSButton *button = buttons[n];
        NSArray<NSString *> *markers = TSInvisibleMarkers(keys[n]);
        if (![popup.itemTitles isEqual:markers]) {
            [popup removeAllItems];
            [popup addItemsWithTitles:markers];
        }
        for (NSInteger i = 0; i < popup.numberOfItems; i++) [popup itemAtIndex:i].tag = i;
        popup.font = [NSFont systemFontOfSize:15];
        popup.menu.font = popup.font;
        popup.accessibilityLabel = button.title;
        [popup selectItemAtIndex:TSInvisibleStoredIndex(defaults, keys[n])];

    }
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryEditor defaults:defaults];
}

// added by Terada( - (IBAction)invisibleCharacterChanged: )
- (IBAction)invisibleCharacterChanged:(id)sender
{
	[SUD setBool:[_showTabCharacterButton state] forKey:showTabCharacterKey];
	
	[SUD setBool:[_showSpaceCharacterButton state] forKey:showSpaceCharacterKey];
	
	[SUD setBool:[_showFullwidthSpaceCharacterButton state] forKey:showFullwidthSpaceCharacterKey];
	
	[SUD setBool:[_showNewLineCharacterButton state] forKey:showNewLineCharacterKey];
	
	TSSetInvisibleIndex(SUD, SpaceCharacterKindKey, [_SpaceCharacterKindPopup selectedItem].tag);
	
	TSSetInvisibleIndex(SUD, FullwidthSpaceCharacterKindKey, [_FullwidthSpaceCharacterKindPopup selectedItem].tag);
	
	TSSetInvisibleIndex(SUD, NewLineCharacterKindKey, [_NewLineCharacterKindPopup selectedItem].tag);
	
	TSSetInvisibleIndex(SUD, TabCharacterKindKey, [_TabCharacterKindPopup selectedItem].tag);
	
    [self updateInvisibleCharacterControls:SUD];
	TSPostPreferenceNotifications([NSSet setWithArray:@[showTabCharacterKey, showSpaceCharacterKey, showFullwidthSpaceCharacterKey, showNewLineCharacterKey, SpaceCharacterKindKey, FullwidthSpaceCharacterKindKey, NewLineCharacterKindKey, TabCharacterKindKey]], self);
	
}

// added by Terada( - (IBAction)makeatletterChanged: )
- (IBAction)makeatletterChanged:(id)sender
{
	[SUD setBool:[_makeatletterButton state] forKey:MakeatletterEnabledKey];
	
	TSPostPreferenceNotifications([NSSet setWithArray:@[MakeatletterEnabledKey]], self);
}

// Each document reads this when it opens; the Source menu still turns expl3 coloring on and off for one document.
- (IBAction)expl3SyntaxColorPressed:sender
{
	[SUD setBool:(_expl3SyntaxColorButton.state == NSControlStateValueOn) forKey:expl3SyntaxColoringKey];    TSPostPreferenceNotifications([NSSet setWithArray:@[expl3SyntaxColoringKey]], self);
}

// Persist immediately; NSDocument autosave and server watching change at next launch.
- (IBAction)autoSaveEnabledPressed:sender
{
    id previousNoteValue = @([SUD boolForKey:AutoSaveEnabledKey]);
	[SUD setBool:(_autoSaveEnabledButton.state == NSControlStateValueOn) forKey:AutoSaveEnabledKey];
	// A backup file is kept only when Versions is off, which follows autosave.
	[self updateSettingsDependenciesForCategory:TSSettingsCategoryDocuments defaults:SUD];
    [self.settingsChangeNotes recordUserChangeForKey:AutoSaveEnabledKey previousValue:previousNoteValue];
}

- (IBAction)keepBackupPressed:sender
{
	[SUD setBool:(_keepBackupButton.state == NSControlStateValueOn) forKey:KeepBackupKey];
}

- (IBAction)saveEncodingMenuPressed:sender
{
	[SUD setBool:(_saveEncodingMenuButton.state == NSControlStateValueOn) forKey:EncodingMenuInSaveDialogKey];
}

// added by Terada( - (IBAction)kpsetoolChanged: )
- (IBAction)kpsetoolChanged:(id)sender
{
    [self commitPreferenceField:_kpsetoolField showError:YES reflect:YES];
}

// added by Terada( - (IBAction)bibTeXengineChanged: )
- (IBAction)bibTeXengineChanged:(id)sender
{
    [self commitPreferenceField:_bibTeXengineField showError:YES reflect:YES];
}

- (IBAction)makeIndexEngineChanged:(id)sender
{
    [self commitPreferenceField:self.makeIndexEngineField showError:YES reflect:YES];
}

- (IBAction)metaPostEngineChanged:(id)sender
{
    [self commitPreferenceField:self.metaPostEngineField showError:YES reflect:YES];
}


/*" Set Command Completion Key"*/
- (IBAction)commandCompletionChanged:sender
{
	
	if ([[sender selectedCell] tag] == 0)
		[SUD setObject:@"ESCAPE" forKey:CommandCompletionCharKey];
	else
		[SUD setObject:@"TAB" forKey:CommandCompletionCharKey];
	TSPostPreferenceNotifications([NSSet setWithArray:@[CommandCompletionCharKey]], self);
	
}



/*" Set Find Panel"*/
- (IBAction)findPanelChanged:sender
{
    id previousNoteValue = @([SUD integerForKey:FindMethodKey]);

	// The cell's tag is the FindMethod value: 0 Apple panel, 1 find bar, 2 OgreKit, 3 Advanced Find panel.
	NSInteger method = [[sender selectedCell] tag];
	[SUD setInteger:(method >= 0 && method <= 3 ? method : 0) forKey:FindMethodKey];
    [self applyEffectsForPreferenceKeys:[NSSet setWithObject:FindMethodKey]];
    [self.settingsChangeNotes recordUserChangeForKey:FindMethodKey previousValue:previousNoteValue];
    // The switch below is for the Advanced Find panel only.
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryEditor defaults:SUD];
}

// Whether the Advanced Find panel stays in front of the document windows; the panel reads it after each event.
- (IBAction)findPanelFloatsChanged:(NSButton *)sender
{
    [SUD setBool:sender.state == NSControlStateValueOn forKey:TSAdvancedFindPanelFloatsKey];
}

/*" Set Line Number Size"*/
- (IBAction)lineSizeChanged:sender
{

    if ([[sender selectedCell] tag] == 0)
        [SUD setInteger:0 forKey:LineNumberSizeKey];
    else if ([[sender selectedCell] tag] == 1)
        [SUD setInteger:1 forKey:LineNumberSizeKey];
    else
        [SUD setInteger:0 forKey:LineNumberSizeKey];
}


/*" Set Wrap Panel"*/
- (IBAction)wrapPanelChanged:sender
{
    
    if ([[sender selectedCell] tag] == 0)
        [SUD setInteger:0 forKey:LineBreakModeKey];
    else if ([[sender selectedCell] tag] == 1)
        [SUD setInteger:1 forKey:LineBreakModeKey];
    else
        [SUD setInteger:2 forKey:LineBreakModeKey];
}



/*" Make Empty Document on Startup "*/
- (IBAction)emptyButtonPressed:sender
{

	[SUD setBool:[(NSCell *)sender state] forKey:MakeEmptyDocumentKey];
}

/*" Configure for External Editor "*/
- (IBAction)externalEditorButtonPressed:sender
{

	[SUD setBool:[(NSCell *)sender state] forKey:UseExternalEditorKey];
	 // post a notification so the system will learn about this change
	TSPostPreferenceNotifications([NSSet setWithObject:UseExternalEditorKey], self);
}


/*" Change Encoding "*/
- (IBAction)encodingChanged:sender
{
	NSString	*oldValue, *value;
	NSStringEncoding	theCode;

	oldValue = [SUD stringForKey:EncodingKey];

	theCode = [[sender selectedCell] tag];
	value = [[TSEncodingSupport sharedInstance] keyForStringEncoding: theCode];
	[SUD setObject:value forKey:EncodingKey];

	// added by mitsu --(G) TSEncodingSupport
	[self applyEffectsForPreferenceKeys:[NSSet setWithObject:EncodingKey]];
    [self.settingsChangeNotes recordUserChangeForKey:EncodingKey previousValue:oldValue ?: @""];
// end addition

}

/*" Change Window Opening Behavior "*/
- (IBAction)openAsTabsChanged:sender
{
    NSInteger value;

    value = [[sender selectedCell] tag];
    [SUD setInteger:value forKey:OpenAsTabsKey];
}


- (IBAction)tabIndentPressed:(id)sender
{
    [self commitPreferenceField:tabIndentField showError:YES reflect:YES];
}

- (IBAction)firstParagraphIndentPressed:(id)sender
{
    [self commitPreferenceField:firstParagraphIndentField showError:YES reflect:YES];
}

- (IBAction)remainingParagraphIndentPressed:(id)sender
{
    [self commitPreferenceField:remainingParagraphIndentField showError:YES reflect:YES];
}

- (IBAction)interlineSpacingPressed:(id)sender
{
    [self commitPreferenceField:interlineSpacingField showError:YES reflect:YES];
}



- (IBAction)useTabPressed:sender
{
    
    [SUD setBool:[(NSButton*)sender state] forKey:TabIndentKey];
}


/*" This method is connected to the 'syntax coloring' checkbox.
"*/
- (IBAction)syntaxColorPressed:sender
{

    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:SyntaxColoringEnabledKey];
    TSPostPreferenceNotifications([NSSet setWithArray:@[SyntaxColoringEnabledKey]], self);
}



/*" This method is connected to the 'syntax line coloring' checkbox.
"*/
- (IBAction)syntaxColorLinePressed:sender
{

     
    [SUD setBool: [(NSCell *)sender state]  forKey:SyntaxColorEntryLineKey];
    TSPostPreferenceNotifications([NSSet setWithArray:@[SyntaxColorEntryLineKey]], self);
}

/*" This method is connected to the 'block cursor' checkbox.
"*/
- (IBAction)blockCursorPressed:sender
{

     
    [SUD setBool: [(NSCell *)sender state]  forKey:BlockCursorKey];
    [self updateSettingsDependenciesFromDefaults:SUD];
}

/*" This method is connected to the 'use font for log and macro editor' checkbox.
"*/
- (IBAction)MacroPressed:sender
{

     
    [SUD setBool: [(NSCell *)sender state]  forKey:SameFontForMacroKey];
}


- (IBAction)blockWidthPressed:sender
{
    NSInteger   selectedValue;
    

    if ([[sender selectedCell] tag] == 0)
        selectedValue = 0;
    else
        selectedValue = 1;
    
    [SUD setInteger: selectedValue forKey:BlockWidthKey];
}


- (IBAction)blockSidePressed:sender
{
    NSInteger   selectedValue;
    

    /*
    if ([[sender selectedCell] tag] == 0)
        selectedValue = 0;
    else
        selectedValue = 1;
    */
    selectedValue = [[sender selectedCell] tag];
    
    [SUD setInteger: selectedValue forKey:BlockSideKey];
}


/*" This method is connected to the block cursor color well.
 "*/
- (IBAction)BlockCursorColorChanged:sender
{
    NSColor *newColor = [((NSColorWell *)sender).color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
    if (newColor == nil) return;
    
    
    [SUD setFloat: [newColor redComponent] forKey:BlockCursorRKey];
    [SUD setFloat: [newColor greenComponent] forKey:BlockCursorGKey];
    [SUD setFloat: [newColor blueComponent] forKey: BlockCursorBKey];
}



/*" This method is connected to the "Source Window Position" Matrix.
 
 This method will be called when the matrix changes. Target 0 means 'all windows start at a fixed position', target 1 means 'remember window position'.
 "*/
- (IBAction)consoleWindowPosChanged:sender
{
    
    [SUD setInteger:[[sender selectedCell] tag] forKey:ConsoleWindowPosModeKey];
    [_consoleWindowPosMatrix selectCellWithTag:[[sender selectedCell] tag]];
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryGeneral defaults:SUD];
}

/*" This method is connected to the 'use current pos as default' button on the 'Document' pane.
 "*/
- (IBAction)consoleWindowPosDefault:sender
{
    NSMutableArray  *visibleWindows;
    NSEnumerator    *windowsEnumerator;
    id              anObject;
    NSWindow        *activeConsole;
    
    
    visibleWindows = [NSMutableArray arrayWithCapacity: 37];
    
    
    NSArray *myWindows = [[NSApplication sharedApplication] windows];
    windowsEnumerator = [myWindows objectEnumerator];
    while (anObject = [windowsEnumerator nextObject])
        if ([(NSWindow *)anObject isVisible])
            [visibleWindows addObject: anObject];
    
    // NSLog(@"There are %lu windows", (unsigned long)[visibleWindows count]);

    windowsEnumerator = [visibleWindows objectEnumerator];
    while ((activeConsole = [windowsEnumerator nextObject]) &&
           ( ! [activeConsole isKindOfClass: [TSConsoleWindow class]]))
    {
        ;
    }
    
    if (! activeConsole)
    {
//      NSLog(@"no console");
        return;
    }
    
//    if (  [activeConsole isKindOfClass: [TSConsoleWindow class]])
//        NSLog(@"this is a console");
    
//    NSLog(@"found one");
    
    if (activeConsole != nil) {
        [SUD setObject:[activeConsole stringWithSavedFrame] forKey:ConsoleWindowFixedPosKey];
        
        // just in case: the radio button must be checked as well.
        /* koch: the code below is harmless but probably unnecessary since the button can only
         be pressed if the radio button is in the fixed position mode */
        [SUD setInteger:ConsoleWindowPosFixed forKey:ConsoleWindowPosModeKey];
        [_consoleWindowPosMatrix selectCellWithTag:ConsoleWindowPosFixed];
    }
}


- (IBAction)XMLChapterButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLChapterTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLSectionButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLSectionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLSubsectionButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLSubsectionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLSubsubsectionButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLSubsubsectionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLIntroductionButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLIntroductionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLConclusionButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLConclusionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLExercisesButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLExercisesTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLProjectButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLProjectTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLFigureButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLFigureTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLTableButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLTableTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLMarkButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLMarkTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}










/*" This method is connected to the 'select on activate' checkbox.
"*/
- (IBAction)selectActivatePressed:sender
{

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:AcceptFirstMouseKey];
}


/*" This method is connected to the 'parens matching' checkbox.
"*/
- (IBAction)parensMatchPressed:sender
{

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:ParensMatchingEnabledKey];
}

/*" This method is connected to the 'spell checking' checkbox.
"*/
- (IBAction)spellCheckPressed:sender
{

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:SpellCheckEnabledKey];
}

- (IBAction)editorAddBracketsPressed:(id)sender
{
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:EditorCanAddBracketsKey];
    editorCanAddBrackets = [SUD boolForKey:EditorCanAddBracketsKey];
}

- (IBAction)spellCorrectPressed:sender
{
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:AutomaticSpellingCorrectionEnabledKey];
}


/*" This method is connected to the 'line number' checkbox.
"*/
- (IBAction)lineNumberButtonPressed:sender
{

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:LineNumberEnabledKey];
}

/*" This method is connected to the 'tags menu' checkbox.
 "*/
- (IBAction)tagMenuButtonPressed:sender
{
    
	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:TagMenuInMenuBarKey];
     [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] setHidden:( ![SUD boolForKey:TagMenuInMenuBarKey])];
}


// added by Terada (-(IBAction)showInvisibleCharacterButtonPressed:)
- (IBAction)showInvisibleCharacterButtonPressed:sender
{
	
	[SUD setBool:[(NSCell *)sender state] forKey:ShowInvisibleCharactersEnabledKey];    TSPostPreferenceNotifications([NSSet setWithArray:@[ShowInvisibleCharactersEnabledKey]], self);
}

/*" This method is connected to the 'Arabic, Persian, Hebrew' checkbox.
 "*/
- (IBAction)midEastButtonPressed:sender
{
	
	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:RightJustifyKey];
}





/*" This method is connected to the 'shell escape warning' checkbox.
"*/
- (IBAction)escapeWarningChanged:sender
{

	[SUD setBool:[(NSCell *)sender state] forKey:WarnForShellEscapeKey];
}


/*" This method is connected to the 'auto complete' checkbox.
"*/
- (IBAction)autoCompletePressed:sender
{

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:AutoCompleteEnabledKey];
	TSPostPreferenceNotifications([NSSet setWithArray:@[AutoCompleteEnabledKey]], self);

}

/*" This method is connected to the 'BibDesk Complete' checkbox.
"*/
- (IBAction)bibDeskCompletePressed:sender
{
	
	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:BibDeskCompletionKey];
	TSPostPreferenceNotifications([NSSet setWithArray:@[BibDeskCompletionKey]], self);

}





//==============================================================================
// Preview pane
//==============================================================================
/*" This method is connected to the "PDF Window Position" Matrix.

A tag of 0 means don't save the window position, a tag of 1 to save the setting. This should only flag the request to save the position, the actual saving of position and size can be left to [NSWindow setAutoSaveFrameName].
"*/
- (IBAction)pdfWindowPosChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfWindowPosModeKey];

	/* koch: button enabled only if appropriate */
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryGeneral defaults:SUD];
}

//==============================================================================
/*" This method is connected to the "HTML Window Position" Matrix.

A tag of 0 means don't save the window position, a tag of 1 to save the setting. This should only flag the request to save the position, the actual saving of position and size can be left to [NSWindow setAutoSaveFrameName].
"*/
- (IBAction)htmlWindowPosChanged:sender
{

    [SUD setInteger:[[sender selectedCell] tag] forKey:HtmlWindowPosModeKey];

    /* koch: button enabled only if appropriate */
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryGeneral defaults:SUD];
}

/*" This method is connected to the 'use current pos as default' button.
"*/
- (IBAction)currentPdfWindowPosDefault:sender
{
	NSWindow	*activeWindow;

	activeWindow = [[TSWindowManager sharedInstance] activePDFWindow];

	if (activeWindow != nil) {
		[SUD setObject:[activeWindow stringWithSavedFrame] forKey:PdfWindowFixedPosKey];

		// just in case: the radio button must be checked as well.
		[SUD setInteger:DocumentWindowPosFixed forKey:PdfWindowPosModeKey];
		[_pdfWindowPosMatrix selectCellWithTag:PdfWindowPosFixed];
	}
}

/*" This method is connected to the 'use current pos as default' button.
"*/
- (IBAction)currentHtmlWindowPosDefault:sender
{
    NSWindow    *activeWindow;

    activeWindow = [[TSWindowManager sharedInstance] activeHTMLWindow];

    if (activeWindow != nil) {
        [SUD setObject:[activeWindow stringWithSavedFrame] forKey:HtmlWindowFixedPosKey];

        // just in case: the radio button must be checked as well.
       //  [SUD setInteger:HtmlWindowPosFixed forKey:HtmlWindowPosModeKey];
       //  [_sourceWindowPosMatrix selectCellWithTag:HtmlWindowPosFixed];
    }
}


- (IBAction)autoPDFChanged:sender
{
	[SUD setBool:[(NSCell *)sender state] forKey:PdfRefreshKey];
}

// The state of Link Popups in the Preview menu when a Preview window opens.
- (IBAction)linkPopupsChanged:(NSButton *)sender
{
    [SUD setBool:sender.state == NSControlStateValueOn forKey:LinkPopupsKey];
}

// Whether scrolling stops at the edge of the page in single and double page display.
- (IBAction)scrollPageTurnChanged:(NSButton *)sender
{
    [SUD setBool:sender.state == NSControlStateValueOn forKey:NoScrollPageTurnKey];
}

// Whether the left and right arrow keys turn pages also when a zoomed page can scroll sideways.
- (IBAction)arrowKeysPageChanged:(NSButton *)sender
{
    [SUD setBool:sender.state == NSControlStateValueOn forKey:LeftRightArrowsAlwaysPageKey];
}

- (IBAction)sourceAndPreviewInSameWindowChanged:sender
{
    NSInteger myTag = [sender tag];
    BOOL result;
    if (myTag == 0)
        result = NO;
    else
        result = YES;
	[SUD setBool:result forKey:SourceAndPreviewInSameWindowKey];
    [self updateSettingsDependenciesFromDefaults:SUD];
}

- (IBAction)sourceOnLeftChanged:sender
{
    NSInteger myTag = [sender tag];
    BOOL result;
    if (myTag == 0)
        result = NO;
    else
        result = YES;
    [SUD setBool:result forKey:SwitchSidesKey];
}



#ifdef MITSU_PDF

// mitsu 1.29 (O)
/*" This method is connected to page style popup button. "*/
- (IBAction)pageStyleChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfPageStyleKey];
}

/*" This method is connect to the 'first double page' radio buttons.
"*/
- (IBAction)displayAsBookChanged:(NSButton *)sender
{
    [SUD setBool:sender.state == NSControlStateValueOn forKey:DisplayAsBookKey];
}

- (IBAction)firstDoublePageChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfFirstPageStyleKey];
}


/*" This method is connected to resize option popup button. "*/
- (IBAction)resizeOptionChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfKitFitSizeKey];
}


/*" This method is connected to image copy type popup button. "*/
- (IBAction)imageCopyTypeChanged:sender
{
	// mitsu 1.29b
	// uncheck menu item Preview=>Copy Format
	NSMenu *previewMenu = [[[NSApp mainMenu] itemWithTitle:
						NSLocalizedString(@"Preview", @"Preview")] submenu];

	NSMenu *formatMenu = [[previewMenu itemWithTitle:
						NSLocalizedString(@"Copy Format", @"Copy Format")] submenu];
	id item = [formatMenu itemWithTag: [[sender selectedCell] tag]];
	if (item)
		[(TSAppDelegate *)[NSApp delegate] changeImageCopyType: item];
	// end mitsu 1.29b
}

// mitsu 1.29b
- (NSPopUpButton *)imageCopyTypePopup
{
	return _imageCopyTypePopup;
}
// end mitsu 1.29b


/*" This method is connected to default mouse mode popup button. "*/
- (IBAction)mouseModeChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfKitMouseModeKey];
}

/*" This method is connected to default mouse mode popup button. "*/
- (IBAction)colorMapChanged:sender
{

	[SUD setBool:([(NSCell *)sender state]==NSOnState) forKey:PdfColorMapKey];
    [self updateSettingsDependenciesFromDefaults:SUD];
}

- (IBAction)colorParam1Changed:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfColorParam1Key];
}

// end mitsu 1.29
#endif



//==============================================================================
- (void)cancelEnginePathDiscovery
{
    self.enginePathSearchGeneration++;
    self.initialEnginePathSearchPending = NO;
    self.enginePathSearchButton.enabled = YES;
    self.enginePathSearchButton = nil;
}

- (void)discoverInitialEnginePaths
{
    [self searchEnginePathsForInitialSetup:YES sender:nil];
}

// Detect Paths in Settings: the installations found, as a sheet.
- (IBAction)discoverEnginePaths:(id)sender
{
    if (![self finishPreferenceEditing:YES]) return;
    [self searchEnginePathsForInitialSetup:self.initialEnginePathSearchPending sender:sender];
}

- (BOOL)enginePathSnapshotMatches:(NSArray<NSString *> *)snapshot initial:(BOOL)initial
{
    if (![snapshot[0] isEqualToString:[SUD stringForKey:TetexBinPath] ?: @""] ||
        ![snapshot[1] isEqualToString:[SUD stringForKey:GSBinPath] ?: @""]) return NO;
    return initial || ([_tetexBinPathField.stringValue isEqualToString:snapshot[0]] &&
                       [_gsBinPathField.stringValue isEqualToString:snapshot[1]]);
}

// BEGIN engine path alert
// Views stacked from the top, left-aligned, as wide as the widest.
static NSView *TSEngineProfileStack(NSArray<NSView *> *views, NSArray<NSNumber *> *gaps)
{
    CGFloat width = 0, height = 0;
    for (NSUInteger i = 0; i < views.count; i++) { width = MAX(width, NSWidth(views[i].frame)); height += NSHeight(views[i].frame) + [gaps[i] doubleValue]; }
    NSView *stack = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    CGFloat top = height;
    for (NSUInteger i = 0; i < views.count; i++) {
        top -= [gaps[i] doubleValue] + NSHeight(views[i].frame);
        [views[i] setFrameOrigin:NSMakePoint(NSMinX(views[i].frame), top)];
        [stack addSubview:views[i]];
    }
    return stack;
}

// An accessory narrower than the alert is centered by NSAlert; widened to the width of the
// message, it starts where the message starts.
static void TSEngineProfileAlignAccessory(NSAlert *alert)
{
    [alert layout];
    NSView *content = alert.window.contentView, *accessory = alert.accessoryView;
    for (NSView *view in content.subviews) {
        if (![view isKindOfClass:NSTextField.class] || ![((NSTextField *)view).stringValue isEqual:alert.messageText]) continue;
        CGFloat width = NSWidth(content.bounds) - 2 * NSMinX(view.frame);
        if (width > NSWidth(accessory.frame)) {
            [accessory setFrameSize:NSMakeSize(width, NSHeight(accessory.frame))];
            [alert layout];
        }
        return;
    }
}

// Detect Paths, and the first step of first launch: the TeX and Ghostscript installations
// found, the newest of each selected. The radio matrices are returned in matrices.
static NSAlert *TSEnginePathAlert(NSDictionary *found, NSMutableDictionary *matrices)
{
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Detect Paths", @"");
    BOOL hasPaths = [found[@"TeX"] count] || [found[@"Ghostscript"] count];
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    NSMutableArray<NSNumber *> *gaps = [NSMutableArray array];
    for (NSString *key in @[@"TeX", @"Ghostscript"]) {
        NSTextField *label = [NSTextField labelWithString:key];
        label.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
        [label sizeToFit];
        [views addObject:label]; [gaps addObject:@(views.count == 1 ? 0 : 12)];
        NSArray *candidates = found[key];
        if (candidates.count == 0) {
            NSTextField *missing = [NSTextField labelWithString:NSLocalizedString(@"Not found", @"")];
            missing.textColor = NSColor.secondaryLabelColor;
            [missing sizeToFit];
            [views addObject:missing]; [gaps addObject:@4];
            continue;
        }
        NSButtonCell *cell = [NSButtonCell new];
        [cell setButtonType:NSButtonTypeRadio];
        cell.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        CGFloat const spacing = 4;
        NSMatrix *matrix = [[NSMatrix alloc] initWithFrame:NSZeroRect mode:NSRadioModeMatrix prototype:cell
            numberOfRows:candidates.count numberOfColumns:1];
        NSSize cellSize = NSZeroSize;
        for (NSUInteger row = 0; row < candidates.count; row++) {
            NSDictionary *candidate = candidates[row];
            NSString *version = [candidate[@"version"] length] ? candidate[@"version"] : NSLocalizedString(@"Version unavailable", @"");
            NSButtonCell *rowCell = [matrix cellAtRow:row column:0];
            rowCell.title = [NSString stringWithFormat:@"%@\n%@", version, candidate[@"path"]];
            [matrix setToolTip:candidate[@"path"] forCell:rowCell];
            // As wide as the longest installation, so that no space is left on the right.
            cellSize = NSMakeSize(MAX(cellSize.width, ceil(rowCell.cellSize.width)), MAX(cellSize.height, ceil(rowCell.cellSize.height)));
        }
        matrix.cellSize = cellSize;
        matrix.intercellSpacing = NSMakeSize(0, spacing);
        [matrix sizeToCells];
        [matrix selectCellAtRow:0 column:0];
        // At most three installations show at once; more scroll.
        BOOL scrolls = candidates.count > 3;
        CGFloat height = scrolls ? 3 * cellSize.height + 2 * spacing : NSHeight(matrix.frame);
        CGFloat width = NSWidth(matrix.frame) + (scrolls ? [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScroller.preferredScrollerStyle] : 0);
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
        scroll.hasVerticalScroller = scrolls;
        scroll.autohidesScrollers = YES;
        scroll.drawsBackground = NO;
        scroll.documentView = matrix;
        [matrix scrollCellToVisibleAtRow:0 column:0];
        [views addObject:scroll]; [gaps addObject:@4];
        matrices[key] = matrix;
    }
    alert.accessoryView = TSEngineProfileStack(views, gaps);
    if (![found[@"TeX"] count]) alert.informativeText = NSLocalizedString(@"Install TeX Live or MacTeX, then choose Detect Paths in Settings > Typesetting.", @"");
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
    if (hasPaths) [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    TSEngineProfileAlignAccessory(alert);
    return alert;
}
// END engine path alert

- (void)searchEnginePathsForInitialSetup:(BOOL)initial sender:(NSButton *)sender
{
    [self cancelEnginePathDiscovery];
    NSUInteger generation = self.enginePathSearchGeneration;
    self.initialEnginePathSearchPending = initial;
    self.enginePathSearchButton = sender;
    sender.enabled = NO;
    NSArray *snapshot = @[[SUD stringForKey:TetexBinPath] ?: @"", [SUD stringForKey:GSBinPath] ?: @""];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *found = [TSEnginePathDiscovery candidatesForPaths:[TSEnginePathDiscovery systemSearchPaths]
                                                  currentTeX:snapshot[0] currentGhostscript:snapshot[1]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.enginePathSearchGeneration) return;
            self.initialEnginePathSearchPending = NO;
            sender.enabled = YES;
            // If Settings opened during the initial search, use its sheet.
            BOOL applyInitial = initial && !self->_prefsWindow.visible;
            BOOL settingsOpen = self->_prefsWindow.visible || self->_prefsWindow.miniaturized;
            if ((!initial && !settingsOpen) || ![self enginePathSnapshotMatches:snapshot initial:applyInitial]) return;
            NSMutableDictionary *matrices = [NSMutableDictionary dictionary];
            NSAlert *alert = TSEnginePathAlert(found, matrices);
            BOOL hasPaths = [found[@"TeX"] count] || [found[@"Ghostscript"] count];
            void (^finish)(NSModalResponse) = ^(NSModalResponse response) {
                if (response == NSAlertFirstButtonReturn && hasPaths && generation == self.enginePathSearchGeneration &&
                    (applyInitial || self->_prefsWindow.visible || self->_prefsWindow.miniaturized) && [self enginePathSnapshotMatches:snapshot initial:applyInitial]) {
                    NSArray *keys = @[TetexBinPath, GSBinPath];
                    NSArray *names = @[@"TeX", @"Ghostscript"];
                    NSArray *required = @[@[@"tex", @"latex", @"pdftex", @"pdflatex"], @[@"gs"]];
                    for (NSUInteger i = 0; i < keys.count; i++) {
                        NSMatrix *matrix = matrices[names[i]];
                        NSString *path = matrix ? found[names[i]][matrix.selectedRow][@"path"] : nil;
                        if (!path || ![TSEnginePathDiscovery directory:path containsPrograms:required[i]]) continue;
                        [SUD setObject:path forKey:keys[i]];
                    }
                    if (self->_prefsWindow != nil) {
                        self->_tetexBinPathField.stringValue = [SUD stringForKey:TetexBinPath] ?: @"";
                        self->_gsBinPathField.stringValue = [SUD stringForKey:GSBinPath] ?: @"";
                    }
                }
                // First launch goes on to the engine profile, whatever was done with the paths.
                if (initial && generation == self.enginePathSearchGeneration) [self chooseInitialEngineProfileModal:applyInitial];
            };
            if (applyInitial) finish([alert runModal]);
            else [alert beginSheetModalForWindow:self->_prefsWindow completionHandler:finish];
        });
    });
}

// The second step of first launch. Cancel leaves the factory commands.
- (void)chooseInitialEngineProfileModal:(BOOL)modal
{
    TSEngineProfileSheet *sheet = [[TSEngineProfileSheet alloc] initChoosingProfile:TSEngineProfileForLanguages(NSLocale.preferredLanguages)];
    NSUInteger generation = self.enginePathSearchGeneration;
    void (^finish)(NSModalResponse) = ^(NSModalResponse response) {
        if (response != NSModalResponseOK || generation != self.enginePathSearchGeneration) return;
        [self applyEngineProfileValues:sheet.valuesToApply];
    };
    if (!modal && self.endingPreferences) {
        // Settings is closing: ask once it has closed.
        dispatch_async(dispatch_get_main_queue(), ^{ if (!self.quittingPreferences) [self chooseInitialEngineProfileModal:YES]; });
        return;
    }
    if (modal || !self->_prefsWindow.visible) finish([sheet runModal]);
    else [sheet beginSheetForWindow:self->_prefsWindow completionHandler:finish];
}

/*" This method is connected to the textField that holds the tetex bin path.
"*/
- (IBAction)tetexBinPathChanged:(id)sender
{
    [self commitPreferenceField:_tetexBinPathField showError:YES reflect:YES];
}

//==============================================================================
/*" This method is connected to the textField that holds the HtmlHome value
"*/
- (IBAction)HtmlHomeChanged:(id)sender
{
    [self commitPreferenceField:_HtmlHomeField showError:YES reflect:YES];
}


//==============================================================================
/*" This method is connected to the textField that holds the alternate path.
"*/
- (IBAction)altPathChanged:(id)sender
{
    [self commitPreferenceField:_altPathField showError:YES reflect:YES];
}


//==============================================================================
/*" This method is connected to the textField that holds the gs bin path.
"*/
- (IBAction)gsBinPathChanged:(id)sender
{
    [self commitPreferenceField:_gsBinPathField showError:YES reflect:YES];
}

//==============================================================================
// TeX pane
//==============================================================================
/*" This method is connected to the textField that holds the TeX command. It is located on the TeX pane.
"*/
- (IBAction)texProgramChanged:(id)sender
{
    [self commitPreferenceField:_texCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the textField that holds the LaTeX command. It is located on the TeX pane.
"*/
- (IBAction)latexProgramChanged:(id)sender
{
    [self commitPreferenceField:_latexCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the textField that holds the tex + ghostscript command. It is located on the TeX pane.
"*/
- (IBAction)texGSProgramChanged:(id)sender
{
    [self commitPreferenceField:_texGSCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the textField that holds the latextex + ghostscript command. It is located on the TeX pane.
"*/
- (IBAction)latexGSProgramChanged:(id)sender
{
    [self commitPreferenceField:_latexGSCommandTextField showError:YES reflect:YES];
}

#ifdef USESPARKLE

/*" Sparkle Actions 
"*/
- (IBAction)sparkleAutomaticCheck:sender
{

    
    BOOL theValue = [(NSCell *) sender state];
    
    [SUD setBool:theValue forKey:SparkleAutomaticUpdateKey];
    
    
    [[TSSparkleController sharedUpdater] setAutomaticallyChecksForUpdates: theValue ];
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryUpdates defaults:SUD];
    
}

- (IBAction)sparkleInterval:sender
{

    
    
    [SUD setInteger:[[sender selectedCell] tag] forKey:SparkleIntervalKey];
    
    switch ([[sender selectedCell] tag])
    {
        case 1: [[TSSparkleController sharedUpdater] setUpdateCheckInterval: 86400];
                break;
            
        case 2: [[TSSparkleController sharedUpdater] setUpdateCheckInterval: 604800];
            break;
            
        case 3: [[TSSparkleController sharedUpdater] setUpdateCheckInterval: 2629800];
            break;
    }
 
    
}

#endif

- (IBAction)sparklePrereleaseUpdates:(NSButton *)sender
{
    [SUD setBool:sender.state == NSControlStateValueOn forKey:SparklePrereleaseUpdatesKey];
#ifdef USESPARKLE
    [[TSSparkleController sharedUpdater] resetUpdateCycleAfterShortDelay];
#endif
}

- (IBAction)checkForUpdatesFromSettings:(id)sender
{
#ifdef USESPARKLE
    [[TSSparkleController sharedController] checkForUpdates:sender];
#endif
}

- (void)sparkleStatusControlsDidLoad
{
#ifdef USESPARKLE
    SPUUpdater *updater = [TSSparkleController sharedUpdater];
    if (updater != nil && self.sparkleCheckNowButton != nil)
        [self.sparkleCheckNowButton bind:NSEnabledBinding toObject:updater withKeyPath:@"canCheckForUpdates" options:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TSSparkleUpdateCheckDidFinishNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sparkleUpdateCheckDidFinish:) name:TSSparkleUpdateCheckDidFinishNotification object:nil];
#endif
    [self refreshSparkleLastCheck];
}

- (void)sparkleUpdateCheckDidFinish:(NSNotification *)notification
{
    [self refreshSparkleLastCheck];
}

- (void)refreshSparkleLastCheck
{
    if (self.sparkleLastCheckField == nil) return;
    NSDate *date = nil;
#ifdef USESPARKLE
    date = [TSSparkleController sharedUpdater].lastUpdateCheckDate;
#endif
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *when;
    if (date != nil)
        when = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
    else
        when = [bundle localizedStringForKey:@"catalog.updates.2.0.never" value:@"Never" table:@"SettingsCategories"];
    NSString *format = [bundle localizedStringForKey:@"catalog.updates.2.0.last" value:@"Last checked: %@" table:@"SettingsCategories"];
    self.sparkleLastCheckField.stringValue = [NSString stringWithFormat:format, when];
}

/*" This method is connected to the textField that holds the tex script command. It is located on the TeX pane.
"*/
- (IBAction)texScriptProgramChanged:(id)sender
{
    [self commitPreferenceField:_texScriptCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the textField that holds the latex script command. It is located on the TeX pane.
"*/
- (IBAction)latexScriptProgramChanged:(id)sender
{
    [self commitPreferenceField:_latexScriptCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the textField that holds the alternate engine command. It is located on the Misc pane.
"*/

/*" This method is connected to the "Default Program" matrix on the TeX pane.

A tag of 0 means use TeX, a tag of 1 means use LaTeX.
"*/
- (IBAction)defaultProgramChanged:sender
{

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:DefaultCommandKey];
	// The engine file shown is the one the documents use from now on, also when it is the factory one.
	if ([[sender selectedCell] tag] == DefaultCommandUser && [self.defaultEnginePopup.selectedItem.representedObject length] > 0)
		[SUD setObject:self.defaultEnginePopup.selectedItem.representedObject forKey:DefaultEngineKey];
	[self updateSettingsDependenciesForCategory:TSSettingsCategoryTypesetting defaults:SUD];
}

/*" This method is connected to the "Default Script" matrix on the TeX pane.

A tag of 100 means use pdftex, a tag of 101 means use tex + ghostscript, a tag of 102 means use
person script. See also: DefaultTypesetMode.

"*/
- (IBAction)defaultScriptChanged:sender
{

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:DefaultScriptKey];
    [self refreshEngineProfileFromDefaults:SUD];
}

- (IBAction)syncChanged: sender
{

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:SyncMethodKey];
}



// zenitani 1.35 (C)
- (IBAction)ptexUtfOutputPressed:sender
{

	[SUD setBool:[(NSCell *)sender state] forKey:ptexUtfOutputEnabledKey];
    [self applyEffectsForPreferenceKeys:[NSSet setWithObject:ptexUtfOutputEnabledKey]];
}

// koch, 4/10/2011
- (IBAction)convertUTFPressed:sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:AutomaticUTF8MACtoUTF8ConversionKey];
 
/*
   self.consoleFont = [NSFont fontWithName: [SUD stringForKey:ConsoleFontNameKey] size:[SUD floatForKey:ConsoleFontSizeKey]];
    
    // become first responder so we will see the envents that NSFontManager sends
    // up the responder chain
    [_prefsWindow makeFirstResponder:_prefsWindow];
    [[NSFontManager sharedFontManager] setSelectedFont:self.consoleFont isMultiple:NO];
 */
}


- (IBAction)openRootFilePressed:sender
{
    
    [SUD setBool:[(NSButton *)sender state] forKey:AutoOpenRootFileKey];
}

- (IBAction)miniaturizeRootFilePressed:sender
{
    
    [SUD setBool:[(NSButton *)sender state] forKey:MiniaturizeRootFileKey];
}

- (void)setSettingsControl:(NSControl *)control enabled:(BOOL)enabled
{
    if (control == nil) return;
    control.enabled = enabled;
    NSView *row = control.superview;
    while (row != nil && ![row.identifier hasPrefix:@"row."]) row = row.superview;
    if (row == nil) return;
    NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:row];
    while (pending.count) {
        NSView *view = pending.lastObject; [pending removeLastObject];
        if ([view isKindOfClass:NSControl.class]) ((NSControl *)view).enabled = enabled;
        [pending addObjectsFromArray:view.subviews];
    }
}
// A rule names its source value, typed outlet and whether the whole row or
// only the accessory depends on it. Per-document defaults have no parent rule.
- (void)updateSettingsDependenciesForCategory:(TSSettingsCategoryID)category defaults:(NSUserDefaults *)defaults
{
    typedef NS_ENUM(NSUInteger, TSDependencyKind) { TSDependencyBoolean, TSDependencyInteger };
    typedef struct {
        __unsafe_unretained TSSettingsCategoryID category;
        __unsafe_unretained TSPreferenceKey key;
        NSInteger enabledValue;
        TSDependencyKind kind;
        __unsafe_unretained id endpoint;
        BOOL wholeRow;
    } Rule;
    Rule rules[] = {
#include "TSSettingsDependencies.inc"
    };
    // These defaults can also be changed on existing documents through menus.
    // Their subordinate values stay editable regardless of the default choice.
    if (category == nil || [category isEqual:TSSettingsCategoryEditor]) {
        [self setSettingsControl:BlockCursorColorWell enabled:YES];
        [self setSettingsControl:_blockSideMatrix enabled:YES];
        [self setSettingsControl:_blockWidthMatrix enabled:YES];
    }
    if (category == nil || [category isEqual:TSSettingsCategoryGeneral]) {
        [self setSettingsControl:useLeftSourceButton enabled:YES];
        [self setSettingsControl:useRightSourceButton enabled:YES];
    }
    for (NSUInteger i = 0; i < sizeof(rules)/sizeof(rules[0]); i++) {
        Rule rule = rules[i];
        if (category && ![category isEqual:rule.category]) continue;
        NSInteger value = rule.kind == TSDependencyBoolean ? [defaults boolForKey:rule.key] : [defaults integerForKey:rule.key];
        BOOL enabled = value == rule.enabledValue;
#ifdef USESPARKLE
        if ([rule.key isEqual:SparkleAutomaticUpdateKey] && defaults == SUD && [TSSparkleController sharedUpdater])
            enabled = [TSSparkleController sharedUpdater].automaticallyChecksForUpdates;
#endif
        [rule.endpoint setEnabled:enabled];
        NSControl *control = [rule.endpoint isKindOfClass:NSCell.class] ? [(NSCell *)rule.endpoint controlView] : rule.endpoint;
        if (rule.wholeRow) [self setSettingsControl:control enabled:enabled];
    }
}
- (void)updateSettingsDependenciesFromDefaults:(NSUserDefaults *)defaults
{
    [self updateSettingsDependenciesForCategory:nil defaults:defaults];
}

- (void)updateSpellingControlsFromDefaults:(NSUserDefaults *)defaults
{
    BOOL enabled = [defaults boolForKey:TSTeXAwareSpellCheckingKey];
    _texAwareSpellCheckButton.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    if (self.legacySpellCheckButton != nil) self.legacySpellCheckButton.state = enabled ? NSControlStateValueOff : NSControlStateValueOn;
    // The exclusion rules apply only to TeX-aware spell checking.
    [self updateSettingsDependenciesForCategory:TSSettingsCategorySpelling defaults:defaults];
}

- (IBAction)texAwareSpellCheckPressed:(NSButton *)sender
{
    id previousNoteValue = @([SUD boolForKey:TSTeXAwareSpellCheckingKey]);
    [SUD setBool:(sender.state == NSControlStateValueOn) forKey:TSTeXAwareSpellCheckingKey];
    [self updateSpellingControlsFromDefaults:SUD];
    [self applyEffectsForPreferenceKeys:[NSSet setWithObject:TSTeXAwareSpellCheckingKey]];
    [self.settingsChangeNotes recordUserChangeForKey:TSTeXAwareSpellCheckingKey previousValue:previousNoteValue];
}

- (IBAction)displayCommentLines:(id)sender
{
    if (self.settingsHelpDocuments == nil) self.settingsHelpDocuments = [HelpDocuments new];
    [self.settingsHelpDocuments displayCommentLines:sender];
}

- (IBAction)legacySpellCheckPressed:(NSButton *)sender
{
    id previousNoteValue = @([SUD boolForKey:TSTeXAwareSpellCheckingKey]);
    [SUD setBool:NO forKey:TSTeXAwareSpellCheckingKey];
    [self updateSpellingControlsFromDefaults:SUD];
    [self applyEffectsForPreferenceKeys:[NSSet setWithObject:TSTeXAwareSpellCheckingKey]];
    [self.settingsChangeNotes recordUserChangeForKey:TSTeXAwareSpellCheckingKey previousValue:previousNoteValue];
}

- (IBAction)editSpellingExclusions:(id)sender
{
    [TSSpellSupport editSpellingExclusions:sender];
}

- (IBAction)spellCheckCommandPressed:sender
{
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:TurnOffCommandSpellCheckKey];
}

- (IBAction)spellCheckParameterPressed:sender
{
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state]  forKey:TurnOffParameterSpellCheckKey];
    
}

- (IBAction)spellCheckCommentPressed:sender
{
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state]  forKey:TurnOffCommentSpellCheckKey];
}




/*" This method is connected to the "Console" matrix on the TeX pane.

A tag of 0 means "always", a tag of 1 means "when errors occur".
"*/
- (IBAction)consoleBehaviorChanged:sender
{

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:ConsoleBehaviorKey];
}

- (IBAction)dictionaryPressed: sender
{
    // The automatic choice has no identifier; the others keep the checker's.
    NSString *language = [[sender selectedItem] representedObject];
    if (![language isKindOfClass:[NSString class]] || [language length] == 0)
    {
        [SUD setBool:YES forKey:spellingAutomaticDefaultKey];
        [SUD setObject:@" " forKey:spellingLanguageDefaultKey];
    }
    else
    {
        [SUD setBool:NO forKey:spellingAutomaticDefaultKey];
        [SUD setObject:language forKey:spellingLanguageDefaultKey];
    }
    TSPostPreferenceNotifications([NSSet setWithArray:@[spellingLanguageDefaultKey, spellingAutomaticDefaultKey]], self);
}


/*" This method is connected to the "After Typesetting" matrix on the Preference pane.
A tag of 0 means "Activate Preview"; a tag of 1 means "Continue Editing".
"*/
- (IBAction)afterTypesettingChanged:sender;
{
	BOOL newBoolValue;
    NSInteger newValue;
	NSInteger		tagValue;
	

	tagValue = [[sender selectedCell] tag];
    
    if (tagValue == 1)
		newBoolValue = NO;
	else
		newBoolValue = YES;
    
    newValue = tagValue;
    if (newValue > 2)
        newValue = 0;
    
    
	[SUD setBool:newBoolValue forKey:BringPdfFrontOnTypesetKey];
    [SUD setInteger:newValue forKey: BringFrontOnTypesetKey];
    
}

/*" On Typesetting Pane

A tag of 0 means "no", a tag of 1 means "yes".
"*/
- (IBAction)syncTabButtonPressed:sender
{

    // since the default program values map identically to the tags of the NSButtonCells,
    // we can use the tag directly here.
    [SUD setBool:[(NSCell *)sender state] forKey:SyncUseTabsKey];
}


//==============================================================================
// other target/action methods
//==============================================================================
/*" This method is connected to the OK button.
"*/


/*" This method is connected to the Cancel button.
"*/


//==============================================================================
// notification methods
//==============================================================================
/*" This method will be called whenever the user defaults change. We simply update the state of the prefences window and all of its controls. This may sound like the "brute force" method (in fact it is) but since the UserDefaults aren't likely to change from outside of this class we'll ignore that for now.
"*/
/*" Actually, Feb 26, 2009, I discovered that this routine is often called, including at terminate time when some objects it calls may already be disposed! 
 I have no idea why we'd ever want to call this routine. Note that updateControlsFromUserDefaults is called by showPreferences, so since this only calls it when
 the window is not visible, and it will be called again when it becomes visible, I don't see what point! RMK"*/
- (void)userDefaultsChanged:(NSNotification *)notification
{
	// only update the window's controls when the window is not visible.
	// If the window is visible the user edits it directly with the mouse.
	if ([_prefsWindow isVisible] == NO) {
		// [self updateControlsFromUserDefaults:[notification object]];
	}
}

//==============================================================================
// API used by other TeXShop classes
//==============================================================================

/*" This method returns a relative path name of 'path', based on fromFile: file. If the second argument 'file' is nil, it will return an absolute path of 'path'. Added by zenitani, Feb 13, 2003. "*/
- (NSString *)relativePath: (NSString *)path fromFile: (NSString *)file
{
	NSArray *a, *b;
	NSString *rpath = @"", *astr, *bstr;

	a = [[ file stringByDeletingLastPathComponent ] pathComponents ];
	b = [ path pathComponents ];
	NSUInteger ai = [a count], bi = [b count], i, j;
	if( ai == 0 ) return path;
	for( i=0; ((i<ai)&&(i<bi)); i++ ){
		astr = [a objectAtIndex: i];
		bstr = [b objectAtIndex: i];
		if( [astr compare: bstr] != NSOrderedSame )  break;
	}
//    NSLog( @"%d %d %d", ai, bi, i );
	for( j=0; j<(ai-i); j++ ){
		rpath = [rpath stringByAppendingString: @"../"];
//        NSLog( @"%@\n", rpath );
	}
	for( j=i; j<bi-1; j++ ){
		rpath = [rpath stringByAppendingFormat: @"%@/", [b objectAtIndex: j]];
//        NSLog( @"%@\n", rpath );
	}
	rpath = [rpath stringByAppendingFormat: @"%@", [b objectAtIndex: (bi-1)]];
	return rpath;
}


/*" This method will be called when no defaults were registered so far. Since this is the first time that TeXShop runs, we register a standard defaults set (from the FactoryDefaults.plist) and fill ~/Library/TeXShop/Templates with our templates.
"*/
- (void)registerFactoryDefaults
{
	NSString *fileName;
	NSDictionary *factoryDefaults;
    NSStringEncoding theEncoding;

	// register defaults
	fileName = [[NSBundle mainBundle] pathForResource:@"FactoryDefaults" ofType:@"plist" inDirectory:@"Defaults"];
	NSParameterAssert(fileName != nil);
	factoryDefaults = [[NSString stringWithContentsOfFile:fileName usedEncoding: &theEncoding error: NULL] propertyList];

	[SUD setPersistentDomain:factoryDefaults forName:TSPreferencesDomainName()];
	[SUD synchronize]; /* added by Koch Feb 19, 2001 to fix pref bug when no defaults present */

	// also register the default font. documentFont was set in -init, dump it here to
	// the user defaults
	[SUD setObject:[NSArchiver archivedDataWithRootObject:self.documentFont] forKey:DocumentFontKey];
    [SUD setObject:[NSArchiver archivedDataWithRootObject:self.fontAttributes] forKey:DocumentFontAttributesKey];
	[SUD synchronize];
}

- (void)addPreferenceField:(NSControl *)field rule:(TSPreferenceInput *)rule
{
    if (field == nil) return;
    [self.inputRules setObject:rule forKey:field];
    // The common validator owns both regular editing and no-UI termination.
    // A whole-number field only keeps its typing to digits and carries its
    // range for the stepper beside it.
    field.formatter = rule.kind == TSPreferenceInputInteger ? [[TSIntegerInputFormatter alloc] initWithInput:rule] : nil;
    if ([field isKindOfClass:NSTextField.class]) ((NSTextField *)field).delegate = self;
}
- (void)configurePreferenceInputs
{
    self.inputRules = [NSMapTable strongToStrongObjectsMapTable];
    self.inputEditing = [TSPreferenceEditing new];
    [self addPreferenceField:tabIndentField rule:[[TSPreferenceInput alloc] initWithKey:tabsKey
        kind:TSPreferenceInputInteger minimum:TSTabWidthRange.minimum maximum:TSTabWidthRange.maximum allowsEmpty:NO notification:TSPreferenceNotificationForKey(tabsKey)]];
    [self addPreferenceField:firstParagraphIndentField rule:[[TSPreferenceInput alloc] initWithKey:SourceFirstLineHeadIndentKey
        kind:TSPreferenceInputInteger minimum:TSParagraphIndentRange.minimum maximum:TSParagraphIndentRange.maximum allowsEmpty:NO notification:TSPreferenceNotificationForKey(SourceFirstLineHeadIndentKey)]];
    [self addPreferenceField:remainingParagraphIndentField rule:[[TSPreferenceInput alloc] initWithKey:SourceHeadIndentKey
        kind:TSPreferenceInputInteger minimum:TSParagraphIndentRange.minimum maximum:TSParagraphIndentRange.maximum allowsEmpty:NO notification:TSPreferenceNotificationForKey(SourceHeadIndentKey)]];
    [self addPreferenceField:interlineSpacingField rule:[[TSPreferenceInput alloc] initWithKey:SourceInterlineSpaceKey
        kind:TSPreferenceInputInteger minimum:TSInterlineSpaceRange.minimum maximum:TSInterlineSpaceRange.maximum allowsEmpty:NO notification:TSPreferenceNotificationForKey(SourceInterlineSpaceKey)]];
    [self addPreferenceField:_magTextField rule:[[TSPreferenceInput alloc] initWithKey:PdfMagnificationKey
        kind:TSPreferenceInputPercentage minimum:20 maximum:400 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_HtmlHomeField rule:[[TSPreferenceInput alloc] initRestoringDefaultForKey:HtmlHomeKey]];
    [self addPreferenceField:_texCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:TexCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_latexCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:LatexCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_texGSCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:TexGSCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_latexGSCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:LatexGSCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_tetexBinPathField rule:[[TSPreferenceInput alloc] initWithKey:TetexBinPath
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_gsBinPathField rule:[[TSPreferenceInput alloc] initWithKey:GSBinPath
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_altPathField rule:[[TSPreferenceInput alloc] initWithKey:AltPathKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil]];
    [self addPreferenceField:_kpsetoolField rule:[[TSPreferenceInput alloc] initRestoringDefaultForKey:KpsetoolKey]];
    [self addPreferenceField:_bibTeXengineField rule:[[TSPreferenceInput alloc] initWithKey:BibTeXengineKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:self.makeIndexEngineField rule:[[TSPreferenceInput alloc] initWithKey:MakeIndexEngineKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:self.metaPostEngineField rule:[[TSPreferenceInput alloc] initWithKey:MetaPostEngineKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_texScriptCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:TexScriptCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil]];
    [self addPreferenceField:_latexScriptCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:LatexScriptCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil]];
}

- (void)showPreferenceError:(NSString *)message
{
    if (self.endingPreferences || _prefsWindow == nil || _prefsWindow.attachedSheet != nil) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Settings could not be saved", @"");
    alert.informativeText = message;
    [alert beginSheetModalForWindow:_prefsWindow completionHandler:nil];
}
- (void)presentInputErrorForField:(NSControl *)field
{
    if (self.inputErrorPresented || self.endingPreferences || _prefsWindow.attachedSheet != nil) return;
    self.inputErrorPresented = YES;
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Enter a valid setting", @"");
    [alert addButtonWithTitle:NSLocalizedString(@"Continue Editing", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Restore This Field", @"")];
    TSPreferenceInput *rule = [self.inputRules objectForKey:field];
    if (rule == nil) { self.inputErrorPresented = NO; return; }
    __weak TSPreferences *weakSelf = self;
    [alert beginSheetModalForWindow:_prefsWindow completionHandler:^(NSModalResponse response) {
        TSPreferences *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        strongSelf.inputErrorPresented = NO;
        if (strongSelf.endingPreferences) return;
        if (response == NSAlertSecondButtonReturn) {
            [strongSelf.inputEditing restoreField:field rule:rule defaults:SUD];
        }
    }];
}
- (BOOL)commitPreferenceField:(NSControl *)field showError:(BOOL)showError reflect:(BOOL)reflect
{
    if (field == nil) return YES;
    TSPreferenceInput *rule = [self.inputRules objectForKey:field];
    if (rule == nil) return YES;
    id previousNoteValue = [self.settingsChangeNotes currentValueForKey:rule.key] ?: NSNull.null;
    BOOL valid = [self.inputEditing commitField:field rule:rule defaults:SUD reflect:reflect sender:self];
    if (valid && !self.endingPreferences) [self.settingsChangeNotes recordUserChangeForKey:rule.key previousValue:previousNoteValue];
    if (!valid && showError) [self presentInputErrorForField:field];
    // A command typed by hand may no longer match the profile shown.
    if (valid) [self refreshEngineProfileFromDefaults:SUD];
    return valid;
}
- (void)controlTextDidBeginEditing:(NSNotification *)notification
{
    NSControl *field = notification.object;
    if ([self.inputRules objectForKey:field] != nil) [self.inputEditing markEdited:field];
}
- (void)controlTextDidChange:(NSNotification *)notification
{
    [self controlTextDidBeginEditing:notification];
}

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)editor
{
    return [self commitPreferenceField:control showError:YES reflect:YES];
}
- (BOOL)finishPreferenceEditing:(BOOL)showError
{
    if (showError && _prefsWindow.attachedSheet != nil) return NO;
    BOOL valid = YES;
    for (NSControl *field in self.inputRules) {
        if (field.currentEditor != nil && ![self commitPreferenceField:field showError:showError reflect:showError]) {
            valid = NO;
            if (showError) return NO;
        }
    }
    if (showError) return [_prefsWindow makeFirstResponder:nil];
    return valid;
}
- (BOOL)windowShouldClose:(NSWindow *)window
{
    return window != _prefsWindow || [self finishPreferenceEditing:YES];
}
- (void)windowWillClose:(NSNotification *)notification
{
    if (notification.object == _prefsWindow) [self tearDownPreferenceEditing];
}
- (void)setAllThemeEditingEnabled:(BOOL)enabled
{
    // A category can be detached from the window while its controls still exist.
    NSView *appearance = [self.settingsController viewForCategoryIdentifier:TSSettingsCategoryAppearance];
    if (appearance != nil) [self setThemeEditingEnabled:enabled inView:appearance];
    for (TSPrefPaneController *pane in self.preferencePanes) [self setThemeEditingEnabled:enabled inView:pane.view];
}
- (void)releasePreferencePanels
{
    [self deactivatePreferenceColorWells];
    NSFontManager *manager = [NSFontManager sharedFontManager];
    if (self.ownsFontPanel && manager.target == nil &&
        (_prefsWindow.isKeyWindow || _prefsWindow.isMainWindow)) {
        [[manager fontPanel:NO] close];
    }
    self.ownsFontPanel = NO;
    self.fontEditingContext = TSSettingsFontNone;
}
- (void)tearDownPreferenceEditing
{
    self.endingPreferences = YES;
    self.themeOperationGeneration++;
    if (_prefsWindow.attachedSheet != nil) [_prefsWindow endSheet:_prefsWindow.attachedSheet returnCode:NSModalResponseCancel];
    // The first-launch search goes on after Settings closes, and asks without it.
    if (!self.initialEnginePathSearchPending) [self cancelEnginePathDiscovery];
    [self releasePreferencePanels];
    [self.inputEditing clear];
    [self.settingsController endSession];
}
- (void)finishPreferencesForTermination
{
    self.quittingPreferences = YES;
    self.endingPreferences = YES;
    self.themeOperationGeneration++;
    [self cancelEnginePathDiscovery];
    if (_prefsWindow.attachedSheet != nil) [_prefsWindow endSheet:_prefsWindow.attachedSheet returnCode:NSModalResponseCancel];
    [self finishPreferenceEditing:NO];
    // Do not invoke formatter delegates or actions that could display a sheet.
    for (NSControl *field in self.inputRules) [field abortEditing];
    [self tearDownPreferenceEditing];
}

//==============================================================================
// helpers
//==============================================================================

/*"  %{This method is not to be called from outside of this class.}

This method retrieves the application preferences from the defaults object and sets the controls in the window accordingly.
"*/
#include "TSSettingsPaneRefresh.inc"

/*" %{This method is not to be called from outside of this class}

This method updates the textField that represents the name of the selected font in the Document pane.
"*/
- (void)updateDocumentFontTextField
{
	NSString *fontDescription;

	fontDescription = [NSString stringWithFormat:@"%@ - %2.0f", [self.documentFont displayName], [self.documentFont pointSize]];
	[_documentFontTextField setStringValue:fontDescription];
}

- (void)updateConsoleFontTextField
{
	NSString *fontDescription;

	fontDescription = [NSString stringWithFormat:@"%@ - %2.0f", [SUD stringForKey:ConsoleFontNameKey], [SUD floatForKey:ConsoleFontSizeKey]];
	[_consoleFontTextField setStringValue:fontDescription];
}




/*" %{This method is not to be called from outside of this class.} "*/


@end
