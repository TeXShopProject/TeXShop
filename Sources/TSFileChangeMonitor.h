// added by Terada: continuous monitoring across reads and atomic replacements.
#import <Foundation/Foundation.h>

// All methods and the reload block run on the main thread. Return NO from the
// block to retain a pending change (for example, while the document is dirty).
@interface TSFileChangeMonitor : NSObject
@property (nonatomic, readonly, copy) NSString *path;
- (instancetype)initWithPath:(NSString *)path reload:(BOOL (^)(void))reload;
- (void)stop;
@end
