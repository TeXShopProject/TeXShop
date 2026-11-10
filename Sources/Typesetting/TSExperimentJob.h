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

// Creates in an Experiment output folder empty folders named like those of the document's folder,
// so that TeX, run from the document's folder, can write into them there instead of failing
// (#8). Nothing is linked or copied. Returns the number of folders created.
+ (NSUInteger)createSubdirectoriesOf:(NSURL *)source inDirectory:(NSURL *)directory;
// Copies the document's .aux file, up to its last complete line, so that \ref and \cite in the
// Experiment resolve (#8); the file may be half written while the document is typeset.
+ (BOOL)copyAuxiliaryFile:(NSURL *)aux toURL:(NSURL *)destination;
@end
