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
#import "TSThemeAlpha.h"
#import "TSThemeFileStore.h"
#import "TSLibraryRepair.h"


@implementation TSPreferences (Color)

NSInteger stringSort(id s1, id s2, void *context)
{
    NSComparisonResult result;
    result =  [(NSString *)s1 localizedCaseInsensitiveCompare: (NSString *)s2];
    return result;
}


// A theme's name as the list has it: composed, whatever form an earlier version stored it in (TSThemeFileStore titles).
static NSString *TSThemeTitle(NSString *title) { return title.precomposedStringWithCanonicalMapping; }

- (void)PrepareColorPane:(NSUserDefaults *)defaults;
{
    // The themes of Light and Dark Mode are chosen among the files in ~/Library/TeXShop/Themes.
    // A theme of Light or Dark Mode renamed elsewhere while Settings was closed is followed when only its case
    // changed; one deleted or renamed otherwise gives way to TeXShop's own.
    TSThemeFileStore *store = [self themeStore];
    for (NSString *chosen in @[self.lightThemeTitle ?: @"", self.darkThemeTitle ?: @""]) {
        if (chosen.length == 0) continue;
        NSString *existing = [store existingTitleForTitle:chosen];
        if (![existing isEqualToString:chosen]) [self themeListDidChangeTitle:chosen to:existing];
    }
    [self fillThemeMenus];
    // The theme of the window's appearance is edited first.
    NSString *editing = [self settingsWindowIsDark] ? self.darkThemeTitle : self.lightThemeTitle;
    self.editingThemeTitle = (editing != nil ? [store existingTitleForTitle:(NSString *_Nonnull)editing] : nil) ?: [store titles].firstObject;
    [self loadEditingTheme];
    [self.themeList reload];
}

