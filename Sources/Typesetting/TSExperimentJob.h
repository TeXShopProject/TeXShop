#import <Foundation/Foundation.h>

// One Experiment invocation. All public methods and callbacks run on the main thread.
@interface TSExperimentJob : NSObject
@property (nonatomic, copy) void (^outputHandler)(NSData *data);
@property (nonatomic, copy) void (^completionHandler)(int status);
@property (nonatomic, readonly, getter=isActive) BOOL active;
- (BOOL)startExecutable:(NSString *)path arguments:(NSArray<NSString *> *)arguments
           environment:(NSDictionary<NSString *, NSString *> *)environment
             directory:(NSURL *)directory error:(NSError **)error;
- (BOOL)sendData:(NSData *)data error:(NSError **)error;
- (void)cancel;

// Fills an Experiment folder with copy-on-write clones of the items of the document's folder, so
// that paths relative to the document, also those beginning with ./, which TeX does not look up
// in TEXINPUTS, resolve as when the document is typeset, while whatever is written there leaves
// the document's folder alone (#8). Names in `names`, and names beginning with "file.", compared
// ignoring case, are left out for the Experiment's own files. Items that cannot be cloned, for
// example on another volume, are skipped; so is a folder of more than 5000 items. Symbolic links
// that lead out of the Experiment folder are removed. Returns the number of items cloned.
+ (NSUInteger)cloneItemsOfDirectory:(NSURL *)source intoDirectory:(NSURL *)directory exceptNames:(NSArray<NSString *> *)names;
// Copies the document's .aux file, up to its last complete line, so that \ref and \cite in the
// Experiment resolve (#8); the file may be half written while the document is typeset.
+ (BOOL)copyAuxiliaryFile:(NSURL *)aux toURL:(NSURL *)destination;
@end
