//
//  TSColorSupport.m
//  
//
//  Created by Richard Koch on 7/26/2018.
//  Copyright 2018 University of Oregon. All rights reserved.
//

#import "globals.h"
#import "TSColorSupport.h"
#import "TSThemeFileStore.h"

@implementation TSColorSupport

// Pointer to the TSColorSupport singleton
static id sharedColorSupport = nil;



+ (id)sharedInstance
{
    if (sharedColorSupport == nil) {
        sharedColorSupport = [[TSColorSupport alloc] init];
    }
    return sharedColorSupport;
}

// A user might remove ALL color styles from Library/TeXShop/Colors
// The routine below checks whether LiteTheme.plist and DarkTheme.plist exist in this directory
// If not, it restores them with default files
- (void)checkAndRestoreDefaults;
{
    NSString *reserveLitePath, *reserveDarkPath;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *newColorPath = [ColorPath stringByExpandingTildeInPath];
    NSString* liteColorPath = [[newColorPath stringByAppendingString:@"/"] stringByAppendingString: @"LiteTheme.plist"];
    NSString* darkColorPath = [[newColorPath stringByAppendingString:@"/"] stringByAppendingString: @"DarkTheme.plist"];
    
    if (! [fileManager fileExistsAtPath: liteColorPath])
    {
        reserveLitePath = [[NSBundle mainBundle] pathForResource:@"LiteTheme" ofType:@"plist" inDirectory:@"Themes"];
        [fileManager copyItemAtPath: reserveLitePath toPath: liteColorPath error: nil];
    }
    if (! [fileManager fileExistsAtPath: darkColorPath])
    {
        reserveDarkPath = [[NSBundle mainBundle] pathForResource:@"DarkTheme" ofType:@"plist" inDirectory:@"Themes"];
        [fileManager copyItemAtPath: reserveDarkPath toPath: darkColorPath error: nil];
    }
}

// Colors of the bundled themes that a later version changed, because text could not be read in them or on them.
// The themes in ~/Library/TeXShop/Themes are copies made when that folder was created, so each copy is given the new
// color where it still has the color that TeXShop gave it. A color the user chose, a renamed copy and a theme of the
// user's own stay as they are. Each change belongs to an update; the last update done is kept in the settings.
typedef struct {
    NSInteger update;
    __unsafe_unretained NSString *theme;
    __unsafe_unretained NSString *key;
    double from[3];
    double to[3];
} TSBundledThemeColorChange;