- (BOOL)settingsWindowIsDark
{
    NSAppearance *appearance = _prefsWindow.effectiveAppearance ?: NSApp.effectiveAppearance;
    return [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
}

- (void)fillThemeMenus
{
    NSArray<NSString *> *titles = [[self themeStore] titles];
    for (NSPopUpButton *popup in @[LiteStyle, DarkStyle]) {
        [popup removeAllItems];
        [popup addItemsWithTitles:titles];
    }
    [LiteStyle selectItemWithTitle:self.lightThemeTitle ?: @""];
    [DarkStyle selectItemWithTitle:self.darkThemeTitle ?: @""];
}

// The wells show the colors of the theme chosen in the list.
- (void)loadEditingTheme
{
    NSString *title = self.editingThemeTitle;
    // A theme chosen in a list read before it was renamed or deleted elsewhere: the list says so and edits another.
    if (title != nil && [[self themeStore] existingTitleForTitle:(NSString *_Nonnull)title] == nil && self.themeList != nil) {
        [self.themeList themeWentMissing:(NSString *_Nonnull)title];
        return;
    }
    NSDictionary<NSString *, id> *saved = title == nil ? nil : [[self themeStore] readTitle:(NSString *_Nonnull)title];
    EditingColors = [saved mutableCopy];
    self.lastSavedEditingColors = saved;
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

// The color a well goes back to when it cannot be changed: as before, without its opacity, and the
// built-in one when the theme has none for the key.
- (NSColor *)editingOpaqueColorForKey: (NSString *)theKey
{
    BOOL withDarkColors = NO;
#ifdef MOJAVEORHIGHER
    withDarkColors = (atLeastMojave) && (_prefsWindow.effectiveAppearance.name == NSAppearanceNameDarkAqua);
#endif
    return [[TSColorSupport sharedInstance] opaqueColorForKey: theKey fromDictionary: EditingColors isWindowDark: withDarkColors];
}

// These colors are drawn opaque, so their wells offer no opacity. Colors whose opacity
// is used (flash, fullwidth background, image copy, preview sync) and the window
// opacity wells behind the sliders keep it.
- (void)useOpaqueColorWells
{
    NSColorWell * __strong wells[] = {SourceTextColorWell, SourceBackgroundColorWell, SourceInsertionPointColorWell,
        PreviewBackgroundColorWell, ConsoleTextColorWell, ConsoleBackgroundColorWell, LogTextColorWell, LogBackgroundColorWell,
        SyntaxCommentColorWell, SyntaxCommandColorWell, SyntaxMarkerColorWell, SyntaxIndexColorWell,
        markerParenColorWell, markerCurlyColorWell, markerSquareColorWell,
        EditorHighlightBracesColorWell, EditorHighlightContentColorWell, EditorInvisibleCharColorWell, EditorReverseSyncColorWell,
        EditorHighlightZenkakuSymbolColorWell, FootnoteColorWell, EntryColorWell,
        XMLCommentColorWell, XMLTagColorWell, XMLSpecialColorWell, XMLParameterColorWell, XMLValueColorWell,
        explFunctionColorWell, explVariableColorWell, explIntenseFunctionColorWell, explIntenseVariableColorWell,
        explmykeyColorWell, explmykeyArgumentColorWell, explmsgColorWell};
    for (NSUInteger i = 0; i < sizeof(wells) / sizeof(wells[0]); i++) {
        NSColorWell *well = wells[i];
        if (well == nil) continue;
        well.supportsAlpha = NO;
        NSColor *color = well.color;
        if (color != nil && color.alphaComponent < 1)
            well.color = [color colorWithAlphaComponent:1];
    }
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
    [self useOpaqueColorWells];
}

- (void)FillInColorWells
{
    [self setAllThemeEditingEnabled:(EditingColors != nil)];
    if (EditingColors == nil) return;
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    NSColor *footnoteCol;

    // Every well shows the color drawn for its key, in the appearance of the Settings window (-editingColorForKey:).
    SourceTextColorWell.color = [self editingColorForKey: @"EditorText"];
    SourceBackgroundColorWell.color = [self editingColorForKey: @"EditorBackground"];
    SourceInsertionPointColorWell.color = [self editingColorForKey: @"EditorInsertionPoint"];
    PreviewBackgroundColorWell.color = [self editingColorForKey: @"PreviewBackground"];
    ConsoleTextColorWell.color = [self editingColorForKey: @"ConsoleText"];
    ConsoleBackgroundColorWell.color = [self editingColorForKey: @"ConsoleBackground"];
    LogTextColorWell.color = [self editingColorForKey: @"LogText"];
    LogBackgroundColorWell.color = [self editingColorForKey: @"LogBackground"];
    SyntaxCommentColorWell.color = [self editingColorForKey: @"SyntaxComment"];
    SyntaxCommandColorWell.color = [self editingColorForKey: @"SyntaxCommand"];
    SyntaxMarkerColorWell.color = [self editingColorForKey: @"SyntaxMarker"];
    SyntaxIndexColorWell.color = [self editingColorForKey: @"SyntaxIndex"];
    
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
   
    
    EditorHighlightBracesColorWell.color = [self editingColorForKey: @"EditorHighlightBraces"];
    EditorHighlightContentColorWell.color = [self editingColorForKey: @"EditorHighlightContent"];
    EditorInvisibleCharColorWell.color = [self editingColorForKey: @"EditorInvisibleChar"];
    EditorHighlightZenkakuSymbolColorWell.color = [self fullwidthHighlightColorForKey: @"EditorHighlightZenkakuSymbol"];
    EditorHighlightZenkakuSymbolBackgroundColorWell.color = [self fullwidthHighlightColorForKey: @"EditorHighlightZenkakuSymbolBackground"];
    EditorFlashColorWell.color = [self editingColorForKey: @"EditorFlash"];
    
    footnoteCol = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"FootnoteColor"];
    if (footnoteCol == nil)
        footnoteCol = [self editingColorForKey: @"SyntaxCommand"];
    FootnoteColorWell.color = footnoteCol;
/*
    else if (withDarkColors)
        // FootnoteColorWell.color = [NSColor colorWithRed:0.75 green:0.75 blue:0.75 alpha:1.00];
        FootnoteColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"FootnoteColor"];
    else
        // FootnoteColorWell.color = [NSColor colorWithRed:0.35 green:0.35 blue:0.35 alpha:1];
        FootnoteColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"FootnoteColor"];
 */
    
    // The active line as it is drawn: without its own color, one that the text reads on (TSColorSupport).
    EntryColorWell.color = [self editingColorForKey: @"EntryColor"];

        
    EditorReverseSyncColorWell.color = [self editingColorForKey: @"EditorReverseSync"];
    PreviewDirectSyncColorWell.color = [self editingColorForKey: @"PreviewDirectSync"];
    SourceAlphaColorWell.color = TSThemeWindowAlphaColor(EditingColors, TSThemeSourceAlphaKey);
    PreviewAlphaColorWell.color = TSThemeWindowAlphaColor(EditingColors, TSThemePreviewAlphaKey);
    ConsoleAlphaColorWell.color = TSThemeWindowAlphaColor(EditingColors, TSThemeConsoleAlphaKey);
    ImageForegroundColorWell.color = [self editingColorForKey: @"ImageForeground"];
    ImageBackgroundColorWell.color = [self editingColorForKey: @"ImageBackground"];
    
    XMLCommentColorWell.color = [self editingColorForKey: @"XMLComment"];
    
    XMLTagColorWell.color = [self editingColorForKey: @"XMLTag"];
    
    XMLSpecialColorWell.color = [self editingColorForKey: @"XMLSpecial"];
    
    XMLParameterColorWell.color = [self editingColorForKey: @"XMLParameter"];
    
    XMLValueColorWell.color = [self editingColorForKey: @"XMLValue"];
    [self useOpaqueColorWells];
}

- (IBAction)SaveEditedStyle:(id)sender
{
    NSString *title = self.editingThemeTitle;
    if (title == nil || EditingColors == nil || self.lastSavedEditingColors == nil) return;
    // Only the colors changed here replace those of the file as it is now (TSThemeFileStore).
    NSDictionary<NSString *, id> *before = self.lastSavedEditingColors;
    NSError *error = nil;
    NSDictionary<NSString *, id> *written = [[self themeStore] writeChangesFrom:before to:EditingColors title:title error:&error];
    if (written == nil && [error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSFileNoSuchFileError) {
        // Renamed or deleted elsewhere: it is not made again under its old name.
        [self.themeList themeWentMissing:title];
        return;
    }
    if (written == nil) {
        NSDictionary<NSString *, id> *saved = [[self themeStore] readTitle:title] ?: self.lastSavedEditingColors;
        EditingColors = [saved mutableCopy];
        self.lastSavedEditingColors = saved;
        [self FillInColorWells];
        [self showPreferenceError:NSLocalizedString(@"The theme could not be saved. Its last saved colors have been restored.", @"")];
        return;
    }
    // Colors not changed here that the file had changed meanwhile.
    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:written.allKeys];
    [keys addObjectsFromArray:before.allKeys];
    [keys removeObject:@"Title"];
    BOOL othersChanged = NO;
    for (NSString *key in keys) {
        id mine = EditingColors[key];
        if ((mine == before[key] || [mine isEqual:before[key]]) && !(written[key] == before[key] || [written[key] isEqual:before[key]]))
            othersChanged = YES;
    }
    EditingColors = [written mutableCopy];
    self.lastSavedEditingColors = written;
    // Renamed elsewhere in case only: the theme is edited under the name it now has.
    NSString *current = [written[@"Title"] isKindOfClass:NSString.class] ? written[@"Title"] : nil;
    if (current != nil && ![current isEqualToString:title] && [[[self themeStore] existingTitleForTitle:title] isEqualToString:(NSString *_Nonnull)current]) {
        [self themeListDidChangeTitle:title to:current];
        title = (NSString *_Nonnull)current;
        [self.themeList reload];
    }
    // A bundled theme changed here is marked at once.
    [self.themeList refreshTitle:title];
    // The wells show the colors changed elsewhere.
    if (othersChanged)
        [self FillInColorWells];
    [self applyEffectsForPreferenceKeys:[NSSet setWithArray:@[DefaultLiteThemeKey, DefaultDarkThemeKey]]];
}

// Actual Colors
- (IBAction)SourceTextColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [self editingOpaqueColorForKey: @"EditorText"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"EditorBackground"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"EditorInsertionPoint"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"PreviewBackground"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"ConsoleText"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"ConsoleBackground"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"LogText"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"LogBackground"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"SyntaxComment"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"SyntaxCommand"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"SyntaxMarker"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"SyntaxIndex"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"FootnoteColor"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"EntryColor"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"EditorReverseSync"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"PreviewDirectSync"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"EditorHighlightBraces"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"EditorHighlightContent"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"EditorInvisibleChar"];
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorInvisibleChar" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

// A theme without the fullwidth keys shows these characters like other text,
// so the wells then show the text and background colors.
- (NSColor *)fullwidthHighlightColorForKey:(NSString *)key
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    NSColor *color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey:key];
    if (color != nil)
        return color;
    NSString *fallback = [key hasSuffix:@"Background"] ? @"EditorBackground" : @"EditorText";
    return [self editingColorForKey:fallback];
}

