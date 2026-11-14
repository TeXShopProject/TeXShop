/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2005 Richard Koch
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
 * $Id: TSDocument-Syntax.m 262 2007-08-17 01:33:24Z richard_koch $
 *
 */

#import "UseMitsu.h"

#import "TSDocument.h"
#import "TSTextView.h"
#import "globals.h"
#import "TSSyntaxTeXScanner.h"
#import "TSSyntaxHighlighter.h"

/*
 * Syntax highlighting for TSDocument is implemented in the following code.
 * The general approach is this: We color ranges of text by using temporary
 * attributes of the layout manager(s) associated to our text view(s).
 * This is a lot faster than using plain text attributes (for example, regular
 * attributes cause the layout to be invalidated when they are changed,
 * which leads to a major slow down).
 * The core of this is in method colorizeText:range:, which clears the given lines
 * and colors the tokens that TSSyntaxTeXScanner finds in them, with the colors of
 * the document's TSSyntaxColorScheme, through TSSyntaxHighlighter.
 *
 * For efficiency, we only actively colorize text which is visible. We colorize
 * in response to textDidChange:, to catch text typed by the user.
 * We also track changes to the text view (resizing, scrolling) and re-color
 * the visible text when any of those events occurs via colorizeVisibleAreaInTextView:.
 *
 * Text being composed with an input method (marked text) is not colored. While it
 * is there, every keystroke can resize the text view, and coloring then would
 * recolor the visible text each time and color the composed text itself. Coloring
 * waits, and the visible text is colored once the composed text is committed or
 * removed; see coloringWaitsForMarkedTextIn: and colorAfterMarkedTextEnds.
 */

@implementation TSDocument (SyntaxHighlighting)

// Whether a view of this text, the source in either half of a split window or the
// Experiment source, holds text being composed with an input method.
static BOOL TSTextStorageHasMarkedText(NSTextStorage *storage)
{
    for (NSLayoutManager *layoutManager in storage.layoutManagers)
        for (NSTextContainer *container in layoutManager.textContainers)
            if (container.textView.hasMarkedText)
                return YES;
    return NO;
}

// YES while the text of aTextView holds text being composed; the coloring asked for
// is then done by colorAfterMarkedTextEnds.
- (BOOL)coloringWaitsForMarkedTextIn:(NSTextView *)aTextView
{
    if (!aTextView || !TSTextStorageHasMarkedText(aTextView.textStorage))
        return NO;
    self.coloringWaitsForMarkedText = YES;
    return YES;
}

// Called when the selection changes, as it does whenever composed text changes, is
// committed or is removed. It looks again once AppKit has finished with the keystroke.
- (void)colorAfterMarkedTextEnds
{
    if (!self.coloringWaitsForMarkedText)
        return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(colorWaitingForMarkedText) object:nil];
    [self performSelector:@selector(colorWaitingForMarkedText) withObject:nil afterDelay:0];
}

// Nothing is colored while text is still being composed in the source or in the
// shown Experiment source, not even the other one. Text left composed in a closed
// Experiment window does not hold back the source; it waits again when that window
// is shown. A brace highlight kept while text was composed is removed by
// -resetHighlight:, which the same change of the selection schedules.
- (void)colorWaitingForMarkedText
{
    if (!self.coloringWaitsForMarkedText || TSTextStorageHasMarkedText(self.textStorage) ||
        (scrapTextView.window.isVisible && TSTextStorageHasMarkedText(scrapTextView.textStorage)))
        return;
    self.coloringWaitsForMarkedText = NO;
    [self colorizeAll];
    [self cursorMoved:textView];
    [self refreshExperimentCurrentLine];
}



// Colorize ("perform syntax highlighting") all the characters in the given range.
// Can only recolor full lines, so the given range will be extended accordingly before the
// coloring takes place.

