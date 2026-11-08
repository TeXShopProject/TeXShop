/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2007 Richard Koch
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * $Id: TSPreferences.m 254 2007-06-03 21:09:25Z fingolfin $
 *
 * Created by dirk on Thu Dec 07 2000.
 *
 */

#import "TSPreferences+LiveSettings.h"
#import "globals.h"
#import "TSColorSupport.h"
#import "TSThemeFileStore.h"


@implementation TSPreferences (Color)

NSInteger stringSort(id s1, id s2, void *context)
{
    NSComparisonResult result;
    result =  [(NSString *)s1 localizedCaseInsensitiveCompare: (NSString *)s2];
    return result;
}


- (void)PrepareColorPane:(NSUserDefaults *)defaults;
{
    
    NSArray *contents, *originalContents;
    
  // Fill three menus with names of plist files in ~/Library/TeXShop/Colors
    
    [LiteStyle removeAllItems];
    [DarkStyle removeAllItems];
    [EditingStyle removeAllItems];

    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *filePath = [ColorPath stringByExpandingTildeInPath];
    originalContents= [fileManager contentsOfDirectoryAtPath: filePath error: nil];
    contents = [originalContents sortedArrayUsingFunction: stringSort context: NULL ];
    
    NSUInteger i;
    NSString *theTitle;
    for (i = 0; i < [contents count]; i++)
    {
        if ([[contents[i] pathExtension] isEqualToString: @"plist"])
             {
                 theTitle = [contents[i] stringByDeletingPathExtension];
                 [LiteStyle addItemWithTitle: theTitle];
                 [DarkStyle addItemWithTitle: theTitle];
                 [EditingStyle addItemWithTitle: theTitle];
              }
    }
    NSString *liteTitle = [SUD stringForKey:DefaultLiteThemeKey];
    NSString *darkTitle = [SUD stringForKey:DefaultDarkThemeKey];
    
    // if this file doesn't exist, switch menu to LiteColors
    [LiteStyle selectItemWithTitle: liteTitle];
    [DarkStyle selectItemWithTitle: darkTitle];
    // if this file doesn't exist, switch menu to DarkColors
#ifdef MOJAVEORHIGHER
    if ((atLeastMojave) && (_prefsWindow.effectiveAppearance.name == NSAppearanceNameDarkAqua))
    {
        [EditingStyle selectItemWithTitle:darkTitle];

    }
    else
#endif
    {
        [EditingStyle selectItemWithTitle: liteTitle];

    }
    
    NSString *selected = EditingStyle.titleOfSelectedItem;
    EditingColors = selected == nil ? nil : [[[self themeStore] readTitle:selected] mutableCopy];
    self.lastSavedEditingColors = [EditingColors copy];
    // Fill in all the color wells with the colors of these items
    
    [self FillInColorWells];
    
    
}


// Bracket and expl3 wells show the theme being edited, resolved the way documents resolve it.
- (NSColor *)editingColorForKey: (NSString *)theKey
{
    BOOL withDarkColors;
    
#ifdef MOJAVEORHIGHER
    if ((atLeastMojave) && (_prefsWindow.effectiveAppearance.name == NSAppearanceNameDarkAqua))
        withDarkColors = YES;
    else
#endif
        withDarkColors = NO;
    
    return [[TSColorSupport sharedInstance] colorForKey: theKey fromDictionary: EditingColors isWindowDark: withDarkColors];
}

// Bracket wells without their own color in the edited theme follow SyntaxMarker.
- (void)refreshInheritedBracketColorWells
{
    if ([EditingColors objectForKey: @"SyntaxMarkerParen"] == nil)
        markerParenColorWell.color = [self editingColorForKey: @"SyntaxMarkerParen"];
    if ([EditingColors objectForKey: @"SyntaxMarkerCurly"] == nil)
        markerCurlyColorWell.color = [self editingColorForKey: @"SyntaxMarkerCurly"];
    if ([EditingColors objectForKey: @"SyntaxMarkerSquare"] == nil)
        markerSquareColorWell.color = [self editingColorForKey: @"SyntaxMarkerSquare"];
}