- (IBAction)EditorHighlightZenkakuSymbolChanged:sender
{
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        ((NSColorWell *)sender).color = [self fullwidthHighlightColorForKey: @"EditorHighlightZenkakuSymbol"];
        return;
    }
    [[TSColorSupport sharedInstance] changeColorValueInDictionary: EditingColors forKey: @"EditorHighlightZenkakuSymbol" fromColorWell:sender];
    [self SaveEditedStyle:sender];
}

- (IBAction)EditorHighlightZenkakuSymbolBackgroundChanged:sender
{
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        ((NSColorWell *)sender).color = [self fullwidthHighlightColorForKey: @"EditorHighlightZenkakuSymbolBackground"];
        return;
    }
    [[TSColorSupport sharedInstance] changeColorValueInDictionary: EditingColors forKey: @"EditorHighlightZenkakuSymbolBackground" fromColorWell:sender];
    [self SaveEditedStyle:sender];
}

- (IBAction)EditorFlashChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [self editingOpaqueColorForKey: @"EditorFlash"];
        if (oldColor != nil)
            ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorFlash" fromColorWell:sender];
    [self SaveEditedStyle:sender];
    
}

// Opacity controls change only the stored alpha. Avoid converting the retained
// RGB through a different NSColor space when adjusting a percentage.
- (void)changeWindowAlphaForKey:(NSString *)key fromWell:(NSColorWell *)well
{
    NSArray *existing=EditingColors[key];
    if([existing isKindOfClass:NSArray.class] && existing.count==4){
        NSMutableArray *components=[existing mutableCopy];
        components[3]=@(well.color.alphaComponent);
        EditingColors[key]=components;
    } else {
        EditingColors[key]=@[@0,@0,@0,@(well.color.alphaComponent)];
    }
}

