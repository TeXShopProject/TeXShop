// Printing a PDF as Preview does; see TSPDFPrinting.h.
#import "TSPDFPrinting.h"

// PDFKit's print view (printOperationForPrintInfo:scalingMode:autoRotate:) keeps its two
// choices under these keys and reads them while it prints, so the panel section can change
// them with the preview following. Should a later PDFKit stop reading them, a print still
// uses the choices the operation was made with.
NSString * const TSPDFPrintAutoRotateKey = @"PDFPrintAutoRotate";
NSString * const TSPDFPrintScalingModeKey = @"PDFPrintScalingMode";

static NSString *TSPrintLabelWithoutColon(NSString *label)
{
    NSCharacterSet *trailing = [NSCharacterSet characterSetWithCharactersInString:@":：   "];
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
    self.scalePercent = sender.integerValue;
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
             @{NSPrintPanelAccessorySummaryItemNameKey: TSPrintLabelWithoutColon([bundle localizedStringForKey:@"Scale:" value:nil table:nil]),
               NSPrintPanelAccessorySummaryItemDescriptionKey: scaling}];
}

@end

NSPrintOperation *TSPDFPrintOperation(PDFDocument *document, NSPrintInfo *printInfo)
{
    if (document.pageCount == 0)
        return nil;
    NSMutableDictionary *settings = printInfo.dictionary;
    // The first print of a document turns pages and fits them to the paper, as Preview does.
    if (settings[TSPDFPrintAutoRotateKey] == nil)
        settings[TSPDFPrintAutoRotateKey] = @YES;
    if (settings[TSPDFPrintScalingModeKey] == nil)
        settings[TSPDFPrintScalingModeKey] = @(kPDFPrintPageScaleToFit);

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
