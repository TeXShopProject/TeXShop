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
// the choices of owner's last print (TSPDFPrintKeepChoices), Auto Rotate and Scale to Fit at first.
NSPrintOperation * _Nullable TSPDFPrintOperation(PDFDocument *document, NSPrintInfo *documentPrintInfo, NSDocument * _Nullable owner);

// Whether the operation printed: it ran, and a job saved as a file wrote the file after started.
BOOL TSPDFPrintSucceeded(NSPrintOperation *operation, BOOL ran, NSDate *started);

// After a print that succeeded: the document's next print starts from these choices; other
// documents do not. The document's print info, edited state and undo list stay as they are.
void TSPDFPrintKeepChoices(NSPrintOperation *operation, NSDocument *document);

// The name of a label for the panel's summary ("Scale:" gives "Scale").
NSString *TSPDFPrintLabelWithoutColon(NSString *label);

NS_ASSUME_NONNULL_END
