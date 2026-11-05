// Asynchronous monitoring across reads and atomic replacements.
#import <Foundation/Foundation.h>

// Public methods are meant for the main thread; both callbacks always run there,
// and stop called from another thread takes effect on the main queue. The prepare
// callback returns a document generation, or nil to defer while dirty. The accept
// callback must reject a stale generation. An exception from either callback is
// logged and treated as a deferred or rejected read. All monitoring I/O and
// snapshot hashing use a private serial queue; stop never waits for a stalled
// filesystem call.
@interface TSFileChangeMonitor : NSObject
@property (nonatomic, readonly, copy) NSString *path;
- (instancetype)initWithPath:(NSString *)path
                    prepare:(NSNumber *(^)(void))prepare
                     accept:(BOOL (^)(NSData *, NSData *, NSNumber *))accept;
- (void)stop;
@end
FOUNDATION_EXPORT NSData *TSSourceFingerprint(NSData *data);