- (IBAction)SourceAlphaChanged:sender
{
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = TSThemeWindowAlphaColor(EditingColors, TSThemeSourceAlphaKey);
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [self changeWindowAlphaForKey:TSThemeSourceAlphaKey fromWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)PreviewAlphaChanged:sender
{
    
   if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = TSThemeWindowAlphaColor(EditingColors, TSThemePreviewAlphaKey);
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [self changeWindowAlphaForKey:TSThemePreviewAlphaKey fromWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)ConsoleAlphaChanged:sender
{
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = TSThemeWindowAlphaColor(EditingColors, TSThemeConsoleAlphaKey);
        ((NSColorWell *)sender).color = oldColor;
        return;
    }
    [self changeWindowAlphaForKey:TSThemeConsoleAlphaKey fromWell:sender];
    [self SaveEditedStyle:sender];
    
}

- (IBAction)ImageForegroundChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! (NSColorPanel.sharedColorPanelExists && [NSColorPanel sharedColorPanel].keyWindow)))
    {
        [self deactivatePreferenceColorWells];
        NSColor *oldColor = [self editingOpaqueColorForKey: @"ImageForeground"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"ImageBackground"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"XMLComment"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"XMLTag"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"XMLSpecial"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"XMLParameter"];
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
        NSColor *oldColor = [self editingOpaqueColorForKey: @"XMLValue"];
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
        [self setThemeEditingEnabled:enabled inView:child];
    }
}
- (TSThemeFileStore *)themeStore
{
    return [[TSThemeFileStore alloc] initWithDirectory:[NSURL fileURLWithPath:[ColorPath stringByExpandingTildeInPath] isDirectory:YES]];
}
#pragma mark Theme list