static const TSBundledThemeColorChange TSBundledThemeColorChanges[] = {
    // 6.00: the content of braces, the active line and the text found by SyncTeX are painted behind the text, which
    // must stay readable on them; brackets, markers, index entries, XML and the commands of Manteuffel are made
    // readable on the background of their themes.
    {1, @"DarkTheme", @"EditorHighlightContent", {0.4756349325, 0.4756467342, 0.4756404161}, {0.270588, 0.25098, 0.176471}},
    {1, @"DarkTheme", @"EntryColor", {0.6386525630950928, 0.1230164617300034, 0.1503929197788239}, {0.258824, 0.258824, 0.258824}},
    {1, @"DarkTheme", @"XMLSpecial", {0.0, 0.3, 1.0}, {0.431373, 0.607843, 1.0}},
    {1, @"Dracula", @"EditorHighlightContent", {0.4756349325, 0.4756467342, 0.4756404161}, {0.25098, 0.243137, 0.172549}},
    {1, @"Dracula", @"EditorReverseSync", {0.9872317910194397, 0.2329826056957245, 0.2662559449672699}, {0.478431, 0.14902, 0.2}},
    {1, @"Dracula", @"EntryColor", {1.0, 0.0, 0.0630970448255539}, {0.180392, 0.188235, 0.243137}},
    {1, @"Dracula", @"SyntaxMarkerCurly", {0.0, 0.0, 0.0}, {0.9725490196078431, 0.9725490196078431, 0.9490196078431372}},
    {1, @"Dracula", @"SyntaxMarkerParen", {0.0, 0.0, 0.0}, {0.9725490196078431, 0.9725490196078431, 0.9490196078431372}},
    {1, @"Dracula", @"SyntaxMarkerSquare", {0.0, 0.0, 0.0}, {0.9725490196078431, 0.9725490196078431, 0.9490196078431372}},
    {1, @"Dracula", @"XMLSpecial", {0.0, 0.3, 1.0}, {0.431373, 0.607843, 1.0}},
    {1, @"GLG-Lite", @"EditorReverseSync", {0.2000000029802322, 0.6000000238418579, 0.9900000095367432}, {0.74902, 0.866667, 0.988235}},
    {1, @"GLG-Lite", @"SyntaxIndex", {1.0, 1.0, 0.0}, {0.541176, 0.427451, 0.0}},
    {1, @"GLG-Lite", @"XMLParameter", {0.0, 1.0, 0.0}, {0.0, 0.541176, 0.0}},
    {1, @"GLG-Lite", @"XMLValue", {0.6, 0.6, 0.2}, {0.478431, 0.478431, 0.121569}},
    {1, @"LiteTheme", @"EditorHighlightContent", {0.8946298956871033, 0.241200892533709, 0.2138740761137153}, {1.0, 0.956863, 0.768627}},
    {1, @"LiteTheme", @"SyntaxIndex", {1.0, 0.9932006001472473, 0.0}, {0.541176, 0.427451, 0.0}},
    {1, @"LiteTheme", @"XMLParameter", {0.0, 1.0, 0.0}, {0.0, 0.541176, 0.0}},
    {1, @"LiteTheme", @"XMLValue", {0.6, 0.6, 0.2}, {0.478431, 0.478431, 0.121569}},
    {1, @"Manteuffel", @"SyntaxCommand", {0.08235294371843338, 0.7098039388656616, 0.9137254953384399}, {0.043137, 0.52549, 0.701961}},
    {1, @"Manteuffel", @"SyntaxIndex", {1.0, 1.0, 0.0}, {0.541176, 0.427451, 0.0}},
    {1, @"Manteuffel", @"XMLParameter", {0.0, 1.0, 0.0}, {0.0, 0.541176, 0.0}},
    {1, @"Manteuffel", @"XMLValue", {0.6, 0.6, 0.2}, {0.478431, 0.478431, 0.121569}},
    {1, @"PreTeXt-Dark", @"EditorHighlightContent", {0.4756349325, 0.4756467342, 0.4756404161}, {0.239216, 0.227451, 0.156863}},
    {1, @"PreTeXt-Dark", @"EntryColor", {1.0, 0.0, 0.0}, {0.188235, 0.192157, 0.164706}},
    {1, @"PreTeXt-Dark", @"XMLSpecial", {0.0, 0.3, 1.0}, {0.431373, 0.607843, 1.0}},
    {1, @"SolarizedDark", @"EditorHighlightContent", {1.0, 1.0, 0.0}, {0.2, 0.188235, 0.039216}},
    {1, @"SolarizedDark", @"EditorReverseSync", {1.0, 1.0, 0.0}, {0.352941, 0.121569, 0.105882}},
    {1, @"SolarizedDark", @"EntryColor", {1.0, 0.0, 0.07932668179273605}, {0.027451, 0.211765, 0.258824}},
    {1, @"SolarizedDark", @"XMLSpecial", {0.0, 0.3, 1.0}, {0.431373, 0.607843, 1.0}},
    {1, @"SolarizedLite", @"SyntaxMarker", {0.1650000065565109, 0.6299999952316284, 0.5960000157356262}, {0.8299999833106995, 0.2099999934434891, 0.5099999904632568}},
    {1, @"SolarizedLite", @"XMLParameter", {0.0, 1.0, 0.0}, {0.0, 0.541176, 0.0}},
    {1, @"SolarizedLite", @"XMLValue", {0.6, 0.6, 0.2}, {0.478431, 0.478431, 0.121569}},
    {1, @"TransparentTheme", @"EditorHighlightContent", {0.9816838723753915, 0.3395324724758731, 0.1522207877986456}, {1.0, 0.956863, 0.768627}},
    {1, @"TransparentTheme", @"SyntaxIndex", {1.0, 1.0, 0.0}, {0.541176, 0.427451, 0.0}},
    {1, @"TransparentTheme", @"SyntaxMarker", {1.0, 0.9703128892638841, 0.2354147580939638}, {0.5, 0.4, 0.0}},
    {1, @"TransparentTheme", @"XMLParameter", {0.0, 1.0, 0.0}, {0.0, 0.541176, 0.0}},
    {1, @"TransparentTheme", @"XMLValue", {0.6, 0.6, 0.2}, {0.478431, 0.478431, 0.121569}},
};