- (void)FillInColorWells
{
    [self setThemeEditingEnabled:(EditingColors != nil) inView:_prefsWindow.contentView];
    if (EditingColors == nil) return;
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    NSColor *flashColor, *aColor;
    NSColor *footnoteCol, *EntryCol;
    BOOL withDarkColors;
    
    
#ifdef MOJAVEORHIGHER
    if ((atLeastMojave) && (_prefsWindow.effectiveAppearance.name == NSAppearanceNameDarkAqua))
        withDarkColors = YES;
    else
#endif
        withDarkColors = NO;

    
    SourceTextColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorText"];
    SourceBackgroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorBackground"];
    SourceInsertionPointColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorInsertionPoint"];
    PreviewBackgroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"PreviewBackground"];
    ConsoleTextColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ConsoleText"];
    ConsoleBackgroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ConsoleBackground"];
    LogTextColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"LogText"];
    LogBackgroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"LogBackground"];
    SyntaxCommentColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxComment"];
    SyntaxCommandColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxCommand"];
    SyntaxMarkerColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxMarker"];
    SyntaxIndexColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxIndex"];
    
    //markerParenColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxMarkerParen"];
    //markerCurlyColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxMarkerCurly"];
    //markerSquareColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxMarkerSquare"];
    markerParenColorWell.color = [self editingColorForKey: @"SyntaxMarkerParen"];
    markerCurlyColorWell.color = [self editingColorForKey: @"SyntaxMarkerCurly"];
    markerSquareColorWell.color = [self editingColorForKey: @"SyntaxMarkerSquare"];
    
    
        
    explFunctionColorWell.color = [self editingColorForKey: @"explFunction"];
    explVariableColorWell.color = [self editingColorForKey: @"explVariable"];
    explIntenseFunctionColorWell.color = [self editingColorForKey: @"explIntenseFunction"];
    explIntenseVariableColorWell.color = [self editingColorForKey: @"explIntenseVariable"];
    explmykeyColorWell.color = [self editingColorForKey: @"explmykey"];
    explmykeyArgumentColorWell.color = [self editingColorForKey: @"explmykeyArgument"];
    explmsgColorWell.color = [self editingColorForKey: @"explmsg"];
   
    
    EditorHighlightBracesColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorHighlightBraces"];
    EditorHighlightContentColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorHighlightContent"];
    EditorInvisibleCharColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorInvisibleChar"];
    flashColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorFlash"];
    if (flashColor != nil)
        EditorFlashColorWell.color = flashColor;
    else if (withDarkColors)
        // EditorFlashColorWell.color = [NSColor colorWithRed:0.00 green:0.20 blue:0.20 alpha:1.00];
        EditorFlashColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"EditorFlash"];
    else
        // EditorFlashColorWell.color = [NSColor colorWithRed:1 green:0.95 blue:1 alpha:1];
        EditorFlashColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"EditorFlash"];
    
    footnoteCol = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"FootnoteColor"];
    if (footnoteCol == nil)
        footnoteCol = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxCommand"];
    FootnoteColorWell.color = footnoteCol;
/*
    else if (withDarkColors)
        // FootnoteColorWell.color = [NSColor colorWithRed:0.75 green:0.75 blue:0.75 alpha:1.00];
        FootnoteColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"FootnoteColor"];
    else
        // FootnoteColorWell.color = [NSColor colorWithRed:0.35 green:0.35 blue:0.35 alpha:1];
        FootnoteColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"FootnoteColor"];
 */
    
   EntryCol = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EntryColor"];
    if (EntryCol != nil)
        EntryColorWell.color = EntryCol;
    else
        EntryColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"EntryColor"];

        
    EditorReverseSyncColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorReverseSync"];
    PreviewDirectSyncColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"PreviewDirectSync"];
    SourceAlphaColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SourceAlpha"];
    PreviewAlphaColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"PreviewAlpha"];
    ConsoleAlphaColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ConsoleAlpha"];
    ImageForegroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ImageForeground"];
    ImageBackgroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ImageBackground"];
    
    aColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"XMLComment"];
    if (aColor != nil)
        XMLCommentColorWell.color = aColor;
    else if (withDarkColors)
        XMLCommentColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"XMLComment"];
    else
        XMLCommentColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"XMLComment"];
    
    aColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"XMLTag"];
    if (aColor != nil)
        XMLTagColorWell.color = aColor;
    else if (withDarkColors)
        XMLTagColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"XMLTag"];
    else
        XMLTagColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"XMLTag"];
    
    aColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"XMLSpecial"];
    if (aColor != nil)
        XMLSpecialColorWell.color = aColor;
    else if (withDarkColors)
        XMLSpecialColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"XMLSpecial"];
    else
        XMLSpecialColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"XMLSpecial"];
    
    aColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"XMLParameter"];
    if (aColor != nil)
        XMLParameterColorWell.color = aColor;
    else if (withDarkColors)
        XMLParameterColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"XMLParameter"];
    else
        XMLParameterColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"XMLParameter"];
    
    aColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"XMLValue"];
    if (aColor != nil)
        XMLValueColorWell.color = aColor;
    else if (withDarkColors)
        XMLValueColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"XMLValue"];
    else
        XMLValueColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"XMLValue"];
       
    
}

