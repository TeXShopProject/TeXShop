// The owners the compiled nibs connect to, and the layout the application
// applies to each window after loading its nib. Shared by the checks that
// load every localized nib.
#import "TSDialogButtonLayout.h"
#import "TSMarkMenu.h"
// Older nibs set outlets directly on instance variables of these names.
@interface SpacingOwner : NSObject { @public id linePanel, projectPanel, extensionPanel; }
@property (strong) NSMutableDictionary *outlets;
@end
@implementation SpacingOwner
- (instancetype)init { if ((self = [super init])) _outlets = [NSMutableDictionary dictionary]; return self; }
- (void)setValue:(id)v forUndefinedKey:(NSString *)k { if (v) self.outlets[k] = v; }
- (id)valueForUndefinedKey:(NSString *)k { return nil; }
// Older nibs connect an action only when the owner responds to it.
- (IBAction)didTapDoneButton:(id)sender {}
- (IBAction)didTapCancelButton:(id)sender {}
- (IBAction)itemChosen:(id)sender {}
@end
// The owner the application gives each nib.
static id ProductionOwner(NSString *name) {
    return [SpacingOwner new];
}
// The layout the application applies after loading each nib.
static void ApplyProductionLayout(NSString *name, id owner, NSArray *objects) {
    NSArray<NSWindow *> *windows = [objects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) { return [o isKindOfClass:NSWindow.class]; }]];
    if ([name isEqual:@"TSDocument.nib"]) {
        SpacingOwner *document = owner;
        if (!document->linePanel || !document->projectPanel || !document->extensionPanel) { printf("ERROR TSDocument.nib panels are not connected\n"); exit(2); }
        for (NSWindow *panel in @[document->linePanel, document->projectPanel, document->extensionPanel]) TSLayoutDialogButtonRow(panel);
    } else if ([name isEqual:@"MainMenu.nib"]) {
        // HelpDocuments (two panels) and TSStationery lay out their OK/Cancel panels.
        NSUInteger dialogs = 0;
        for (NSWindow *w in windows) {
            BOOL ret = NO, esc = NO;
            for (NSView *v in w.contentView.subviews) if ([v isKindOfClass:NSButton.class]) { ret |= [((NSButton *)v).keyEquivalent isEqual:@"\r"]; esc |= [((NSButton *)v).keyEquivalent isEqual:@"\033"]; }
            if (ret && esc) { TSLayoutDialogButtonRow(w); dialogs++; }
        }
        if (dialogs != 3) { printf("ERROR MainMenu.nib has %lu OK/Cancel panels, not the three the application lays out\n", (unsigned long)dialogs); exit(2); }
    } else if ([name isEqual:@"CustomModalWindowController.xib"]) {
        // Its constraints space the buttons; lay them out as a window would.
        for (NSWindow *w in windows) [w.contentView layoutSubtreeIfNeeded];
    } else if ([name isEqual:@"FindPanel.nib"]) {
        for (NSWindow *w in windows) TSLayoutBottomActionRow(w);
    }
}
