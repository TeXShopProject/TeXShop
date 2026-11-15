//
//  TSColorSupport.h
//  
//
//  Created by Richard Koch on 7/26/2018.
//  Copyright 2018 University of Oregon. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface TSColorSupport : NSObject {
    
}

+ (id)sharedInstance;

- (void)checkAndRestoreDefaults;
// Gives the bundled themes in ~/Library/TeXShop/Themes the colors that later versions changed, once.
- (void)updateBundledThemeColors;
- (NSInteger)updateBundledThemeColorsInDirectory: (NSURL *)directory after: (NSInteger)update;
- (void)initializeColors;
- (NSMutableDictionary *) dictionaryForColorFile: (NSString *) fileTitle;
- (NSColor *)colorFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey;
- (NSColor *)colorAndAlphaFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey;


- (NSColor *)liteColorWithKey: (NSString *)theKey;
- (NSColor *)darkColorWithKey: (NSString *)theKey;
- (NSColor *)liteColorAndAlphaWithKey: (NSString *)theKey;
- (NSColor *)darkColorAndAlphaWithKey: (NSString *)theKey;

- (NSColor *)colorForKey: (NSString *)theKey fromDictionary: (NSDictionary *)theDictionary isWindowDark: (BOOL)mode;
- (NSColor *)colorForKey: (NSString *)theKey isWindowDark: (BOOL)mode;
// A theme color drawn opaque, as the document's source, console and preview draw it;
// the opacity stored with the color is not used. Without the key, the built-in color.
- (NSColor *)opaqueColorForKey: (NSString *)theKey fromDictionary: (NSDictionary *)theDictionary isWindowDark: (BOOL)mode;

// - (NSColor *)colorForKey: (NSString *)theKey  whiledark: (BOOL)mode;

- (void)changeColorValueInDictionary: (NSMutableDictionary *)theDictionary forKey: (NSString *)theKey fromColorWell: (id)theWell;
@end