- (IBAction)EditingStyleChoice:(id)sender
{
    NSString *title = EditingStyle.titleOfSelectedItem;
    if (title == nil) return;
    NSDictionary<NSString *, id> *saved = [[self themeStore] readTitle:title];
    EditingColors = [saved mutableCopy];
    self.lastSavedEditingColors = saved;
    [self FillInColorWells];
}

- (IBAction)SaveEditedStyle:(id)sender
{
    NSString *title = EditingStyle.titleOfSelectedItem;
    if (title == nil || EditingColors == nil || self.lastSavedEditingColors == nil) return;
    NSError *error = nil;
    if (![[self themeStore] writeColors:EditingColors title:title error:&error]) {
        NSDictionary<NSString *, id> *saved = [[self themeStore] readTitle:title] ?: self.lastSavedEditingColors;
        EditingColors = [saved mutableCopy];
        self.lastSavedEditingColors = saved;
        [self FillInColorWells];
        [self showPreferenceError:NSLocalizedString(@"The theme could not be saved. Its last saved colors have been restored.", @"")];
        return;
    }
    self.lastSavedEditingColors = [EditingColors copy];
    [[TSColorSupport sharedInstance] initializeColors];
    [NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:self];
}

- (IBAction)NewStyleFromPrefs:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    NSMutableDictionary *prefsDictionary = [NSMutableDictionary dictionaryWithCapacity:19];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorText" withRed: [SUD doubleForKey:foreground_RKey]
                                          Green: [SUD doubleForKey:foreground_GKey] Blue: [SUD doubleForKey:foreground_BKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorBackground" withRed: [SUD doubleForKey:background_RKey]
                                      Green: [SUD doubleForKey:background_GKey] Blue: [SUD doubleForKey:background_BKey] Alpha: [SUD doubleForKey:backgroundAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"LogText" withRed: [SUD doubleForKey:foreground_RKey]
                                      Green: [SUD doubleForKey:foreground_GKey] Blue: [SUD doubleForKey:foreground_BKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"LogBackground" withRed: [SUD doubleForKey:background_RKey]
                                      Green: [SUD doubleForKey:background_GKey] Blue: [SUD doubleForKey:background_BKey] Alpha: [SUD doubleForKey:backgroundAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"ConsoleText" withRed: [SUD doubleForKey:ConsoleForegroundColor_RKey]
                                      Green: [SUD doubleForKey:ConsoleForegroundColor_GKey] Blue: [SUD doubleForKey:ConsoleForegroundColor_BKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"ConsoleBackground" withRed: [SUD doubleForKey:ConsoleBackgroundColor_RKey]
                                      Green: [SUD doubleForKey:ConsoleBackgroundColor_GKey] Blue: [SUD doubleForKey:ConsoleBackgroundColor_BKey] Alpha: [SUD doubleForKey:ConsoleBackgroundAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorInsertionPoint" withRed: [SUD doubleForKey:insertionpoint_RKey]
                                      Green: [SUD doubleForKey:insertionpoint_GKey] Blue: [SUD doubleForKey:insertionpoint_BKey] Alpha: 1.0];
    
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"SyntaxComment" withRed: [SUD doubleForKey:commentredKey]
                                      Green: [SUD doubleForKey:commentgreenKey] Blue: [SUD doubleForKey:commentblueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"SyntaxCommand" withRed: [SUD doubleForKey:commandredKey]
                                      Green: [SUD doubleForKey:commandgreenKey] Blue: [SUD doubleForKey:commandblueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"SyntaxMarker" withRed: [SUD doubleForKey:markerredKey]
                                      Green: [SUD doubleForKey:markergreenKey] Blue: [SUD doubleForKey:markerblueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"SyntaxIndex" withRed: [SUD doubleForKey:indexredKey]
                                      Green: [SUD doubleForKey:indexgreenKey] Blue: [SUD doubleForKey:indexblueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"FootnoteColor" withRed: 0.35
                                      Green: 0.35 Blue: 0.35 Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EntryColor" withRed: 0.9
                                      Green: 0.99 Blue: 0.99 Alpha: 1.0];
    
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorHighlightBraces" withRed: [SUD doubleForKey:highlightBracesRedKey]
                                      Green: [SUD doubleForKey:highlightBracesGreenKey] Blue: [SUD doubleForKey:highlightBracesBlueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorHighlightContent" withRed: [SUD doubleForKey:highlightContentRedKey]
                                      Green: [SUD doubleForKey:highlightContentGreenKey] Blue: [SUD doubleForKey:highlightContentBlueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorInvisibleChar" withRed: [SUD doubleForKey:invisibleCharRedKey]
                                      Green: [SUD doubleForKey:invisibleCharGreenKey] Blue: [SUD doubleForKey:invisibleCharBlueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorFlash" withRed: 1.0 Green: 0.95 Blue: 1.0 Alpha:1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorReverseSync" withRed: [SUD doubleForKey:reverseSyncRedKey]
                                      Green: [SUD doubleForKey:reverseSyncGreenKey] Blue: [SUD doubleForKey:reverseSyncBlueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"PreviewDirectSync" withRed: 1.0 Green: 1.0 Blue: 0.0 Alpha: 1.0];
    
    
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"PreviewBackground" withRed: [SUD doubleForKey:PdfPageBack_RKey]
                                      Green: [SUD doubleForKey:PdfPageBack_GKey] Blue: [SUD doubleForKey:PdfPageBack_BKey] Alpha: 1.0];
    
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"SourceAlpha" withRed: 1.0
                                      Green: 1.0 Blue: 1.0 Alpha: [SUD doubleForKey: SourceWindowAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"PreviewAlpha" withRed: 1.0
                                      Green: 1.0  Blue: 2.0 Alpha: [SUD doubleForKey: PreviewWindowAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"ConsoleAlpha" withRed: 1.0
                                      Green: 1.0 Blue: 1.0 Alpha: [SUD doubleForKey: ConsoleWindowAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"ImageForeground" withRed: [SUD doubleForKey:PdfFore_RKey]
                                      Green: [SUD doubleForKey:PdfFore_GKey] Blue: [SUD doubleForKey:PdfFore_BKey]
                                      Alpha: [SUD doubleForKey:PdfFore_AKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"ImageBackground" withRed: [SUD doubleForKey:PdfBack_RKey]
                                      Green: [SUD doubleForKey:PdfBack_GKey] Blue: [SUD doubleForKey:PdfBack_BKey]
                                      Alpha: [SUD doubleForKey:PdfBack_AKey]];
    
    
    [self requestNameForThemeColors:prefsDictionary];

}



- (IBAction)SaveNewStyle:sender
{
    if (self.lastSavedEditingColors == nil) {
        [self showPreferenceError:NSLocalizedString(@"Reopen Settings or select a readable theme before editing or duplicating it.", @"")];
        return;
    }
    [self requestNameForThemeColors:self.lastSavedEditingColors];
}

- (void)requestNameForThemeColors:(NSDictionary<NSString *, id> *)colors
{
    if (_prefsWindow == nil || stylePanel == nil || _prefsWindow.attachedSheet != nil) return;
    NSUInteger generation = ++self.themeOperationGeneration;
    NSDictionary<NSString *, id> *snapshot = [colors copy];
    styleTitle.stringValue = @"";
    [stylePanel setContentSize:NSMakeSize(420, stylePanel.contentView.fittingSize.height)];
    __weak __typeof(self) weakSelf = self;
    [_prefsWindow beginSheet:stylePanel completionHandler:^(NSModalResponse response) {
        __strong __typeof(weakSelf) coordinator = weakSelf;
        if (coordinator == nil) return;
        if (response != NSModalResponseOK || generation != coordinator.themeOperationGeneration) return;
        NSString *title = [coordinator->styleTitle.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (title.length == 0) return;
        NSURL *url = [[coordinator themeStore] URLForTitle:title];
        NSString *path = url.path;
        if (path == nil) {
            [coordinator showPreferenceError:NSLocalizedString(@"Choose another theme name. Names beginning with a dot, path separators, control characters, and symbolic links are not allowed.", @"")];
            return;
        }
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
            [coordinator saveNewTheme:snapshot title:title];
            return;
        }
        NSAlert *alert = [NSAlert new];
        alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"The theme “%@” already exists. Replace it?", @""), title];
        [alert addButtonWithTitle:NSLocalizedString(@"Replace", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
        [alert beginSheetModalForWindow:coordinator->_prefsWindow completionHandler:^(NSModalResponse answer) {
            __strong __typeof(weakSelf) confirmedCoordinator = weakSelf;
            if (confirmedCoordinator == nil) return;
            if (answer == NSAlertFirstButtonReturn && generation == confirmedCoordinator.themeOperationGeneration) [confirmedCoordinator saveNewTheme:snapshot title:title];
        }];
    }];
}

- (void)okForStylePanel:(id)sender
{
    if (stylePanel.sheetParent == _prefsWindow) [_prefsWindow endSheet:stylePanel returnCode:NSModalResponseOK];
}

- (void)cancelForStylePanel:(id)sender
{
    if (stylePanel.sheetParent == _prefsWindow) [_prefsWindow endSheet:stylePanel returnCode:NSModalResponseCancel];
}

// Actual Colors
- (IBAction)SourceTextColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorText"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }

    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorText" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)SourceBackgroundColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorBackground"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorBackground" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)SourceInsertionPointColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorInsertionPoint"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorInsertionPoint" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)PreviewBackgroundColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"PreviewBackground"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"PreviewBackground" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)ConsoleTextColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"ConsoleText"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"ConsoleText" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)ConsoleBackgroundColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"ConsoleBackground"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"ConsoleBackground" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)LogTextColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"LogText"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"LogText" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)LogBackgroundColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"LogBackground"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"LogBackground" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}


- (IBAction)SyntaxCommentColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxComment"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxComment" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)SyntaxCommandColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxCommand"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxCommand" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)SyntaxMarkerColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxMarker"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxMarker" fromColorWell:sender];
    [self refreshInheritedBracketColorWells];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)SyntaxIndexColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxIndex"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxIndex" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)FootnoteColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"FootnoteColor"];
        if (oldColor != nil)
            ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"FootnoteColor" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)EntryColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EntryColor"];
        if (oldColor != nil)
            ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EntryColor" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}



- (IBAction)EditorReverseSyncChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorReverseSync"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
   [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorReverseSync" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)PreviewDirectSyncChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"PreviewDirectSync"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"PreviewDirectSync" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}


- (IBAction)EditorHighlightBracesChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorHighlightBraces"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorHighlightBraces" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)EditorHighlightContentChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorHighlightContent"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorHighlightContent" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)EditorInvisibleCharChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorInvisibleChar"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorInvisibleChar" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)EditorFlashChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorFlash"];
        if (oldColor != nil)
            ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorFlash" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)SourceAlphaChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SourceAlpha"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SourceAlpha" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)PreviewAlphaChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"PreviewAlpha"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"PreviewAlpha" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)ConsoleAlphaChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ConsoleAlpha"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"ConsoleAlpha" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)ImageForegroundChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"ImageForeground"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"ImageForeground" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)ImageBackgroundChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"ImageBackground"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"ImageBackground" fromColorWell:sender];
     [self SaveEditedStyle:sender];
    
}

