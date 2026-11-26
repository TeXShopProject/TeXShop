/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2014 Richard Koch
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
 * $Id: TSDocument-Jobs.m 254 2014-06-28 21:09:25Z fingolfin $
 *
 */


#import "TSDocument.h"
#import "globals.h"
#import "TSColorSupport.h"
#import "TSThemeSystemColor.h"
#import "TSSyntaxColorScheme.h"
#import "TSThemeAlpha.h"
#import "MyPDFKitView.h"


@implementation TSDocument (Color)

- (void) applySourceSelectionColorToTextView: (NSTextView *)aTextView
{
    TSThemeSetSelectionColor(aTextView, self.sourceSelectionColor);
}

- (void) endReverseSyncSelection
{
    // The view marked, or, if it has gone (its part of a split closed), the one in use.
    NSTextView *marked = self.reverseSyncTextView ?: [self textView];
    [self setTextSelectionYellow: NO];
    [self applySourceSelectionColorToTextView: marked];
}

- (void)changeColors: (BOOL)toDark;
{
    NSDictionary *theDictionary;
    
    if (toDark)
        theDictionary = darkColors;
    else
        theDictionary = liteColors;
    
    [self changeColorsUsingDictionary: theDictionary];
    
}


- (void) changeColorsUsingDictionary: (NSDictionary *)colorDictionary
{
    NSColor *myBackgroundColor;
    NSColor *myTextColor;
    NSColor *myColor;
    BOOL    withDarkColors;
    
#ifdef MOJAVEORHIGHER
    if ((atLeastMojave) && (textWindow.effectiveAppearance.name == NSAppearanceNameDarkAqua))
        withDarkColors = YES;
    else
#endif
        withDarkColors = NO;
    
    /*
     flashColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorFlash"];
     if (flashColor != nil)
     EditorFlashColorWell.color = flashColor;
     else if (withDarkColors)
     EditorFlashColorWell.color = [NSColor colorWithDeviceRed:0.00 green:0.20 blue:0.20 alpha:1.00];
     else
     EditorFlashColorWell.color = [NSColor colorWithDeviceRed:1 green:0.95 blue:1 alpha:1];
     */
    
    
    // EDITOR
    // A color the theme does not have is the built-in one of the mode (TSColorSupport), never nil.
    
    [self.myPDFKitView updatePreviewPaperColor];
    [self.myPDFKitView2 updatePreviewPaperColor];
    
    myBackgroundColor = [[TSColorSupport sharedInstance] opaqueColorForKey: @"EditorBackground" fromDictionary: colorDictionary isWindowDark: withDarkColors];
    myTextColor = [[TSColorSupport sharedInstance] opaqueColorForKey: @"EditorText" fromDictionary: colorDictionary isWindowDark: withDarkColors];
    
    // [textView1 setTextColor: myTextColor];
    // [textView2 setTextColor: myTextColor];
    [textView1 setBackgroundColor: myBackgroundColor];
    [textView2 setBackgroundColor: myBackgroundColor];
    
    /*
     NSParagraphStyle         *    paraStyle            = [NSParagraphStyle defaultParagraphStyle];
     NSMutableParagraphStyle    *    newStyle            = [paraStyle mutableCopy] ;
     
     NSMutableDictionary *theTypingAttributes = [[NSMutableDictionary alloc] initWithCapacity:1] ;
     [theTypingAttributes setObject:newStyle forKey:NSParagraphStyleAttributeName];
     [textView1 setTypingAttributes:theTypingAttributes];
     
     NSMutableDictionary *theTypingAttributes2 = [[NSMutableDictionary alloc] initWithCapacity:1];
     [theTypingAttributes2 setObject:newStyle forKey:NSParagraphStyleAttributeName];
     [textView2 setTypingAttributes:theTypingAttributes2];
     
     [textView1 setFontSafely:font];
     [textView1 setDefaultParagraphStyle: newStyle];
     [textView2 setFontSafely:font];
     [textView2 setDefaultParagraphStyle: newStyle];
     */
    
    
    [textView1 setTextColor: myTextColor];
    [textView2 setTextColor: myTextColor];
    
    
    // LOG WINDOW
    
    myBackgroundColor = [[TSColorSupport sharedInstance] opaqueColorForKey: @"LogBackground" fromDictionary: colorDictionary isWindowDark: withDarkColors];
    myTextColor = [[TSColorSupport sharedInstance] opaqueColorForKey: @"LogText" fromDictionary: colorDictionary isWindowDark: withDarkColors];
    
    [self.logTextView setTextColor: myTextColor];
    [self.logTextView setBackgroundColor: myBackgroundColor];
    
    // CONSOLE WINDOW
    
    myBackgroundColor = [[TSColorSupport sharedInstance] opaqueColorForKey: @"ConsoleBackground" fromDictionary: colorDictionary isWindowDark: withDarkColors];
    myTextColor = [[TSColorSupport sharedInstance] opaqueColorForKey: @"ConsoleText" fromDictionary: colorDictionary isWindowDark: withDarkColors];
    
    [outputText setTextColor: myTextColor];
    [outputText setBackgroundColor: myBackgroundColor];
    
    
    // SYNTAX COLORS
    TSSyntaxColorScheme *scheme = [[TSSyntaxColorScheme alloc] initWithTheme:colorDictionary dark:withDarkColors];
    self.syntaxColorScheme = scheme;
    self.commentColorAttribute = [scheme attributesForRole:TSSyntaxRoleComment];
    self.commandColorAttribute = [scheme attributesForRole:TSSyntaxRoleCommand];
    self.markerColorAttribute = [scheme attributesForRole:TSSyntaxRoleMarker];
    self.markerColorParenAttribute = [scheme attributesForRole:TSSyntaxRoleBracketParen];
    self.markerColorCurlyAttribute = [scheme attributesForRole:TSSyntaxRoleBracketCurly];
    self.markerColorSquareAttribute = [scheme attributesForRole:TSSyntaxRoleBracketSquare];
    self.indexColorAttribute = [scheme attributesForRole:TSSyntaxRoleIndex];
    self.footnoteColorAttribute = [scheme attributesForRole:TSSyntaxRoleFootnote];
    // Without fullwidth colors, fullwidth characters are colored like other text.
    NSDictionary *fullwidthAttributes = [scheme attributesForRole:TSSyntaxRoleFullwidthSymbol];
    self.fullwidthSymbolColorAttribute = fullwidthAttributes.count ? fullwidthAttributes : nil;
    self.explColorAttribute1 = [scheme attributesForRole:TSSyntaxRoleExplVariable];
    self.explColorAttribute2 = [scheme attributesForRole:TSSyntaxRoleExplFunction];
    self.explColorAttribute3 = [scheme attributesForRole:TSSyntaxRoleExplIntenseVariable];
    self.explColorAttribute4 = [scheme attributesForRole:TSSyntaxRoleExplIntenseFunction];
    self.explColorAttribute5 = [scheme attributesForRole:TSSyntaxRoleExplMessage];
    self.explColorAttribute6 = [scheme attributesForRole:TSSyntaxRoleExplKey];
    self.explColorAttribute7 = [scheme attributesForRole:TSSyntaxRoleExplKeyArgument];
    self.commentXMLColorAttribute = [scheme attributesForRole:TSSyntaxRoleXMLComment];
    self.tagXMLColorAttribute = [scheme attributesForRole:TSSyntaxRoleXMLTag];
    self.specialXMLColorAttribute = [scheme attributesForRole:TSSyntaxRoleXMLSpecial];
    self.parameterXMLColorAttribute = [scheme attributesForRole:TSSyntaxRoleXMLParameter];
    self.valueXMLColorAttribute = [scheme attributesForRole:TSSyntaxRoleXMLValue];
    self.EntryColorAttribute = scheme.activeLineAttributes;
    highlightBracesColorDict = scheme.braceHighlightAttributes;
    highlightContentColorDict = scheme.contentHighlightAttributes;
    
    myColor = [[TSColorSupport sharedInstance] opaqueColorForKey: @"EditorReverseSync" fromDictionary: colorDictionary isWindowDark: withDarkColors];
    ReverseSyncColor = myColor;
    
    myColor = [[TSColorSupport sharedInstance] insertionPointColorFromDictionary: colorDictionary isWindowDark: withDarkColors];
    [textView1 setInsertionPointColor: myColor];
    [textView2 setInsertionPointColor: myColor];
    
    // The selection; a view the reverse sync has marked keeps its mark until the next click or key.
    self.sourceSelectionColor = [[TSColorSupport sharedInstance] selectionColorFromDictionary: colorDictionary isWindowDark: withDarkColors];
    for (NSTextView *view in @[textView1 ?: (id)NSNull.null, textView2 ?: (id)NSNull.null]) {
        if ([view isKindOfClass: NSTextView.class] && !([self textSelectionYellow] && view == self.reverseSyncTextView))
            [self applySourceSelectionColorToTextView: view];
    }
    
    myColor = [[TSColorSupport sharedInstance] opaqueColorForKey: @"EditorInvisibleChar" fromDictionary: colorDictionary isWindowDark: withDarkColors];
    InvisibleColor = myColor;
    
    self.pdfKitWindow.alphaValue = TSThemeWindowAlpha(colorDictionary, TSThemePreviewAlphaKey);
    textWindow.alphaValue = TSThemeWindowAlpha(colorDictionary, TSThemeSourceAlphaKey);
    fullSplitWindow.alphaValue = TSThemeWindowAlpha(colorDictionary, TSThemeSourceAlphaKey);
    outputWindow.alphaValue = TSThemeWindowAlpha(colorDictionary, TSThemeConsoleAlphaKey);
    
    myColor = [[TSColorSupport sharedInstance] colorAndAlphaFromDictionary:colorDictionary andKey: @"ImageForeground"];
    // The text of copied images is never drawn invisible, as it would be with a fully transparent color.
    if (myColor != nil && myColor.alphaComponent == 0)
        myColor = [myColor colorWithAlphaComponent:1];
    ImageForegroundColor = myColor;
    
    myColor = [[TSColorSupport sharedInstance] colorAndAlphaFromDictionary:colorDictionary andKey: @"ImageBackground"];
    ImageBackgroundColor = myColor;
    
    myColor = [[TSColorSupport sharedInstance] colorAndAlphaFromDictionary:colorDictionary andKey: @"PreviewDirectSync"];
    PreviewDirectSyncColor = myColor;
    
    
    
    [self.myPDFKitView setNeedsDisplay: YES];
    [self.myPDFKitView2 setNeedsDisplay: YES];

    // update console and log
    [outputWindow display];
    [self.logWindow display];
    
    [self colorizeVisibleAreaInTextView:textView1];
    [self colorizeVisibleAreaInTextView:textView2];
    [self colorizeExperimentSource];
    
}

- (void) changeColorsFromNotification:(NSNotification *)notification
{
    NSDictionary *colorDictionary;
    
    colorDictionary = notification.userInfo;
    
    // next code is case when color change didn't really come from a notification
    
    if (colorDictionary == nil)
    {
        colorDictionary = liteColors;
#ifdef MOJAVEORHIGHER
       if (atLeastMojave)
       {
        if (textView1.effectiveAppearance.name == NSAppearanceNameDarkAqua)
            colorDictionary = darkColors;
       }
#endif
    }
    
    [self changeColorsUsingDictionary: colorDictionary];
    
}


@end
