/*
 TSLayoutManager.m
 Created by Terada on Feb 2011.
 
 ------------
 TSLayoutManager is based on CotEditor - CELayoutManager (written by nakamuxu – http://www.aynimac.com/)
 CotEditor Copyright (c) 2004-2007 nakamuxu, All rights reserved.
 CotEditor is released under GNU General Public License, http://www.gnu.org/copyleft/gpl.html
 arranged by Terada, Feb 2011.
 -------------------------------------------------

 ------------
 CELayoutManager is based on Smultron - SMLLayoutManager (written by Peter Borg – http://smultron.sourceforge.net)
 Smultron Copyright (c) 2004 Peter Borg, All rights reserved.
 Smultron is released under GNU General Public License, http://www.gnu.org/copyleft/gpl.html
 arranged by nakamuxu, Jan 2005.
 -------------------------------------------------
 
 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 2
 of the License, or (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA. 
 
 =================================================
*/

#import "globals.h"
#import "TSLayoutManager.h"
#import "TSInvisibleCharacters.h"

@implementation TSLayoutManager
- (id)init
{
	self = [super init];
    self.tabCharacters = TSInvisibleMarkers(TabCharacterKindKey);
    self.nextLineCharacters = TSInvisibleMarkers(NewLineCharacterKindKey);
    self.fullwidthSpaceCharacters = TSInvisibleMarkers(FullwidthSpaceCharacterKindKey);
    self.spaceCharacters = TSInvisibleMarkers(SpaceCharacterKindKey);
	return self;
}

- (void)setInvisibleCharactersEnabled:(BOOL)enabled
{
	invisibleCharactersShowing = enabled;
}

// changed by Terada (from this line): Align the marker baseline with the text baseline.
- (void)drawInvisibleCharacter:(NSString *)marker
               atGlyphIndex:(NSUInteger)glyphIndex
            containerOrigin:(NSPoint)containerOrigin
                 attributes:(NSDictionary *)attributes
                      cache:(NSMutableDictionary *)cache
{
    NSArray *key = @[marker, attributes[NSFontAttributeName]];
    NSTextStorage *markerStorage = cache[key];
    if (markerStorage == nil) {
        markerStorage = [[NSTextStorage alloc] initWithString:marker attributes:attributes];
        NSLayoutManager *markerLayout = [NSLayoutManager new];
        NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(10000, 10000)];
        container.lineFragmentPadding = 0;
        [markerStorage addLayoutManager:markerLayout];
        [markerLayout addTextContainer:container];
        [markerLayout ensureLayoutForTextContainer:container];
        cache[key] = markerStorage;
    }
    NSLayoutManager *markerLayout = markerStorage.layoutManagers.firstObject;
    NSPoint textBaseline = [self locationForGlyphAtIndex:glyphIndex];
    NSRect textLine = [self lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:NULL];
    NSPoint markerBaseline = [markerLayout locationForGlyphAtIndex:0];
    NSRect markerLine = [markerLayout lineFragmentRectForGlyphAtIndex:0 effectiveRange:NULL];
    NSPoint origin = NSMakePoint(containerOrigin.x + textLine.origin.x + textBaseline.x
                                - markerLine.origin.x - markerBaseline.x,
                                containerOrigin.y + textLine.origin.y + textBaseline.y
                                - markerLine.origin.y - markerBaseline.y);
    [markerLayout drawGlyphsForGlyphRange:NSMakeRange(0, markerLayout.numberOfGlyphs) atPoint:origin];
}
// changed by Terada (until this line)

- (void)drawGlyphsForGlyphRange:(NSRange)inGlyphRange atPoint:(NSPoint)inContainerOrigin
{
    NSString *theCompleteStr = [[self textStorage] string];
    NSUInteger theLengthToRedraw = NSMaxRange(inGlyphRange);
    NSUInteger theGlyphIndex, theCharIndex = 0;
    unichar theCharacter;
    // changed by Terada: Follow inline font changes and reuse marker layouts during drawing.
    NSMutableDictionary *markerCache = [NSMutableDictionary dictionary];

	BOOL showTabCharacter = (invisibleCharactersShowing && [SUD boolForKey:showTabCharacterKey]);
	BOOL showNewLineCharacter = (invisibleCharactersShowing && [SUD boolForKey:showNewLineCharacterKey]);
	BOOL showFullwidthSpaceCharacter = (invisibleCharactersShowing && [SUD boolForKey:showFullwidthSpaceCharacterKey]);
	BOOL showSpaceCharacter = (invisibleCharactersShowing && [SUD boolForKey:showSpaceCharacterKey]);

	NSString *tabCharacter = TSInvisibleMarker(self.tabCharacters, [SUD integerForKey:TabCharacterKindKey]);
    NSString *nextLineCharacter = TSInvisibleMarker(self.nextLineCharacters, [SUD integerForKey:NewLineCharacterKindKey]);
    NSString *fullwidthSpaceCharacter = TSInvisibleMarker(self.fullwidthSpaceCharacters, [SUD integerForKey:FullwidthSpaceCharacterKindKey]);
    NSString *spaceCharacter = TSInvisibleMarker(self.spaceCharacters, [SUD integerForKey:SpaceCharacterKindKey]);

	for (theGlyphIndex = inGlyphRange.location; theGlyphIndex < theLengthToRedraw; theGlyphIndex++) {
		theCharIndex = [self characterIndexForGlyphAtIndex:theGlyphIndex];
		theCharacter = [theCompleteStr characterAtIndex:theCharIndex];
		
		NSString *marker = nil;
		if (theCharacter == '\t' && showTabCharacter ) {
            marker = tabCharacter;
		} else if (theCharacter == '\n' && showNewLineCharacter) {
            marker = nextLineCharacter;
		} else if (theCharacter == 0x3000 && showFullwidthSpaceCharacter) { // Fullwidth-space (JP)
            marker = fullwidthSpaceCharacter;
		} else if (theCharacter == ' ' && showSpaceCharacter) {
            marker = spaceCharacter;
        }
        // added by Terada: Use the drawing origin and text baseline instead of a fixed offset.
        if (marker != nil) {
            NSFont *font = [self.textStorage attribute:NSFontAttributeName atIndex:theCharIndex effectiveRange:NULL];
            if (font == nil) font = [NSFont userFixedPitchFontOfSize:12];
            NSDictionary *attributes = @{NSFontAttributeName: font,
                                         NSForegroundColorAttributeName: InvisibleColor ?: NSColor.textColor};
            [self drawInvisibleCharacter:marker atGlyphIndex:theGlyphIndex
                         containerOrigin:inContainerOrigin attributes:attributes cache:markerCache];
        }
	}
	[super drawGlyphsForGlyphRange:inGlyphRange atPoint:inContainerOrigin];
}

@end