// Gives the colors of the updates after the given one to a copy of a bundled theme, where it still has the old color.
static BOOL TSApplyBundledThemeColorChanges(NSMutableDictionary *colors, NSString *theme, NSInteger update)
{
    const size_t count = sizeof(TSBundledThemeColorChanges) / sizeof(TSBundledThemeColorChanges[0]);
    BOOL changed = NO;
    for (size_t i = 0; i < count; i++) {
        const TSBundledThemeColorChange *change = &TSBundledThemeColorChanges[i];
        if (change->update <= update || ![change->theme isEqualToString:theme])
            continue;
        NSMutableArray *color = colors[change->key];
        if (![color isKindOfClass:NSMutableArray.class] || color.count < 3)
            continue;
        BOOL unchanged = YES;
        for (NSUInteger c = 0; c < 3; c++)
            unchanged = unchanged && [color[c] isKindOfClass:NSNumber.class] && fabs([color[c] doubleValue] - change->from[c]) < 0.0005;
        if (!unchanged)
            continue;
        // The opacity, if any, stays.
        for (NSUInteger c = 0; c < 3; c++)
            color[c] = @(change->to[c]);
        changed = YES;
    }
    return changed;
}

// Updates one theme file; NO if it exists but could not be read or written. Another TeXShop may save the theme at the
// same time: the file is coordinated with the theme saves of this version, and it is replaced only if it still holds
// what was read; otherwise it is read again, so that a color saved meanwhile is kept.
static BOOL TSUpdateBundledThemeFile(NSURL *url, NSString *theme, NSInteger update)
{
    __block BOOL done = NO;
    NSError *coordinationError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForMerging error:&coordinationError byAccessor:^(NSURL *fileURL) {
        for (NSUInteger attempt = 0; attempt < 5; attempt++) {
            NSData *data = [NSData dataWithContentsOfURL:fileURL];
            NSMutableDictionary *colors = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:NULL] : nil;
            if (![colors isKindOfClass:NSMutableDictionary.class])
                return;
            if (!TSApplyBundledThemeColorChanges(colors, theme, update)) {
                done = YES;
                return;
            }
            NSData *updated = [NSPropertyListSerialization dataWithPropertyList:colors format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
            if (updated == nil)
                return;
            if (![[NSData dataWithContentsOfURL:fileURL] isEqualToData:data])
                continue;
            done = [updated writeToURL:fileURL options:NSDataWritingAtomic error:NULL];
            return;
        }
    }];
    return done;
}

// Returns the last update done: every update after the given one, or the given one if a theme that is there could not
// be read or written, so that the update is tried again at the next launch.
- (NSInteger)updateBundledThemeColorsInDirectory: (NSURL *)directory after: (NSInteger)update
{
    const size_t count = sizeof(TSBundledThemeColorChanges) / sizeof(TSBundledThemeColorChanges[0]);
    NSInteger last = update;
    for (size_t i = 0; i < count; i++)
        last = MAX(last, TSBundledThemeColorChanges[i].update);
    if (last == update)
        return update;

    TSThemeFileStore *store = [[TSThemeFileStore alloc] initWithDirectory:directory];
    NSMutableOrderedSet<NSString *> *themes = [NSMutableOrderedSet orderedSet];
    for (size_t i = 0; i < count; i++)
        if (TSBundledThemeColorChanges[i].update > update)
            [themes addObject:TSBundledThemeColorChanges[i].theme];
    BOOL written = YES;
    for (NSString *theme in themes) {
        // A theme that is not there, or is reached through a symbolic link, is left alone.
        NSURL *url = [store URLForTitle:theme];
        if (url == nil || ![[NSFileManager defaultManager] fileExistsAtPath:url.path])
            continue;
        if (!TSUpdateBundledThemeFile(url, theme, update))
            written = NO;
    }
    return written ? last : update;
}

