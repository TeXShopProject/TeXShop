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
@end
