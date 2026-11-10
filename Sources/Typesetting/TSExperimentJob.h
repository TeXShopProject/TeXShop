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

// Fills an Experiment folder with symbolic links to the items of the document's folder, except
// those named `name` or beginning with `name.`, so that paths relative to the document, also
// those beginning with ./ that TeX does not look up in TEXINPUTS, resolve as when the document
// is typeset (#8). Removing the folder removes only the links. Returns the number of links.
+ (NSUInteger)linkItemsOfDirectory:(NSURL *)source intoDirectory:(NSURL *)directory exceptName:(NSString *)name;
// Copies the document's .aux file, up to its last complete line, so that \ref and \cite in the
// Experiment resolve (#8); the file may be half written while the document is typeset.
+ (BOOL)copyAuxiliaryFile:(NSURL *)aux toURL:(NSURL *)destination;
@end
