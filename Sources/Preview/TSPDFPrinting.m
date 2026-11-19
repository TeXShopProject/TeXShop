// Printing a PDF as Preview does; see TSPDFPrinting.h.
#import "TSPDFPrinting.h"
#import <objc/runtime.h>

// PDFKit's print view (printOperationForPrintInfo:scalingMode:autoRotate:) keeps its two
// choices under these keys and reads them while it prints, so the panel section can change
// them with the preview following. Should a later PDFKit stop reading them, a print still
// uses the choices the operation was made with.
NSString * const TSPDFPrintAutoRotateKey = @"PDFPrintAutoRotate";
NSString * const TSPDFPrintScalingModeKey = @"PDFPrintScalingMode";
// The choices of a document's last print, kept with the document itself (not in its print
// info: setting a document's print info marks it edited and enters the undo list, and
// printing the source uses its NSPrintScalingFactor).
static char TSPDFPrintChoicesKey;

NSString *TSPDFPrintLabelWithoutColon(NSString *label)
{
    // French sets a no-break space (or a narrow one) before its colon.
    NSCharacterSet *trailing = [NSCharacterSet characterSetWithCharactersInString:@": \uFF1A\u00A0\u202F"];
    NSString *result = label;
    while (result.length > 0 && [trailing characterIsMember:[result characterAtIndex:result.length - 1]])
        result = [result substringToIndex:result.length - 1];
    return result;
}

@implementation TSPDFPrintAccessory
{
    NSPrintInfo *_printInfo;
    NSButton *_autoRotateButton;
    NSButton *_scaleButton;
    NSButton *_fitButton;
    NSTextField *_scaleField;
}

- (instancetype)initWithPrintInfo:(NSPrintInfo *)printInfo
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _printInfo = printInfo;
        self.representedObject = printInfo;
        self.title = NSRunningApplication.currentApplication.localizedName ?: @"TeXShop";
    }
    return self;
}

- (NSMutableDictionary *)settings
{
    return _printInfo.dictionary;
}

- (BOOL)autoRotate
{
    return [self.settings[TSPDFPrintAutoRotateKey] boolValue];
}

- (void)setAutoRotate:(BOOL)autoRotate
{
    self.settings[TSPDFPrintAutoRotateKey] = @(autoRotate);
    _autoRotateButton.state = autoRotate ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)scaleToFit
{
    return [self.settings[TSPDFPrintScalingModeKey] integerValue] == kPDFPrintPageScaleToFit;
}

- (void)setScaleToFit:(BOOL)scaleToFit
{
    self.settings[TSPDFPrintScalingModeKey] = @(scaleToFit ? kPDFPrintPageScaleToFit : kPDFPrintPageScaleNone);
    _fitButton.state = scaleToFit ? NSControlStateValueOn : NSControlStateValueOff;
    _scaleButton.state = scaleToFit ? NSControlStateValueOff : NSControlStateValueOn;
    _scaleField.enabled = ! scaleToFit;
}

- (NSInteger)scalePercent
{
    double factor = [self.settings[NSPrintScalingFactor] doubleValue];
    return factor > 0 ? (NSInteger)lround(factor * 100) : 100;
}

- (void)setScalePercent:(NSInteger)scalePercent
{
    scalePercent = MAX(1, MIN(1000, scalePercent));
    self.settings[NSPrintScalingFactor] = @(scalePercent / 100.0);
    _scaleField.integerValue = scalePercent;
}

- (void)loadView
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    _autoRotateButton = [NSButton checkboxWithTitle:[bundle localizedStringForKey:@"Auto Rotate" value:nil table:nil]
                                             target:self action:@selector(autoRotateChanged:)];
    _scaleButton = [NSButton radioButtonWithTitle:[bundle localizedStringForKey:@"Scale:" value:nil table:nil]
                                           target:self action:@selector(scalingChanged:)];
    _fitButton = [NSButton radioButtonWithTitle:[bundle localizedStringForKey:@"Scale to Fit" value:nil table:nil]
                                         target:self action:@selector(scalingChanged:)];
    _scaleField = [NSTextField textFieldWithString:@"100"];
    _scaleField.alignment = NSTextAlignmentRight;
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.numberStyle = NSNumberFormatterNoStyle;
    formatter.minimum = @1;
    formatter.maximum = @1000;
    formatter.allowsFloats = NO;
    _scaleField.formatter = formatter;
    _scaleField.target = self;
    _scaleField.action = @selector(scaleFieldChanged:);
    [_scaleField.widthAnchor constraintEqualToConstant:52].active = YES;
    NSTextField *percent = [NSTextField labelWithString:@"%"];

    NSStackView *scaleRow = [NSStackView stackViewWithViews:@[_scaleButton, _scaleField, percent]];
    scaleRow.spacing = 6;
    NSStackView *stack = [NSStackView stackViewWithViews:@[_autoRotateButton, scaleRow, _fitButton]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(16, 20, 16, 20);
    self.view = stack;

    // The controls show the choices kept in the print info.
    self.autoRotate = self.autoRotate;
    self.scaleToFit = self.scaleToFit;
    self.scalePercent = self.scalePercent;
}

- (void)autoRotateChanged:(NSButton *)sender
{
    self.autoRotate = sender.state == NSControlStateValueOn;
}

- (void)scalingChanged:(NSButton *)sender
{
    self.scaleToFit = sender == _fitButton;
}

