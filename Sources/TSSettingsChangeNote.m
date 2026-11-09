// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsChangeNote.h"
#import "TSPreferenceKey.h"
#import "globals.h"

static NSMutableDictionary<NSString *, id> *launchValues;
void TSSettingsRememberLaunchValue(NSString *key, id value) {
    if (launchValues == nil) launchValues = [NSMutableDictionary dictionary];
    if (launchValues[key] == nil) launchValues[key] = [value copy];
}
NSDictionary<NSString *, id> *TSSettingsLaunchValues(void) { return [launchValues copy] ?: @{}; }

@interface TSSettingsChangeNote ()
@property (strong) NSLayoutConstraint *readableWidth;
@end

@implementation TSSettingsChangeNote
- (instancetype)initWithText:(NSString *)text {
    self = [super initWithFrame:NSZeroRect]; if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.identifier = @"settings.change-note";
    self.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.alignment = NSLayoutAttributeFirstBaseline; self.spacing = 4;
    NSFont *font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    NSImage *symbol = [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill" accessibilityDescription:nil];
    NSImageView *icon = [NSImageView new];
    NSImageSymbolConfiguration *configuration = [[NSImageSymbolConfiguration configurationWithPointSize:font.pointSize weight:NSFontWeightRegular]
        configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationPreferringMulticolor]];
    icon.image = [symbol imageWithSymbolConfiguration:configuration];
    icon.identifier = @"settings.warning-symbol.multicolor"; icon.accessibilityElement = NO;
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = font; label.textColor = NSColor.labelColor;
    [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addArrangedSubview:icon]; [self addArrangedSubview:label];
    self.accessibilityLabel = text; self.hidden = YES;
    return self;
}
- (void)setShown:(BOOL)shown announce:(BOOL)announce {
    BOOL newlyShown = self.hidden && shown; self.hidden = !shown;
    self.readableWidth.active = shown;
    if (newlyShown && announce) NSAccessibilityPostNotificationWithUserInfo(self, NSAccessibilityAnnouncementRequestedNotification,
        @{NSAccessibilityAnnouncementKey:self.accessibilityLabel ?: @"", NSAccessibilityPriorityKey:@(NSAccessibilityPriorityMedium)});
}
@end

typedef NS_ENUM(NSUInteger, TSSettingsNoteValueKind) { TSSettingsNoteBoolean, TSSettingsNoteInteger, TSSettingsNoteDouble, TSSettingsNoteString };
@interface TSSettingsNoteRule : NSObject
@property (copy) NSString *category, *key, *row, *message;
@property TSSettingsNoteValueKind kind;
@property BOOL restart;
@property (copy) BOOL (^condition)(void);
@property (strong) TSSettingsChangeNote *view;
@end
@implementation TSSettingsNoteRule @end

