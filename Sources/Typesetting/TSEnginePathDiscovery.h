#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface TSEnginePathDiscovery : NSObject
+ (BOOL)shouldSearchOnFirstLaunch:(NSDictionary *)persistentSettings;
+ (NSArray<NSString *> *)systemSearchPaths;
+ (NSArray<NSString *> *)texLivePathsUnderRoots:(NSArray<NSString *> *)roots;
+ (BOOL)directory:(NSString *)directory containsPrograms:(NSArray<NSString *> *)programs;
// Each list is newest first. Entries contain path and version; an empty list leaves the setting unchanged.
+ (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)candidatesForPaths:(NSArray<NSString *> *)paths
                                                              currentTeX:(NSString *)texPath
                                                      currentGhostscript:(NSString *)gsPath;
@end
NS_ASSUME_NONNULL_END