- (void)updateBundledThemeColors
{
    NSInteger update = [SUD integerForKey:BundledThemeColorsUpdateKey];
    NSURL *directory = [NSURL fileURLWithPath:[ColorPath stringByExpandingTildeInPath] isDirectory:YES];
    NSInteger done = [self updateBundledThemeColorsInDirectory:directory after:update];
    if (done != update)
        [SUD setInteger:done forKey:BundledThemeColorsUpdateKey];
}

// This routine sets the Lite and Dark color dictionaries. It also checks to make sure the default color plist exists.
// If not, it switches to LiteColors and/or DarkColors and changes the default values for these items.

- (void)initializeColors
{
    
    NSString *lite = [SUD stringForKey: DefaultLiteThemeKey];
    NSString *dark = [SUD stringForKey: DefaultDarkThemeKey];
    
    NSString *newColorPath = [ColorPath stringByExpandingTildeInPath];
    NSString* liteThemePath = [[[newColorPath stringByAppendingString:@"/"] stringByAppendingString: lite] stringByAppendingString: @".plist"];
    NSString* darkThemePath = [[[newColorPath stringByAppendingString:@"/"] stringByAppendingString: dark] stringByAppendingString: @".plist"];
    NSString* defaultLiteThemePath = [[newColorPath stringByAppendingString:@"/"] stringByAppendingString: @"LiteTheme.plist"];
    NSString* defaultDarkThemePath = [[newColorPath stringByAppendingString:@"/"] stringByAppendingString: @"DarkTheme.plist"];
    
    
    [self checkAndRestoreDefaults];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (! [fileManager fileExistsAtPath: liteThemePath])
    {
        [SUD setObject: @"LiteTheme" forKey: DefaultLiteThemeKey];
        liteThemePath = defaultLiteThemePath;
    }
    if (! [fileManager fileExistsAtPath: darkThemePath])
    {
        [SUD setObject: @"DarkTheme" forKey: DefaultDarkThemeKey];
        darkThemePath = defaultDarkThemePath;
    }
    
    liteColors = [NSDictionary dictionaryWithContentsOfFile:liteThemePath];
    darkColors = [NSDictionary dictionaryWithContentsOfFile:darkThemePath];
}

- (NSMutableDictionary *) dictionaryForColorFile: (NSString *) fileTitle
{
    
    NSString *newColorPath = [ColorPath stringByExpandingTildeInPath];
    NSString *colorFilePath = [[[newColorPath stringByAppendingString:@"/"] stringByAppendingString: fileTitle] stringByAppendingString: @".plist"];
    return [NSMutableDictionary dictionaryWithContentsOfFile:colorFilePath];
}


// Themes made before brackets had their own colors only define SyntaxMarker.
- (NSArray *) colorArrayFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey
{
    NSArray *theColorArray = [theDictionary objectForKey: theKey];
    if ((theColorArray == nil) &&
        ([theKey isEqualToString: @"SyntaxMarkerParen"] ||
         [theKey isEqualToString: @"SyntaxMarkerCurly"] ||
         [theKey isEqualToString: @"SyntaxMarkerSquare"]))
        theColorArray = [theDictionary objectForKey: @"SyntaxMarker"];
    return theColorArray;
}

- (NSColor *) colorFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey
{
    NSArray *theColorArray = [self colorArrayFromDictionary: theDictionary andKey: theKey];
    if (theColorArray == nil)
        return nil;
    NSColor *theColor = [NSColor colorWithRed: [theColorArray[0] doubleValue]  green: [theColorArray[1] doubleValue]  blue: [theColorArray[2] doubleValue]  alpha:1.00];
    
    return theColor;
}