// This routine contains a very important bug fix. If a very large document is loaded, the
// system immediately returns after the command which inserts text, and then text is added on
// a thread. As this text is added, the document resizes, and each resize calls the syntax
// coloring routine. The result is that the visible region is syntax colored over and over
// again. If the user tries to edit during this time, the rotating cursor appears, and eventually
// the program crashes.
//

// Notice the code below to avoid recoloring when the file is first opened!
// YES when the paragraph containing location already has the given alignment.
// Natural alignment counts as left alignment only in a left-to-right paragraph;
// in a right-to-left one it lays the line out on the right, so report NO.
static BOOL TSParagraphHasAlignment(NSTextStorage *storage, NSUInteger location, NSTextAlignment alignment)
{
    if (location >= [storage length])
        return NO;
    NSParagraphStyle *style = [storage attribute:NSParagraphStyleAttributeName atIndex:location effectiveRange:NULL];
    if (! style)
        style = [NSParagraphStyle defaultParagraphStyle];
    NSTextAlignment current = [style alignment];
    if (current == NSTextAlignmentNatural) {
        NSWritingDirection direction = [style baseWritingDirection];
        if (direction == NSWritingDirectionNatural)
            direction = [NSParagraphStyle defaultWritingDirectionForLanguage:nil];
        if (direction != NSWritingDirectionLeftToRight)
            return NO;
        current = NSLeftTextAlignment;
    }
    return current == alignment;
}

