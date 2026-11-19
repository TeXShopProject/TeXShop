#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface TSEnginePathDiscovery : NSObject
+ (BOOL)shouldSearchOnFirstLaunch:(NSDictionary *)persistentSettings;
+ (NSArray<NSString *> *)systemSearchPaths;
+ (NSArray<NSString *> *)texLivePathsUnderRoots:(NSArray<NSString *> *)roots;
// The release named in a --version banner: name ("TeX Live 2027/dev"), year and dev; nil when none.
+ (nullable NSDictionary *)texLiveReleaseInBanner:(NSString *)banner;
+ (BOOL)directory:(NSString *)directory containsPrograms:(NSArray<NSString *> *)programs;
// Each list is newest first. Entries contain path and version; the entry to select first has default set.
// An empty list leaves the setting unchanged.
+ (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)candidatesForPaths:(NSArray<NSString *> *)paths
                                                              currentTeX:(NSString *)texPath
                                                      currentGhostscript:(NSString *)gsPath;
@end
NS_ASSUME_NONNULL_END
