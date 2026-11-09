// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
#import "TSPrefPaneLayout.h"
@interface TSPrefPaneController ()
@property (copy, readwrite) NSArray<NSObject *> *nibObjects;
@end
@implementation TSPrefPaneController
- (void)setCategoryIdentifier:(TSSettingsCategoryID _Nullable)identifier
{
    _categoryIdentifier = [identifier copy];
    if (identifier == nil) { self.title = nil; return; }
    self.title = [(self.nibBundle ?: NSBundle.mainBundle) localizedStringForKey:identifier ?: @"" value:nil table:@"SettingsCategories"];
}
- (void)loadView
{
    NSArray<NSObject *> *objects = nil;
    NSString *name = self.nibName;
    if (name == nil || ![(self.nibBundle ?: NSBundle.mainBundle) loadNibNamed:name owner:self topLevelObjects:&objects]) {
        [NSException raise:NSInternalInconsistencyException format:@"Cannot load settings pane %@", self.nibName];
    }
    self.nibObjects = objects;
    [TSPrefPaneLayout arrangeView:self.view];
}
@end