- (IBAction)XMLCommentChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"XMLComment"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"XMLComment" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)XMLTagChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"XMLTag"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"XMLTag" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)XMLSpecialChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"XMLSpecial"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"XMLSpecial" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)XMLParameterChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"XMLParameter"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"XMLParameter" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)XMLValueChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"XMLValue"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"XMLValue" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)explFunctionColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        // Restore the well without storing its color, so a missing key stays missing.
        ((NSColorWell *)sender).color = [self editingColorForKey: @"explFunction"];
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explFunction" fromColorWell:sender];
    [self SaveEditedStyle:sender];

}

- (IBAction)markerParenColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        // Restore the well without storing its color, so a missing key stays missing.
        ((NSColorWell *)sender).color = [self editingColorForKey: @"SyntaxMarkerParen"];
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxMarkerParen" fromColorWell:sender];
    [self SaveEditedStyle:sender];

}

- (IBAction)markerCurlyColorChanged:sender
{
    
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        // Restore the well without storing its color, so a missing key stays missing.
        ((NSColorWell *)sender).color = [self editingColorForKey: @"SyntaxMarkerCurly"];
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxMarkerCurly" fromColorWell:sender];
    [self SaveEditedStyle:sender];

}

- (IBAction)markerSquareColorChanged:sender
{
    
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        // Restore the well without storing its color, so a missing key stays missing.
        ((NSColorWell *)sender).color = [self editingColorForKey: @"SyntaxMarkerSquare"];
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxMarkerSquare" fromColorWell:sender];
    [self SaveEditedStyle:sender];

}