- (void)scaleFieldChanged:(NSTextField *)sender
{
    // An emptied field goes back to the scale in use.
    if (sender.objectValue == nil || sender.integerValue < 1) {
        sender.integerValue = self.scalePercent;
        return;
    }
    self.scalePercent = sender.integerValue;
}

// The print panel watches the summary.
+ (NSSet<NSString *> *)keyPathsForValuesAffectingLocalizedSummaryItems
{
    return [NSSet setWithObjects:@"autoRotate", @"scaleToFit", @"scalePercent", nil];
}

- (NSSet<NSString *> *)keyPathsForValuesAffectingPreview
{
    return [NSSet setWithObjects:@"autoRotate", @"scaleToFit", @"scalePercent", nil];
}

- (NSArray<NSDictionary<NSPrintPanelAccessorySummaryKey, NSString *> *> *)localizedSummaryItems
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *scaling = self.scaleToFit ? [bundle localizedStringForKey:@"Scale to Fit" value:nil table:nil]
        : [NSString stringWithFormat:@"%ld%%", (long)self.scalePercent];
    return @[@{NSPrintPanelAccessorySummaryItemNameKey: [bundle localizedStringForKey:@"Auto Rotate" value:nil table:nil],
               NSPrintPanelAccessorySummaryItemDescriptionKey: [bundle localizedStringForKey:(self.autoRotate ? @"On" : @"Off") value:nil table:nil]},
             @{NSPrintPanelAccessorySummaryItemNameKey: TSPDFPrintLabelWithoutColon([bundle localizedStringForKey:@"Scale:" value:nil table:nil]),
               NSPrintPanelAccessorySummaryItemDescriptionKey: scaling}];
}

@end

NSPrintOperation *TSPDFPrintOperation(PDFDocument *document, NSPrintInfo *documentPrintInfo, NSDocument *owner)
{
    if (document.pageCount == 0)
        return nil;
    // The document's print info stays as it is: the operation works on a copy.
    NSPrintInfo *printInfo = [documentPrintInfo copy];
    NSMutableDictionary *settings = printInfo.dictionary;
    // The choices of the document's last print; at first, as Preview: turn pages and fit them to
    // the paper. Values in the print info itself (from elsewhere) are not taken.
    NSDictionary *kept = owner ? objc_getAssociatedObject(owner, &TSPDFPrintChoicesKey) : nil;
    settings[TSPDFPrintAutoRotateKey] = kept[TSPDFPrintAutoRotateKey] ?: @YES;
    settings[TSPDFPrintScalingModeKey] = kept[TSPDFPrintScalingModeKey] ?: @(kPDFPrintPageScaleToFit);
    settings[NSPrintScalingFactor] = kept[NSPrintScalingFactor] ?: @1.0;

    // The paper follows the first page as it is shown, its /Rotate applied.
    PDFPage *first = [document pageAtIndex:0];
    NSSize size = [first boundsForBox:kPDFDisplayBoxCropBox].size;
    if ((first.rotation / 90) % 2)
        size = NSMakeSize(size.height, size.width);
    printInfo.orientation = size.width > size.height ? NSPaperOrientationLandscape : NSPaperOrientationPortrait;

    BOOL autoRotate = [settings[TSPDFPrintAutoRotateKey] boolValue];
    PDFPrintScalingMode mode = [settings[TSPDFPrintScalingModeKey] integerValue] == kPDFPrintPageScaleToFit
        ? kPDFPrintPageScaleToFit : kPDFPrintPageScaleNone;
    NSPrintOperation *operation = [document printOperationForPrintInfo:printInfo scalingMode:mode autoRotate:autoRotate];
    if (operation == nil)
        return nil;
    NSPrintPanel *panel = operation.printPanel;
    // Scale is the section's own field (as in Preview), so the panel does not show its own.
    panel.options = (panel.options | NSPrintPanelShowsOrientation | NSPrintPanelShowsPaperSize) & ~NSPrintPanelShowsScaling;
    [panel addAccessoryController:[[TSPDFPrintAccessory alloc] initWithPrintInfo:operation.printInfo]];
    return operation;
}

BOOL TSPDFPrintSucceeded(NSPrintOperation *operation, BOOL ran, NSDate *started)
{
    if (! ran)
        return NO;
    NSPrintInfo *info = operation.printInfo;
    if (! [info.jobDisposition isEqual:NSPrintSaveJob])
        return YES;
    // Saved as a file: the file is there, written by this print (not left from before).
    NSURL *url = info.dictionary[NSPrintJobSavingURL];
    if (! [url isKindOfClass:NSURL.class])
        return YES;
    NSDate *modified = nil;
    [url removeCachedResourceValueForKey:NSURLContentModificationDateKey];
    if (! [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:NULL] || modified == nil)
        return NO;
    return [modified timeIntervalSinceDate:started] > -0.01;
}

void TSPDFPrintKeepChoices(NSPrintOperation *operation, NSDocument *document)
{
    NSDictionary *chosen = operation.printInfo.dictionary;
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    for (NSString *key in @[TSPDFPrintAutoRotateKey, TSPDFPrintScalingModeKey, NSPrintScalingFactor])
        if (chosen[key] != nil)
            kept[key] = chosen[key];
    objc_setAssociatedObject(document, &TSPDFPrintChoicesKey, [kept copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