- (nullable NSWindow *)themeListWindow { return _prefsWindow; }
- (nullable NSString *)lightThemeTitle { return TSThemeTitle([SUD stringForKey:DefaultLiteThemeKey]); }
- (nullable NSString *)darkThemeTitle { return TSThemeTitle([SUD stringForKey:DefaultDarkThemeKey]); }

// A new theme starts with TeXShop's own colors for the appearance of the moment.
- (nullable NSDictionary<NSString *, id> *)newThemeColors
{
    NSString *name = [self settingsWindowIsDark] ? @"DarkTheme" : @"LiteTheme";
    NSString *path = TSLibraryBundledPath([@"Themes" stringByAppendingPathComponent:[name stringByAppendingString:@".plist"]]);
    NSData *data = path != nil ? [NSData dataWithContentsOfFile:path] : nil;
    id colors = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    return [colors isKindOfClass:NSDictionary.class] ? colors : [[self themeStore] readTitle:name];
}

- (void)themeListDidChooseTitle:(nullable NSString *)title
{
    self.editingThemeTitle = title;
    [self loadEditingTheme];
}

// A renamed theme stays chosen for Light or Dark Mode under its new name; a deleted one gives way to TeXShop's own.
- (void)themeListDidChangeTitle:(nullable NSString *)changedTitle to:(nullable NSString *)newTitle
{
    BOOL inUse = NO;
    NSString *oldTitle = changedTitle ?: @"";
    if (changedTitle != nil && ![oldTitle isEqualToString:newTitle ?: @""]) {
        if ([self.lightThemeTitle isEqualToString:oldTitle]) {
            [SUD setObject:newTitle ?: @"LiteTheme" forKey:DefaultLiteThemeKey];
            inUse = YES;
        }
        if ([self.darkThemeTitle isEqualToString:oldTitle]) {
            [SUD setObject:newTitle ?: @"DarkTheme" forKey:DefaultDarkThemeKey];
            inUse = YES;
        }
        if ([self.editingThemeTitle isEqualToString:oldTitle] && newTitle != nil) self.editingThemeTitle = newTitle;
    }
    [self fillThemeMenus];
    // Restored colors.
    if (changedTitle != nil && [oldTitle isEqualToString:newTitle ?: @""]) {
        if ([self.editingThemeTitle isEqualToString:oldTitle]) [self loadEditingTheme];
        inUse = [self.lightThemeTitle isEqualToString:oldTitle] || [self.darkThemeTitle isEqualToString:oldTitle];
    }
    if (inUse) [self applyEffectsForPreferenceKeys:[NSSet setWithArray:@[DefaultLiteThemeKey, DefaultDarkThemeKey]]];
}

- (void)themeListShowError:(NSString *)message { [self showPreferenceError:message]; }

// A file imported as a theme has the form TeXShop repairs themes to (TSLibraryThemeCheck) and at least one of the
// colors of TeXShop's themes: a property list of other settings is not a theme.
- (BOOL)themeListAcceptsData:(NSData *)data
{
    if (!TSLibraryThemeCheck()(data, nil)) return NO;
    NSDictionary *theme = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    NSString *lite = TSLibraryBundledPath(@"Themes/LiteTheme.plist");
    // TeXShop's LiteTheme names the colors; its copy in the Themes folder when TeXShop's own cannot be read.
    NSDictionary *reference = (lite != nil ? [NSDictionary dictionaryWithContentsOfFile:(NSString *_Nonnull)lite] : nil) ?: [[self themeStore] readTitle:@"LiteTheme"];
    for (NSString *key in theme) {
        id value = theme[key];
        if (![value isKindOfClass:NSArray.class]) continue;
        if (reference == nil || [reference[key] isKindOfClass:NSArray.class]) return YES;
    }
    return NO;
}

- (IBAction)themeSelectionChanged:(id)sender
{
    if (sender != LiteStyle && sender != DarkStyle) return;
    NSPopUpButton *popup = sender;
    NSString *title = popup.titleOfSelectedItem;
    if (title == nil) return;
    [SUD setObject:title forKey:popup == LiteStyle ? DefaultLiteThemeKey : DefaultDarkThemeKey];
    [self applyEffectsForPreferenceKeys:[NSSet setWithArray:@[DefaultLiteThemeKey, DefaultDarkThemeKey]]];
    [self.themeList reload];
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
