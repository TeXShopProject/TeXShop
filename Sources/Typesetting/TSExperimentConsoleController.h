#import <Cocoa/Cocoa.h>

@interface TSExperimentConsoleController : NSWindowController
@property (nonatomic, copy) void (^typesetHandler)(void);
@property (nonatomic, copy) void (^returnHandler)(void);
@property (nonatomic, weak) NSWindow *returnWindow;
- (void)startExecutable:(NSString *)path arguments:(NSArray<NSString *> *)arguments
           environment:(NSDictionary<NSString *, NSString *> *)environment
             directory:(NSURL *)directory encoding:(NSStringEncoding)encoding title:(NSString *)title
            completion:(void (^)(NSURL *pdfURL))completion;
- (void)toggleFromWindow:(NSWindow *)origin;
- (void)abort:(id)sender;
- (void)invalidate;
@end