- (void)colorizeText:(NSTextView *)aTextView range:(NSRange)range
{
    NSLayoutManager *layoutManager;
    NSString        *textString;
    NSUInteger        length;
    NSRange            colorRange;
    NSUInteger        aLineStart;
    NSUInteger        aLineEnd;
    BOOL            colorIndexDifferently;
    BOOL            colorFootnoteDifferently;
    NSTimeInterval    theTime;
    BOOL            TurnOffCommandSpellChecking;
    BOOL            TurnOffCommentSpellChecking;
    BOOL            TurnOffParameterSpellChecking;
    BOOL            ListHasWordsWhoseParametersShouldBeChecked;
    BOOL            colorExpl3;
    
    if ([self coloringWaitsForMarkedTextIn:aTextView])
        return;

    colorExpl3 = self.useExplColor; // [SUD boolForKey:expl3SyntaxColoringKey];
    
    // New rules and legacy exclusions are alternative spelling modes.
    BOOL texAwareSpelling = [self.textView usesTeXAwareSpellChecking];
    TurnOffCommandSpellChecking = !texAwareSpelling && [SUD boolForKey:TurnOffCommandSpellCheckKey];
    TurnOffCommentSpellChecking = !texAwareSpelling && [SUD boolForKey:TurnOffCommentSpellCheckKey];
    TurnOffParameterSpellChecking = !texAwareSpelling && [SUD boolForKey:TurnOffParameterSpellCheckKey];
    ListHasWordsWhoseParametersShouldBeChecked = [SUD boolForKey:ExceptionListExcludesParametersKey];
    
    
    if (isLoading) {
        if (firstTime == YES) {
            colorTime = [[NSDate date] timeIntervalSince1970];
            firstTime = NO;
            // secondTime = YES;
        }
        else {
            theTime = [[NSDate date] timeIntervalSince1970];
            
            // secondTime = NO;
            // NSLog([NSString stringWithFormat:@"%f", theTime]);
            // NSLog([NSString stringWithFormat:@"%f",colorTime]);
            if ((theTime - colorTime) < 1.0) {
                colorTime = theTime;
                if (! [SUD boolForKey: ColorImmediatelyKey] )
                    return;
            }
            else {
                isLoading = NO;
                [self doUpdate:self];
                // NSLog(@"it ended");
            }
        }
    }
    
    
    /*
     
     Experiments show that TSDocument routines can be called in the following order
     
     close
     colorizeText
     dealloc
     
     Thus colorizeText can be called after close but before dealloc. By the time it is
     called, some of the pieces of the document, including the toolbar, have been deallocated.
     
     This is why the code below does not itself look at the indexColorBox to get its state.
     
     */
    
    // The next line may not be necessary, but seems to produce a smoother result. Koch/2022
    // Actually, it causes a crash bug is a large number of blank lines are deleted and both syntax coloring and active line coloring are on. Koch, July 1, 2022
    
    // [self cursorMoved:[self textView]];
    
    
    colorIndexDifferently =  [self indexColorState];
    colorFootnoteDifferently = [SUD boolForKey: SyntaxColorFootnoteKey];
    
    
    // Fetch the underlying layout manager and string.
    layoutManager = [aTextView layoutManager];
    textString = [aTextView string];
    length = [textString length];
    
    // Clip the given range (call it paranoia, if you like :-).
    if (range.location >= length)
        return;
    // changed by Terada: Clamp the range to the string regardless of persistent highlighting.
    if (range.length > length - range.location)
    {
    //    NSLog(@"fixed");
        range.length = length - range.location;
    }
    
    // NSLog(@"The location and length are %d and %d", range.location, range.length);
    
    // We only perform coloring for full lines here, so extend the given range to full lines.
    // Note that aLineStart is the start of *a* line, but not necessarily the same line
    // for which aLineEnd marks the end! We may span many lines.
    [textString getLineStart:&aLineStart end:&aLineEnd contentsEnd:nil forRange:range];
    
    // NSLog(@"got here");
    
    // Handle Persian, Arabic, and Hebrew Justification
    
    NSRange            lineRange, selectedLineRange, middleEastRange, testRange;
    NSCharacterSet    *middleEastSet;
    NSUInteger        start, theend;
    NSString        *theLine;
    
    if ([SUD boolForKey: RightJustifyKey]) {
        // Arabic and Persian range is 0600 - 06FF; Hebrew range is 0590 - 05FF
        middleEastRange.location = 0x0590;
        middleEastRange.length = 0x016F;
        middleEastSet = [NSCharacterSet characterSetWithRange: middleEastRange];
        
        lineRange.location = aLineStart;
        lineRange.length = 1;
        while (lineRange.location < aLineEnd) {
            [textString getLineStart: &start end: &theend contentsEnd: nil forRange: lineRange];
            lineRange.location = theend;
            selectedLineRange.location = start;
            selectedLineRange.length = theend - start;
            if ( ! [SUD boolForKey: RightJustifyIfAnyKey] ) {
                // a line must START with Persian, etc., to be right justified; later must have Persian in first three letters
                if (selectedLineRange.length >= 3)
                    selectedLineRange.length = 3;
            }
            theLine = [textString substringWithRange:selectedLineRange];
            testRange = [theLine rangeOfCharacterFromSet: middleEastSet];
            NSTextAlignment wanted = (testRange.location == NSNotFound) ? NSLeftTextAlignment : NSRightTextAlignment;
            // Setting the alignment edits the text storage, which relays out the
            // paragraph, resizes the view and colors the visible area again. Only
            // change it when it differs, so that coloring does not feed itself.
            if (! TSParagraphHasAlignment([aTextView textStorage], start, wanted))
                [aTextView setAlignment: wanted range: selectedLineRange];
        }
    }
    
    // NSLog(@"after Hebrew");
    
    // We reset the color of all chars in the given range to the regular color; later, we'll
    // then only recolor anything which is supposed to have another color.
    colorRange.location = aLineStart;
    colorRange.length = aLineEnd - aLineStart;
    
    /* September 4, 2018: Below is a dialog I don't understand. I don't understand why
     the first author commented out my line of code below, or why I put it back, or why
     Toudykov's code made it unnecessary!
     
     All I know is that when color support was completely rewritten for Mojave, removing a comment did not
     change the color of the ordinary text which followed from the comment color back to the ordinary text
     color. Then I reactivated my code, which fixed the problem, and then commented out
     Toudykov's code, which changed nothing. So we are back where we started. */
    
    
    // WARNING!! The following line has been commented out to restore changing the text color
    
    
    // June 27, 2008; Koch; I don't understand the previous warning; the line below fixes cases when removing a comment leaves text red
    // Sept 3, 2011; the Toudykov patch below makes this unnecessary
    [layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:colorRange];
    
    // the following line is deactivaeed active-line-colors are used because it caused them to to be removed when scrolling on May, 2022
    
    // HERE-RED
   if (( ! self.syntaxcolorEntry) && ( ![SUD boolForKey:AlwaysHighlightEnabledKey]))
      [layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:colorRange];
    
    // the next line was added by Daniel Toundykov to allow changing the foreground and background source colors
    // [layoutManager addTemporaryAttributes:self.regularColorAttribute forCharacterRange:colorRange];
    /* End of this strange section.
     */
    
    // NSLog(@"After confusing section");
    
    // Now the tokens of the lines get their colors.
    TSMutableSyntaxTeXOptions *options = [TSMutableSyntaxTeXOptions new];
    options.texCharacter = (unichar)g_texChar;
    options.colorsExpl3 = colorExpl3;
    options.makesAtLetter = [SUD boolForKey:MakeatletterEnabledKey];
    options.colorsIndex = colorIndexDifferently;
    options.colorsFootnote = colorFootnoteDifferently;
    options.marksFullwidthSymbols = [self.syntaxColorScheme attributesForRole:TSSyntaxRoleFullwidthSymbol].count > 0;
    options.isXML = self.fileIsXML;
    options.excludesCommandsFromSpelling = TurnOffCommandSpellChecking;
    options.excludesCommentsFromSpelling = TurnOffCommentSpellChecking;
    options.excludesParametersFromSpelling = TurnOffParameterSpellChecking;
    options.excludesParametersOfUnlistedCommands = ListHasWordsWhoseParametersShouldBeChecked;
    if (TurnOffParameterSpellChecking) {
        options.commandsWithCheckedParameters = [(commandsToSpellCheck ?: @[]) arrayByAddingObjectsFromArray:userCommandsToSpellCheck ?: @[]];
        options.commandsWithUncheckedParameters = [(commandsNotToSpellCheck ?: @[]) arrayByAddingObjectsFromArray:userCommandsNotToSpellCheck ?: @[]];
    }
    TSSyntaxTeXScanner *scanner = [[TSSyntaxTeXScanner alloc] initWithOptions:options];
    TSSyntaxHighlighter *highlighter = [[TSSyntaxHighlighter alloc] initWithTextView:aTextView scanner:scanner scheme:self.syntaxColorScheme];
    [highlighter applyTokensInRange:colorRange];
    
    // Now we color the background of the active line
    [self doEntryLineAndCursorColoring: (NSTextView *)aTextView];
}