- (IBAction)explVariableColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        // Restore the well without storing its color, so a missing key stays missing.
        ((NSColorWell *)sender).color = [self editingColorForKey: @"explVariable"];
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explVariable" fromColorWell:sender];
    [self SaveEditedStyle:sender];

}

- (IBAction)explIntenseFunctionColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        // Restore the well without storing its color, so a missing key stays missing.
        ((NSColorWell *)sender).color = [self editingColorForKey: @"explIntenseFunction"];
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explIntenseFunction" fromColorWell:sender];
    [self SaveEditedStyle:sender];

}

- (IBAction)explIntenseVariableColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        // Restore the well without storing its color, so a missing key stays missing.
        ((NSColorWell *)sender).color = [self editingColorForKey: @"explIntenseVariable"];
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explIntenseVariable" fromColorWell:sender];
    [self SaveEditedStyle:sender];

}

- (IBAction)explmykeyColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        // Restore the well without storing its color, so a missing key stays missing.
        ((NSColorWell *)sender).color = [self editingColorForKey: @"explmykey"];
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explmykey" fromColorWell:sender];
    [self SaveEditedStyle:sender];

}

- (IBAction)explmykeyArgumentColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        // Restore the well without storing its color, so a missing key stays missing.
        ((NSColorWell *)sender).color = [self editingColorForKey: @"explmykeyArgument"];
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explmykeyArgument" fromColorWell:sender];
    [self SaveEditedStyle:sender];

}

