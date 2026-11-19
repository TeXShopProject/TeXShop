// Printing a PDF as Preview does: each page as it is shown (its /Rotate applied),
// turned to suit the paper and scaled to fit it, with Preview's choices in the print panel.
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>

NS_ASSUME_NONNULL_BEGIN

// Keys of the print info dictionary that PDFKit's print view reads while it prints.
extern NSString * const TSPDFPrintAutoRotateKey;
extern NSString * const TSPDFPrintScalingModeKey;

// The print panel section: Auto Rotate, and Scale (a percentage) or Scale to Fit.
@interface TSPDFPrintAccessory : NSViewController <NSPrintPanelAccessorizing>
@property (nonatomic) BOOL autoRotate;
@property (nonatomic) BOOL scaleToFit;
@property (nonatomic) NSInteger scalePercent;
- (instancetype)initWithPrintInfo:(NSPrintInfo *)printInfo;
@end

// Returns the operation with the panel section, on a copy of the document's print info:
// choices kept from an earlier print of the document, Auto Rotate and Scale to Fit the first time.
NSPrintOperation * _Nullable TSPDFPrintOperation(PDFDocument *document, NSPrintInfo *documentPrintInfo);

// After a print that succeeded: the document's next print starts from these choices; other
// documents do not.
void TSPDFPrintKeepChoices(NSPrintOperation *operation, NSDocument *document);

// The name of a label for the panel's summary ("Scale:" gives "Scale").
NSString *TSPDFPrintLabelWithoutColon(NSString *label);

NS_ASSUME_NONNULL_END