// Load the color definitions from the config system
- (void)setupColors
{
    /*
	CGFloat		r, g, b;
	NSColor		*color;

	//
	// Free the old text attributes
	//
	// [regularColorAttribute release];
	// [commandColorAttribute release];
	// [commentColorAttribute release];
	// [markerColorAttribute release];
	// [indexColorAttribute release];

	//
	// Setup the new ones. Note that only color and underline attributes are supported!
	//
	r = [SUD floatForKey:foreground_RKey];
	g = [SUD floatForKey:foreground_GKey];
	b = [SUD floatForKey:foreground_BKey];
	color = [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
	self.regularColorAttribute = [[NSDictionary alloc] initWithObjectsAndKeys:color, NSForegroundColorAttributeName, nil];

	r = [SUD floatForKey:commandredKey];
	g = [SUD floatForKey:commandgreenKey];
	b = [SUD floatForKey:commandblueKey];
	color = [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
	self.commandColorAttribute = [[NSDictionary alloc] initWithObjectsAndKeys:color, NSForegroundColorAttributeName, nil];

	r = [SUD floatForKey:commentredKey];
	g = [SUD floatForKey:commentgreenKey];
	b = [SUD floatForKey:commentblueKey];
	color = [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
	self.commentColorAttribute = [[NSDictionary alloc] initWithObjectsAndKeys:color, NSForegroundColorAttributeName, nil];

	r = [SUD floatForKey:markerredKey];
	g = [SUD floatForKey:markergreenKey];
	b = [SUD floatForKey:markerblueKey];
	color = [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
	self.markerColorAttribute = [[NSDictionary alloc] initWithObjectsAndKeys:color, NSForegroundColorAttributeName, nil];
	
	r = [SUD floatForKey:indexredKey];
	g = [SUD floatForKey:indexgreenKey];
	b = [SUD floatForKey:indexblueKey];
	color = [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
	self.indexColorAttribute = [[NSDictionary alloc] initWithObjectsAndKeys:color, NSForegroundColorAttributeName, nil];
    */
    
    [self colorizeVisibleAreaInTextView:textView1];
    [self colorizeVisibleAreaInTextView:textView2];
    
}

