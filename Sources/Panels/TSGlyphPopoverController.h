/*
 ==============================================================================
 TSGlyphPopoverController
 Created on 2014-08-24 by Yusuke Terada

 TSGlyphPopoverController is based on CEGlyphPopoverController.
 
 CotEditor
 http://coteditor.github.io
 
 Created on 2014-05-01 by 1024jp
 encoding="UTF-8"
 ------------------------------------------------------------------------------
 
 © 2014 CotEditor Project
 
 This program is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License as published by the Free Software
 Foundation; either version 2 of the License, or (at your option) any later
 version.
 
 This program is distributed in the hope that it will be useful, but WITHOUT
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License along with
 this program; if not, write to the Free Software Foundation, Inc., 59 Temple
 Place - Suite 330, Boston, MA  02111-1307, USA.
 
 ==============================================================================
 */

#import <Cocoa/Cocoa.h>
#import "NSString-Extras.h"


NS_ASSUME_NONNULL_BEGIN

@interface TSGlyphPopoverController : NSViewController
/// Character Info for the characters of `ranges` in `text` (the selected ranges of a text view), counted as the
/// status bar counts the selection, with the code points of every range; nil when the ranges hold no character.
- (nullable instancetype)initWithText:(NSString *)text ranges:(NSArray<NSValue *> *)ranges;
/// Character Info for the characters of `range` in `text`.
- (nullable instancetype)initWithText:(NSString *)text range:(NSRange)range;
/// Character Info for the whole string.
- (nullable instancetype)initWithCharacter:(NSString *)singleString;
- (void)showPopoverRelativeToRect:(NSRect)positioningRect ofView:(NSView *)parentView;
@end

NS_ASSUME_NONNULL_END