@interface TSSettingsChangeNotes ()
@property (strong) NSUserDefaults *defaults;
@property (copy) NSDictionary<NSString *, id> *launch;
@property (copy) NSDictionary<NSString *, id> *original;
@property (copy) NSDictionary<NSString *, NSArray<TSSettingsNoteRule *> *> *categories;
@property BOOL open;
@end
@implementation TSSettingsChangeNotes
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults launchValues:(NSDictionary<NSString *,id> *)values bundle:(NSBundle *)bundle {
    self=[super init]; if(!self)return nil;
    _defaults=defaults; _launch=[values copy]; _original=@{};
    _hasSourceWindow=^BOOL{return NO;}; _hasPDFWindow=^BOOL{return NO;};
    __weak TSSettingsChangeNotes *weakSelf=self;
    TSSettingsNoteRule *(^rule)(NSString *,NSString *,NSString *,NSString *,TSSettingsNoteValueKind,BOOL,BOOL(^)(void)) = ^TSSettingsNoteRule *(NSString *category,NSString *key,NSString *row,NSString *message,TSSettingsNoteValueKind kind,BOOL restart,BOOL(^condition)(void)) {
        TSSettingsNoteRule *r=[TSSettingsNoteRule new];r.category=category;r.key=key;r.row=row;r.message=message;r.kind=kind;r.restart=restart;r.condition=condition;
        r.view=[[TSSettingsChangeNote alloc]initWithText:[bundle localizedStringForKey:message value:message table:@"Localizable"]]; return r;
    };
    NSString *restart=@"Takes effect after you restart TeXShop.";
    _categories=@{
        @"spelling":@[rule(@"spelling",TSTeXAwareSpellCheckingKey,@"row.catalog.spelling.1.0",@"This does not turn spell checking while typing on or off.",TSSettingsNoteBoolean,NO,^BOOL{return YES;})],
        @"preview":@[rule(@"preview",PdfMagnificationKey,@"row.catalog.preview.0.2",@"Open PDFs keep their zoom. The new value applies to PDFs opened from now on.",TSSettingsNoteDouble,NO,^BOOL{return weakSelf.hasPDFWindow();})],
        @"documents":@[rule(@"documents",EncodingKey,@"row.catalog.documents.0.0",@"Currently open files retain their old encoding.",TSSettingsNoteString,NO,^BOOL{return weakSelf.hasSourceWindow();}),rule(@"documents",AutoSaveEnabledKey,@"row.catalog.documents.1.0",restart,TSSettingsNoteBoolean,YES,^BOOL{return YES;})],
        @"editor":@[rule(@"editor",FindMethodKey,@"row.catalog.editor.7.0",restart,TSSettingsNoteInteger,YES,^BOOL{return [weakSelf.launch[FindMethodKey] integerValue] == 2 || [weakSelf.defaults integerForKey:FindMethodKey] == 2;})]
    };
    return self;
}
- (TSSettingsNoteRule *)ruleForKey:(NSString *)key {
    for(NSArray<TSSettingsNoteRule *> *rules in self.categories.allValues)for(TSSettingsNoteRule *rule in rules)if([rule.key isEqual:key])return rule;
    return nil;
}
- (id)currentValueForKey:(NSString *)key {
    TSSettingsNoteRule *rule=[self ruleForKey:key];
    if(rule==nil)return [self.defaults objectForKey:key] ?: NSNull.null;
    switch(rule.kind){
        case TSSettingsNoteBoolean:return @([self.defaults boolForKey:key]);
        case TSSettingsNoteInteger:return @([self.defaults integerForKey:key]);
        case TSSettingsNoteDouble:return @([self.defaults doubleForKey:key]);
        case TSSettingsNoteString:return [self.defaults stringForKey:key] ?: @"";
    }
}
- (NSView *)find:(NSString *)identifier inView:(NSView *)view {
    if([view.identifier isEqual:identifier])return view;
    for(NSView *child in view.subviews){NSView *found=[self find:identifier inView:child];if(found)return found;}return nil;
}
- (void)attachToPanes:(NSDictionary<NSString *,NSViewController *> *)panes {
    for(NSString *category in self.categories)for(TSSettingsNoteRule *rule in self.categories[category]){
        NSView *row=[self find:rule.row inView:panes[category].view];
        NSStackView *host=(NSStackView *)[self find:@"label.catalog-stack" inView:row];
        NSAssert(host!=nil,@"Change note requires a catalog label stack: %@",rule.row);
        [host addArrangedSubview:rule.view];
        [rule.view.widthAnchor constraintEqualToAnchor:host.widthAnchor].active=YES;
        rule.view.readableWidth = [host.widthAnchor constraintGreaterThanOrEqualToConstant:200];
    }
}
- (void)beginSession {
    NSMutableDictionary *values=[NSMutableDictionary dictionary];
    for(NSArray<TSSettingsNoteRule *> *rules in self.categories.allValues)for(TSSettingsNoteRule *rule in rules)values[rule.key]=[self currentValueForKey:rule.key];
    self.original=values;self.open=YES;[self leaveCategory];
}
- (void)leaveCategory {
    for(NSArray<TSSettingsNoteRule *> *rules in self.categories.allValues)for(TSSettingsNoteRule *rule in rules)if(!rule.restart)[rule.view setShown:NO announce:NO];
    [self refreshRestartNotes];
}
- (void)endSession { self.open=NO; for(NSArray<TSSettingsNoteRule *> *rules in self.categories.allValues)for(TSSettingsNoteRule *rule in rules)[rule.view setShown:NO announce:NO]; }
- (void)valuesReplaced { [self leaveCategory]; }
- (void)refreshRestartNotes {
    for(NSArray<TSSettingsNoteRule *> *rules in self.categories.allValues)for(TSSettingsNoteRule *rule in rules)if(rule.restart){
        id initial=self.launch[rule.key];BOOL show=self.open && initial!=nil && ![[self currentValueForKey:rule.key] isEqual:initial] && rule.condition();
        [rule.view setShown:show announce:YES];
    }
}
- (void)recordUserChangeForKey:(NSString *)key previousValue:(id)value {
    TSSettingsNoteRule *rule=[self ruleForKey:key];if(rule==nil || !self.open)return;
    id current=[self currentValueForKey:key];
    if([current isEqual:value])return;
    id original=rule.restart?self.launch[key]:self.original[key];
    BOOL show=original!=nil && ![current isEqual:original] && rule.condition();
    [rule.view setShown:show announce:YES];
}
@end