// This method is invoked when the syntax highlighting preferences are changed.
// It either colorizes the whole text or removes all the coloring.
- (void)reColor:(NSNotification *)notification
{
    
  	// if ([SUD boolForKey:SyntaxColoringEnabledKey]) {
    if (self.syntaxColor) {
		[self colorizeAll];
	} else {
		NSRange theRange;

		theRange.location = 0;
		theRange.length = [self.textStorage length];
		[[textView1 layoutManager] removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:theRange];
		[[textView2 layoutManager] removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:theRange];
		[[scrapTextView layoutManager] removeTemporaryAttribute:NSForegroundColorAttributeName
			forCharacterRange:NSMakeRange(0, scrapTextView.string.length)];
	}
}

// Recolor when scrolling takes place
- (void)viewBoundsDidChange:(NSNotification *)notification
{
    
	[self colorizeVisibleAreaInTextView:[[notification object] documentView]];
}

// Recolor when resizing
- (void)viewFrameDidChange:(NSNotification *)notification
{
    
   [self colorizeVisibleAreaInTextView:[notification object]];
}

// Recolor when typing / text is inserted...
- (void)textDidChange:(NSNotification *)aNotification
{
// FIXME: There's a bug (also present in stock 2.03) when working in split view mode:
// If (for example) the upper view is positioned at the start of the document; and the
// lower view is positioned at a part of the document which is e.g. in the middle of the
// document (and I am assuming here that the document is at least a couple 'windows' high).
// and you then insert (paste) text into the upper view, the lower view's content is
// being scrolled. So far so good. But if you repeatedly insert text into the upper view,
// the lower view isn't updated anymore!

//	[self colorizeAll];
	[self fixColor :colorStart :colorEnd];
	if (tagLine)
		[self setupTags];
	colorStart = 0;
	colorEnd = 0;
	tagLine = NO;
	// [self updateChangeCount: NSChangeDone];
}

- (void)colorizeAll
{
  
   
  // No syntax coloring if the file is not TeX, or if it is disabled
	// if (!fileIsTex || ![SUD boolForKey:SyntaxColoringEnabledKey])
    if (!fileIsTex || !self.syntaxColor)
		return;

	// Recolor the visible area only.
	[self colorizeVisibleAreaInTextView:textView1];
	[self colorizeVisibleAreaInTextView:textView2];
	[self colorizeExperimentSource];
}

