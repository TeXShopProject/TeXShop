// The owners the compiled nibs connect to, and the layout the application
// applies to each window after loading its nib. Shared by the checks that
// load every localized nib.
#import "TSDialogButtonLayout.h"
#import "TSConsoleButtonRow.h"
#import "TSMarkMenu.h"
#import "TSOlderPanelLayout.h"
// The Matrix and LaTeX panels are loaded by their own controllers, which lay them out after loading. A check
// that defines TS_PANEL_CONTROLLERS compiles their sources (panel_controller_sources in panel_sources.py).
#ifdef TS_PANEL_CONTROLLERS
#import "TSMatrixPanelController.h"
#import "TSLaTeXPanelController.h"
#import "PanelEnvironment.h"
#endif
// Older nibs set outlets directly on instance variables of these names.
@interface SpacingOwner : NSObject { @public id linePanel, projectPanel, extensionPanel, outputWindow; }
@property (strong) NSMutableDictionary *outlets;
@end
// The windows TSOlderPanelLayout fits after TSDocument loads its nib, and the
// logWindow property, which the nib sets through its setter.
@interface SpacingOwner () { @public id printRequestPanel, requestWindow; }
@property (strong) id logWindow;
@end
// The pull-down buttons of the toolbars, which TSToolbarController titles and fits.
@interface SpacingOwner () { @public id tags, stags, labels, slabels; }
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
#ifdef TS_PANEL_CONTROLLERS
    TSInstallPanelEnvironment();
    if ([name isEqual:@"matrixpanel.nib"]) return [[TSMatrixPanelController alloc] initWithWindow:nil];
    if ([name isEqual:@"completionpanel1.2.nib"]) return [[TSLaTeXPanelController alloc] initWithWindow:nil];
#endif
    return [SpacingOwner new];
}
// The layout the application applies after loading each nib.
static void ApplyProductionLayout(NSString *name, id owner, NSArray *objects) {
    NSArray<NSWindow *> *windows = [objects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) { return [o isKindOfClass:NSWindow.class]; }]];
    if ([name isEqual:@"TSDocument.nib"]) {
        SpacingOwner *document = owner;
        if (!document->linePanel || !document->projectPanel || !document->extensionPanel) { printf("ERROR TSDocument.nib panels are not connected\n"); exit(2); }
        for (NSWindow *panel in @[document->linePanel, document->projectPanel, document->extensionPanel]) TSLayoutDialogButtonRow(panel);
        // TSDocument -setupConsole: push buttons along the top of the console.
        if (![document->outputWindow isKindOfClass:NSWindow.class]) { printf("ERROR TSDocument.nib console is not connected\n"); exit(2); }
        TSLayoutConsoleButtonRow(document->outputWindow);
        // TSToolbarController: the Tags and Labels pull-downs, titled as the document titles them.
        if (!document->tags || !document->stags || !document->labels || !document->slabels) { printf("ERROR TSDocument.nib toolbar pull-downs are not connected\n"); exit(2); }
        for (NSPopUpButton *tag in @[document->tags, document->stags]) TSFitToolbarPullDown(tag, NSLocalizedString(@"Tags", @"Tags"));
        for (NSPopUpButton *label in @[document->labels, document->slabels]) TSFitToolbarPullDown(label, NSLocalizedString(@"Labels", @"Labels"));
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
#ifdef TS_PANEL_CONTROLLERS
    else if ([owner isKindOfClass:NSWindowController.class]) {
        // NSWindowController calls this after loading the nib.
        [(NSWindowController *)owner windowDidLoad];
    }
#endif
    if ([name isEqual:@"TSDocument.nib"]) {
        // TSDocument -windowControllerDidLoadNib: lays out the Log File window.
        SpacingOwner *document = owner;
        if (![document.logWindow isKindOfClass:NSWindow.class]) { printf("ERROR TSDocument.nib log window is not connected\n"); exit(2); }
        TSLayoutLogWindow(document.logWindow);
        // MyPDFKitView fits Image Type: in the accessory of its Save Selection panel.
        for (id o in objects)
            if ([o isKindOfClass:NSView.class])
                for (NSView *v in [o subviews])
                    if ([v isKindOfClass:NSPopUpButton.class] && [[((NSPopUpButton *)v).itemTitles componentsJoinedByString:@"\n"] containsString:@"JPEG"]) TSFitLabelsBeforePopUps(o);
    } else if ([name isEqual:@"MainMenu.nib"]) {
        // TSStationery draws its list without vertical grid lines; TSDocumentController fits Encoding: in the open panel.
        for (id o in objects) {
            if ([o isKindOfClass:NSWindow.class]) TSRemoveVerticalGridLines([o contentView]);
            else if ([o isKindOfClass:NSView.class]) TSFitLabelsBeforePopUps(o);
        }
    }
}
