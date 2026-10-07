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

@implementation TSLayoutManager
- (id)init
{
	self = [super init];
	unichar _tabCharacter0 = 0x2023;
	unichar _tabCharacter1 = 0x25B9;
//	unichar _tabCharacter2 = 0x21E5;
//	unichar _tabCharacter3 = 0x00AC;
	unichar _newLineCharacter0 = 0x21B5;
	unichar _newLineCharacter1 = 0x00B6;
//	unichar _newLineCharacter2 = 0x21A9;
//	unichar _newLineCharacter3 = 0x23CE;
	unichar _fullwidthSpaceCharacter0 = 0x25A1;
	unichar _fullwidthSpaceCharacter1 = 0x25A0;
//	unichar _fullwidthSpaceCharacter2 = 0x2022;
//	unichar _fullwidthSpaceCharacter3 = 0x22A0;
	unichar _spaceCharacter0 = 0x2423;
	unichar _spaceCharacter1 = 0x00B7;
//	unichar _spaceCharacter2 = 0x02D0;
//	unichar _spaceCharacter3 = 0x00B0;
	self.tabCharacters = [NSArray arrayWithObjects:
					 [NSString stringWithCharacters:&_tabCharacter0 length:1],
					 [NSString stringWithCharacters:&_tabCharacter1 length:1],
//					 [NSString stringWithCharacters:&_tabCharacter2 length:1],
//					 [NSString stringWithCharacters:&_tabCharacter3 length:1],
					 nil
                    ];
	self.nextLineCharacters = [NSArray arrayWithObjects:
					 [NSString stringWithCharacters:&_newLineCharacter0 length:1],
					 [NSString stringWithCharacters:&_newLineCharacter1 length:1],
//					 [NSString stringWithCharacters:&_newLineCharacter2 length:1],
//					 [NSString stringWithCharacters:&_newLineCharacter3 length:1],
					 nil
                    ];
    self.fullwidthSpaceCharacters = [NSArray arrayWithObjects:
								[NSString stringWithCharacters:&_fullwidthSpaceCharacter0 length:1],
								[NSString stringWithCharacters:&_fullwidthSpaceCharacter1 length:1],
//								[NSString stringWithCharacters:&_fullwidthSpaceCharacter2 length:1],
//								[NSString stringWithCharacters:&_fullwidthSpaceCharacter3 length:1],
								nil
                                ];
	self.spaceCharacters = [NSArray arrayWithObjects:
					   [NSString stringWithCharacters:&_spaceCharacter0 length:1],
					   [NSString stringWithCharacters:&_spaceCharacter1 length:1],
//					   [NSString stringWithCharacters:&_spaceCharacter2 length:1],
//					   [NSString stringWithCharacters:&_spaceCharacter3 length:1],
					   nil
                        ];
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

	NSString *tabCharacter = [self.tabCharacters objectAtIndex:[SUD integerForKey:TabCharacterKindKey]];
    NSString *nextLineCharacter = [self.nextLineCharacters objectAtIndex:[SUD integerForKey:NewLineCharacterKindKey]];
    NSString *fullwidthSpaceCharacter = [self.fullwidthSpaceCharacters objectAtIndex:[SUD integerForKey:FullwidthSpaceCharacterKindKey]];
    NSString *spaceCharacter = [self.spaceCharacters objectAtIndex:[SUD integerForKey:SpaceCharacterKindKey]];

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