- (NSColor *) colorAndAlphaFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey
{
    NSArray *theColorArray = [theDictionary objectForKey: theKey];
    if (theColorArray == nil)
        return nil;
    NSColor *theColor = [NSColor colorWithRed: [theColorArray[0] doubleValue]  green: [theColorArray[1] doubleValue]  blue: [theColorArray[2] doubleValue]  alpha: [theColorArray[3] doubleValue]];
    
    return theColor;
}

// When colors are added later, dictionaries may not have them; the four calls below give default values until the user selects new
// colors for these keys and consequentlycolor adds entries to dictionaries

- (NSColor *)liteColorWithKey: (NSString *)theKey
{
    if ([theKey isEqualToString: @"EditorFlash"])
        return [NSColor colorWithRed: 1 green: 0.95 blue: 1 alpha:1.00];
    else if ([theKey isEqualToString: @"FootnoteColor"]) //not actually used
        return [NSColor colorWithRed: 0.35  green: 0.35  blue: 0.35 alpha:1.00];
    else if ([theKey isEqualToString: @"EntryColor"])
        return [NSColor colorWithRed: 0.9  green: 0.99  blue: 0.99 alpha:1.00];

    else if ([theKey isEqualToString: @"XMLComment"])
            return [NSColor colorWithRed: 0.50  green: 0.50  blue: 0.50 alpha:1.00];
        else if ([theKey isEqualToString: @"XMLTag"])
            return [NSColor colorWithRed: 1.00  green: 0.00  blue: 0.20 alpha:1.00];
        else if ([theKey isEqualToString: @"XMLSpecial"])
            return [NSColor colorWithRed: 0.00  green: 0.30  blue: 1.00 alpha:1.00];
        else if ([theKey isEqualToString: @"XMLParameter"])
            return [NSColor colorWithRed: 0.00  green: 1.00  blue: 0.00 alpha:1.00];
        else if ([theKey isEqualToString: @"XMLValue"])
            return [NSColor colorWithRed: 0.60  green: 0.60  blue: 0.20 alpha:1.00];
    
    /*
    myColor1 = [NSColor colorWithRed: 1.0 green: 0.0 blue: 1.0 alpha: 1.00];
    self.explColorAttribute1 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor1, NSForegroundColorAttributeName, nil];
    myColor2 = [NSColor colorWithRed: .2 green: 0.5 blue: 0.5 alpha: 1.00];
    self.explColorAttribute2 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor2, NSForegroundColorAttributeName, nil];
    myColor3 = [NSColor colorWithRed: .5 green: 0.5 blue: .5 alpha: 1.00];
    self.explColorAttribute3 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor3, NSForegroundColorAttributeName, nil];
    myColor4 = [NSColor colorWithRed: .8 green: 0.8 blue: 0.1 alpha: 1.00];
    self.explColorAttribute4 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor4, NSForegroundColorAttributeName,nil];
    myColor5 = [NSColor colorWithRed: 1.0 green: 1.0 blue: 0.0 alpha: 1.00];
    self.explColorAttribute5 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor5, NSForegroundColorAttributeName,nil];
    myColor6 = [NSColor colorWithRed: 0.0 green: 1.0 blue: 1.0 alpha: 1.00];
    self.explColorAttribute6 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor6, NSForegroundColorAttributeName,nil];
    myColor7 = [NSColor colorWithRed: 0.7 green: 0.0 blue: 0.7 alpha: 1.00];
    self.explColorAttribute7 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor7, NSForegroundColorAttributeName,nil];
    */
    
        else if ([theKey isEqualToString: @"explFunction"])
            return [NSColor colorWithRed: .00 green: 0.10 blue: 0.57 alpha: 1.00];
        else if ([theKey isEqualToString: @"explVariable"])
            return [NSColor colorWithRed: .31 green: 0.56 blue: .00 alpha: 1.00];
        else if ([theKey isEqualToString: @"explIntenseFunction"])
            return [NSColor colorWithRed: .58 green: 0.32 blue: 0.00 alpha: 1.00];
        else if ([theKey isEqualToString: @"explIntenseVariable"])
            return [NSColor colorWithRed: .37 green: 0.37 blue: .37 alpha: 1.00];
        else if ([theKey isEqualToString: @"explmykey"])
            return [NSColor colorWithRed: .58 green: .21 blue: 1.0 alpha: 1.00];
        else if ([theKey isEqualToString: @"explmykeyArgument"])
            return [NSColor colorWithRed: 0.85 green: 0.29 blue: 0.36 alpha: 1.00];
        else if ([theKey isEqualToString: @"explmsg"])
            return [NSColor colorWithRed: .00 green: .57 blue: .57 alpha: 1.00];
  
    
        else if ([theKey isEqualToString: @"SyntaxMarkerParen"])
            return [NSColor colorWithRed: .02 green: .51 blue: .13 alpha: 1.00];
        else if ([theKey isEqualToString: @"SyntaxMarkerCurly"])
            return [NSColor colorWithRed: .02 green: .51 blue: .13 alpha: 1.00];
        else if ([theKey isEqualToString: @"SyntaxMarkerSquare"])
            return [NSColor colorWithRed: .02 green: .51 blue: .13 alpha: 1.00];
    
    
    else
        return [NSColor colorWithRed: 1.00  green: 1.00 blue: 1.00 alpha:1.00];
}