// The characters visible in any text view, as -[TSTextView visibleCharacterRange]; the
// Experiment source is a plain text view.
static NSRange TSVisibleCharacterRange(NSTextView *textView)
{
    NSLayoutManager *layoutManager = textView.layoutManager;
    NSRect visibleRect = textView.enclosingScrollView.contentView.documentVisibleRect;
    NSRange glyphs = [layoutManager glyphRangeForBoundingRect:visibleRect inTextContainer:textView.textContainer];
    return [layoutManager characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
}

- (void) colorizeVisibleAreaInTextView:(NSTextView *)aTextView
{
    CGFloat editWidth;
    
    // Nov 5, 2024. Koch.
    // Warning: the next three lines and the value 60.0
    // are required to prevent a crash if the splitbar
    // is moved to the extreme left.
    
    // No syntax coloring if the file is not TeX, or if it is disabled
	// if (!fileIsTex || ![SUD boolForKey:SyntaxColoringEnabledKey])
     if (!fileIsTex || !self.syntaxColor)
		return;
    if ([self coloringWaitsForMarkedTextIn:aTextView])
        return;
    
    // Nov 5, 2024. Koch.
    // Warning: the next three lines and the value 60.0
    // are required to prevent a crash if the splitbar
    // is moved to the extreme left.
    
    // The width of the clip view, as -[TSTextView theViewWidth].
    editWidth = aTextView.enclosingScrollView.contentView.bounds.size.width;
    // NSLog(@"the width is %f", editWidth);
    
    if (editWidth > 60.0)

        [self colorizeText:aTextView range:TSVisibleCharacterRange(aTextView)];
}


// This is the main syntax coloring routine, used for everything except opening documents
- (void)fixColor: (NSUInteger)from : (NSUInteger)to
{
	NSRange			colorRange;
	NSUInteger		length;

	// No syntax coloring if the file is not TeX, or if it is disabled
	// if (!fileIsTex || ![SUD boolForKey:SyntaxColoringEnabledKey])
     if (!fileIsTex || !self.syntaxColor)
		return;

	length = [self.textStorage length];
	if (length == 0)
		return;

	// This is an attempt to be safe: we perform some clipping on the color range.
	// TODO: Consider replacing this by a NSAssert or so. It *shouldn't* happen, and if it
	// does anyway, then due to a bug in our code, which we'd like to know about so that we
	// can fix it... right?
	if (from >= length)
		from = length - 1;
	if (to > length)
		to = length;
	if (to < from)
		to = from;

	// A line break typed or pasted inside a line moves the rest of that line
	// onto a new line, just after the edit. Include the character after the
	// edit so that this line is colored again too; otherwise text split off
	// a comment line keeps the comment color.
	if (to < length)
		to = to + 1;

	colorRange.location = from;
	colorRange.length = to - from;
	
	// TODO: Consider intersecting the range with the visible range ...

	// Colorize the range
    [self colorizeText:textView1 range:colorRange];
	[self colorizeText:textView2 range:colorRange];
    
}

- (void)cursorMoved: (NSTextView *)aTextView
{
    [self doEntryLineAndCursorColoring: (NSTextView *)aTextView];
}
    

- (void)removeCurrentLineColor: (NSTextView *)aTextView
{
    NSLayoutManager *layoutManager;
    NSString        *textString;
    NSRange         fullRange;
    
    layoutManager = [aTextView layoutManager];
    textString = [aTextView string];
    fullRange.location = 0;
    fullRange.length = [textString length];
    [layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:fullRange];
}
    

- (void)doEntryLineAndCursorColoring: (NSTextView *)aTextView
    {
        // Now we color the background of the active line
        
        
        NSRange         mySelectedLineRange, currentLineRange, cursorRange;
        NSUInteger      startl, endl, theEnd;
        NSDictionary    *cursorAttribute;
        NSLayoutManager *layoutManager;
        NSString        *textString;
        BOOL            writeCursor;
        
        if (self.syntaxcolorEntry && ![self coloringWaitsForMarkedTextIn:aTextView])
        {
            layoutManager = [aTextView layoutManager];
            textString = [aTextView string];
            [layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:TSVisibleCharacterRange(aTextView)];

            mySelectedLineRange = [aTextView selectedRange];
            [textString getLineStart:&startl end:&endl contentsEnd:&theEnd forRange:mySelectedLineRange];
            currentLineRange.location = startl;
            currentLineRange.length = theEnd - startl;
            if (! self.blockCursor)
                [layoutManager addTemporaryAttributes:self.EntryColorAttribute forCharacterRange:currentLineRange];
            
            else
                
            {
                NSColor *cursorColor = [NSColor colorWithCalibratedRed: [SUD floatForKey:BlockCursorRKey]
                                                                 green: [SUD floatForKey:BlockCursorGKey] blue: [SUD floatForKey:BlockCursorBKey] alpha:1.0];
                BOOL goLeft;
                BOOL goCenter;
                BOOL twoCharacters;
                if ([SUD integerForKey:BlockWidthKey] == 0)
                    twoCharacters = NO;
                else
                    twoCharacters = YES;
                if ([SUD integerForKey:BlockSideKey] == 0)
                    goLeft = YES;
                else
                    goLeft = NO;
                if ([SUD integerForKey:BlockSideKey] == 1)
                    goCenter = YES;
                else
                    goCenter = NO;
                
                cursorAttribute = [[NSDictionary alloc] initWithObjectsAndKeys: cursorColor, NSBackgroundColorAttributeName, nil];
                cursorRange = [aTextView selectedRange];
                
                if (cursorRange.length == 0)
                {
                    if (goCenter) {
                        
                        cursorRange.length = 2;
                        cursorRange.location = cursorRange.location - 1;
                        if (cursorRange.location < startl)
                        {
                            cursorRange.location = cursorRange.location + 1;
                            cursorRange.length = cursorRange.length - 1;
                        }
                        if ((cursorRange.location) >= (theEnd - 1))
                        {
                            cursorRange.length = 1;
                        }
                        if ((cursorRange.location) >= (theEnd))
                        {
                            cursorRange.length = 0;
                        }
                         
                        [layoutManager addTemporaryAttributes:cursorAttribute forCharacterRange:cursorRange];
            
                        
                    }
                     
                    
                    else if (goLeft) {
                        if (twoCharacters)
                        {
                            
                            cursorRange.length = 2;
                            cursorRange.location = cursorRange.location - 2;
                            if (cursorRange.location < startl)
                            {
                                cursorRange.location = cursorRange.location + 1;
                                cursorRange.length = cursorRange.length - 1;
                            }
                            if (cursorRange.location < startl)
                            {
                                cursorRange.location = cursorRange.location + 1;
                                cursorRange.length = cursorRange.length - 1;
                            }
                            
                           
                            [layoutManager addTemporaryAttributes:cursorAttribute forCharacterRange:cursorRange];
                            
                        }
                        
                        else
                        {
                            cursorRange.length = 1;
                            cursorRange.location = cursorRange.location - 1;
                            if (cursorRange.location < startl)
                            {
                                cursorRange.location = cursorRange.location + 1;
                                cursorRange.length = cursorRange.length - 1;
                            }
                     
                            [layoutManager addTemporaryAttributes:cursorAttribute forCharacterRange:cursorRange];
                        }
                    }
                    else
                    {
                        if (twoCharacters)
                        {
                            writeCursor = YES;
                            cursorRange.length = 2;
                             if ((cursorRange.location + 1) >= (theEnd))
                            {
                                cursorRange.length = cursorRange.length - 1;
                            }
                            if (cursorRange.location >= theEnd)
                                writeCursor = NO;
                            if (writeCursor)
                                [layoutManager addTemporaryAttributes:cursorAttribute forCharacterRange:cursorRange];
                        }
                        else
                        {
                            writeCursor = YES;
                            cursorRange.length = 1;
                            // if ((cursorRange.location + 1) == endl)
                            if ((cursorRange.location) >= (theEnd))
                                writeCursor = NO;
                              //  cursorRange.length = 1;
                               // cursorRange.location = cursorRange.location - 1;
                             if (writeCursor)
                                [layoutManager addTemporaryAttributes:cursorAttribute forCharacterRange:cursorRange];
                        }
                    }
                    
                }
            }
        }
    }

@end
