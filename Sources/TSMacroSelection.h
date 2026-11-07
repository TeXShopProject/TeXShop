#import <Foundation/Foundation.h>
@class TSMacroTreeNode;

NS_ASSUME_NONNULL_BEGIN
// Locate a saved macro in a possibly reordered, unsaved editor tree.
@interface TSMacroSelection : NSObject
+ (nullable TSMacroTreeNode *)nodeInRoot:(TSMacroTreeNode *)root indexPath:(NSIndexPath *)path name:(NSString *)name key:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