- (NSColor *)darkColorWithKey: (NSString *)theKey
{
    if ([theKey isEqualToString: @"EditorFlash"])
        return [NSColor colorWithRed: 0.00 green: 0.20  blue: 0.20 alpha:1.00];
    else if ([theKey isEqualToString: @"FootnoteColor"]) //not actually used
        return [NSColor colorWithRed: 0.75 green: 0.75 blue: 0.75 alpha:1.00];
    else if ([theKey isEqualToString: @"EntryColor"])
        return [NSColor colorWithRed: 0.1 green: 0.01 blue: 0.01 alpha:1.00];
    
    else if ([theKey isEqualToString: @"XMLComment"]) //not actually used
        return [NSColor colorWithRed: 0.50  green: 0.50  blue: 0.50 alpha:1.00];
    else if ([theKey isEqualToString: @"XMLTag"]) //not actually used
        return [NSColor colorWithRed: 1.00  green: 0.00  blue: 0.20 alpha:1.00];
    else if ([theKey isEqualToString: @"XMLSpecial"]) //not actually used
        return [NSColor colorWithRed: 0.00  green: 0.30  blue: 1.00 alpha:1.00];
    else if ([theKey isEqualToString: @"XMLParameter"]) //not actually used
        return [NSColor colorWithRed: 0.00  green: 1.00  blue: 0.00 alpha:1.00];
    else if ([theKey isEqualToString: @"XMLValue"]) //not actually used
        return [NSColor colorWithRed: 0.60  green: 0.60  blue: 0.20 alpha:1.00];
    
    else if ([theKey isEqualToString: @"explFunction"])
        return [NSColor colorWithRed: .57 green: 0.57 blue: 0.00 alpha: 1.00];
    else if ([theKey isEqualToString: @"explVariable"])
        return [NSColor colorWithRed: .31 green: 0.56 blue: .00 alpha: 1.00];
    else if ([theKey isEqualToString: @"explIntenseFunction"])
        return [NSColor colorWithRed: 1.00 green: 0.58 blue: 0.00 alpha: 1.00];
    else if ([theKey isEqualToString: @"explIntenseVariable"])
        return [NSColor colorWithRed: .66 green: 0.66 blue: .66 alpha: 1.00];
    else if ([theKey isEqualToString: @"explmykey"])
        return [NSColor colorWithRed: .58 green: .21 blue: 1.0 alpha: 1.00];
    else if ([theKey isEqualToString: @"explmykeyArgument"])
        return [NSColor colorWithRed: 0.85 green: 0.29 blue: 0.36 alpha: 1.00];
    else if ([theKey isEqualToString: @"explmsg"])
        return [NSColor colorWithRed: .00 green: .57 blue: .57 alpha: 1.00];
    
    
    else if ([theKey isEqualToString: @"SyntaxMarkerParen"])
        return [NSColor colorWithRed: 0.96766179800033569 green: 0.57783806324005127 blue: 0.9108852744102478 alpha: 1.00];
    else if ([theKey isEqualToString: @"SyntaxMarkerCurly"])
        return [NSColor colorWithRed: 0.96766179800033569 green: 0.57783806324005127 blue: 0.9108852744102478 alpha: 1.00];
    else if ([theKey isEqualToString: @"SyntaxMarkerSquare"])
        return [NSColor colorWithRed: 0.96766179800033569 green: 0.57783806324005127 blue: 0.9108852744102478 alpha: 1.00];
    
    else
        return [NSColor colorWithRed: 0.00  green: 0.00 blue: 0.00 alpha:1.00];
}