- (IBAction)explmsgColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        // Restore the well without storing its color, so a missing key stays missing.
        ((NSColorWell *)sender).color = [self editingColorForKey: @"explmsg"];
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explmsg" fromColorWell:sender];
    [self SaveEditedStyle:sender];

}




- (void)setThemeEditingEnabled:(BOOL)enabled inView:(NSView *)view
{
    for (NSView *child in view.subviews) {
        if ([child isKindOfClass:NSColorWell.class] && ((NSColorWell *)child).action != @selector(BlockCursorColorChanged:))
            [(NSColorWell *)child setEnabled:enabled];
        if ([child isKindOfClass:NSButton.class] && ((NSButton *)child).action == @selector(SaveNewStyle:))
            [(NSButton *)child setEnabled:enabled];
        [self setThemeEditingEnabled:enabled inView:child];
    }
}
- (TSThemeFileStore *)themeStore
{
    return [[TSThemeFileStore alloc] initWithDirectory:[NSURL fileURLWithPath:[ColorPath stringByExpandingTildeInPath] isDirectory:YES]];
}
- (void)saveNewTheme:(NSDictionary<NSString *, id> *)colors title:(NSString *)title
{
    NSError *error = nil;
    if (![[self themeStore] writeColors:colors title:title error:&error]) {
        [self showPreferenceError:NSLocalizedString(@"The new theme could not be saved. The original theme is unchanged.", @"")];
        return;
    }
    NSMutableDictionary<NSString *, id> *saved = [colors mutableCopy];
    saved[@"Title"] = title;
    EditingColors = saved;
    self.lastSavedEditingColors = [saved copy];
    for (NSPopUpButton *popup in @[LiteStyle, DarkStyle, EditingStyle]) {
        if ([popup itemWithTitle:title] == nil) [popup addItemWithTitle:title];
    }
    [EditingStyle selectItemWithTitle:title];
    [self FillInColorWells];
    [[TSColorSupport sharedInstance] initializeColors];
    [NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:self];
}
- (IBAction)themeSelectionChanged:(id)sender
{
    if (sender != LiteStyle && sender != DarkStyle) return;
    NSPopUpButton *popup = sender;
    NSString *title = popup.titleOfSelectedItem;
    if (title == nil) return;
    [SUD setObject:title forKey:popup == LiteStyle ? DefaultLiteThemeKey : DefaultDarkThemeKey];
    [[TSColorSupport sharedInstance] initializeColors];
    [NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:self];
}
- (BOOL)deactivateColorWellsInView:(NSView *)view
{
    BOOL owned = NO;
    for (NSView *child in view.subviews) {
        if ([child isKindOfClass:NSColorWell.class] && ((NSColorWell *)child).isActive) {
            [(NSColorWell *)child deactivate]; owned = YES;
        }
        owned = [self deactivateColorWellsInView:child] || owned;
    }
    return owned;
}
- (void)deactivatePreferenceColorWells
{
    if (_prefsWindow == nil) return;
    BOOL owned = [self deactivateColorWellsInView:_prefsWindow.contentView];
    if (owned && NSColorPanel.sharedColorPanelExists) [[NSColorPanel sharedColorPanel] close];
}

@end