- (NSColor *)liteColorAndAlphaWithKey: (NSString *)theKey
{
    return [self liteColorWithKey: theKey];
}

- (NSColor *)darkColorAndAlphaWithKey: (NSString *)theKey
{
      return [self darkColorWithKey: theKey];
}

// Resolves a color from any theme dictionary, falling back to the built-in default for the given mode.
- (NSColor *)colorForKey: (NSString *)theKey fromDictionary: (NSDictionary *)theDictionary isWindowDark: (BOOL)mode
{
    NSColor *theColor;
    
    NSArray *theColorArray = [self colorArrayFromDictionary: theDictionary andKey: theKey];
    if (theColorArray != nil)
        {
            theColor = [NSColor colorWithRed: [theColorArray[0] doubleValue]  green: [theColorArray[1] doubleValue]  blue: [theColorArray[2] doubleValue]  alpha: [theColorArray[3] doubleValue]];
            return (theColor);
        }
    if (mode)
        return [self darkColorWithKey: theKey];
    else
        return [self liteColorWithKey: theKey];
}

// Themes store an opacity of 0 with some of these colors, for example the editor
// background of SolarizedDark, which -colorFromDictionary:andKey: ignores.
- (NSColor *)opaqueColorForKey: (NSString *)theKey fromDictionary: (NSDictionary *)theDictionary isWindowDark: (BOOL)mode
{
    NSColor *theColor = [self colorFromDictionary: theDictionary andKey: theKey];
    if (theColor != nil)
        return theColor;
    if (mode)
        return [self darkColorWithKey: theKey];
    else
        return [self liteColorWithKey: theKey];
}

- (NSColor *)colorForKey: (NSString *)theKey isWindowDark: (BOOL)mode
{
    NSDictionary *theDictionary;
    
    if (mode)
        theDictionary = darkColors;
     else
         theDictionary = liteColors;
    
    return [self colorForKey: theKey fromDictionary: theDictionary isWindowDark: mode];
}



- (void)changeColorValueInDictionary: (NSMutableDictionary *)theDictionary forKey: (NSString *)theKey fromColorWell: (id)theWell
{
    CGFloat aRed, aGreen, aBlue, anAlpha;
    NSNumber *redNumber, *greenNumber, *blueNumber, *alphaNumber;
    
    NSColor *theColor = [((NSColorWell *)theWell).color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
    if (theColor == nil) return;
    [theColor getRed: &aRed green: &aGreen blue: &aBlue alpha: &anAlpha];
    redNumber = [NSNumber numberWithDouble: aRed];
    greenNumber = [NSNumber numberWithDouble: aGreen];
    blueNumber = [NSNumber numberWithDouble: aBlue];
    alphaNumber = [NSNumber numberWithDouble: anAlpha];
    NSArray *theArray = @[redNumber, greenNumber, blueNumber, alphaNumber];
    [theDictionary setObject: theArray forKey:theKey];
}

@end
