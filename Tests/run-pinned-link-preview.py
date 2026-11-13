#!/usr/bin/env python3
"""Exercise production link-popup event handling without showing windows or saving settings."""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['move-dismisses', 'stale-timer', 'other-window', 'cleanup-state', 'ordinary-escape', 'modified-escape', 'click-cleanup', 'initialize-cleanup',
                                           'unpinned-interactive', 'pinned-transparent', 'scroll-chains', 'scroll-moves-frame', 'option-not-forwarded', 'kill-leaves-view', 'cursor-overridden', 'resize-scales',
                                           'click-kills-pin', 'cleanup-in-click-kills-pin', 'cursor-not-restored', 'hand-selects', 'no-selection', 'move-confined', 'copy-ignores-popup', 'click-keeps-selection', 'toggle-keeps-popup', 'link-popups-per-view', 'reads-settings-again',
                                           'tool-change-kills-pin', 'flag-not-restored', 'click-keeps-focus',
                                           'no-page-label', 'label-unscaled', 'tooltip-kept', 'tooltip-always-hidden',
                                           'tooltip-trusts-data', 'label-from-index',
                                           'magnifier-kills-pin', 'switch-kills-pin', 'keep-marquee', 'contains-unpinned', 'contains-hidden-part',
                                           'detach-keeps-state', 'attach-keeps-old-tool', 'attach-replaces-pin', 'not-kept-in-view',
                                           'window-magnifier-bypass', 'window-resign-kills-pin', 'window-split-kills-pin', 'window-unsplit-drops-pin',
                                           'window-layout-not-kept', 'drag-cursor-stays', 'hidden-part-cursor', 'no-exit-tracking', 'exit-ignored',
                                           'outside-always-arrow', 'visible-beyond-bounds', 'escape-ignores-active-part',
                                           'popup-side-fitted', 'popup-side-always-kept', 'no-next-page', 'selection-first-page',
                                           'control-ignored-when-off', 'control-ignored-when-on', 'command-still-shows', 'control-popup-stays',
                                           'timer-ignores-release', 'tooltip-ignores-control', 'tooltip-back-under-popup',
                                           'pinned-blocks-hover', 'pin-keeps-old', 'over-pin-keeps-hover', 'pin-times-out',
                                           'escape-falls-to-other-part', 'escape-closes-hover',
                                           'link-keeps-pin', 'outline-keeps-pin', 'back-keeps-pin', 'forward-keeps-pin', 'page-number-keeps-pin',
                                           'last-page-keeps-pin', 'sync-keeps-pin', 'zoom-kills-pin', 'next-page-kills-pin',
                                           'empty-outline-kills-pin', 'stuck-back-kills-pin'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
def method(signature):
    start = source.rindex(signature)
    body = source[start:source.index('\n}', start) + 2]
    if args.mutation == 'click-cleanup' and signature == '- (void) mouseDown:':
        body = body.replace('if (self.handlingLink) [self killTransientLinkPreview];', '')
    if args.mutation == 'click-kills-pin' and signature == '- (void) mouseDown:':
        body = body.replace('if (self.handlingLink) [self killTransientLinkPreview];', '[self doKillPopup];')
    if args.mutation == 'initialize-cleanup' and signature == '- (void) initializeDisplay':
        body = body.replace('if (self.handlingLink || pinnedLinkPreview) [self doKillPopup];', '')
    return body
methods = '\n'.join(method(signature) for signature in (
    '- (void) increaseTimerNumber', '- (void) changeLinkPopups', '- (void) mouseMoved:',
    '- (void)handleLink:', '- (NSEvent *)handleLinkPreviewEvent:',
    '- (void)observeLinkPreviewEvents', '- (void)linkPreviewWindowWillClose:',
    '- (void)viewWillMoveToWindow:', '- (void)doKillPopup', '- (void)killPopup:',
    '- (void)setDocument:(PDFDocument *)document', '- (void)cleanupMarquee:',
    '- (void) mouseDown:', '- (void) mouseDownKeepingPinnedLinkPreview:', '- (void) initializeDisplay',
    '- (NSCursor *) cursorForToolWithEvent:', '- (void) showToolCursorOutsideLinkPreviewWithEvent:', '- (void) copy:', '- (BOOL) validateMenuItem:',
    '- (void) keepingPinnedLinkPreview:', '- (void) changeMouseMode:',
    '- (void) linkPopupsChanged', '- (BOOL) skipLinks', '- (void) setSkipLinks:', '- (BOOL) showsLinkPopupsWithModifierFlags:',
    '+ (void)initialize', '- (BOOL)showsLinkPreviewForAnnotation:',
    '- (void) fancyMouseDown:', '- (void) fancyMouseDownKeepingPinnedLinkPreview:',
    '- (void)cleanupMarqueeKeepingPinnedLinkPreview', '- (BOOL)hasPinnedLinkPreview',
    '- (BOOL)pinnedLinkPreviewContainsWindowPoint:', '- (TSLinkPreviewView *)detachPinnedLinkPreviewWithWindowFrame:',
    '- (void)attachPinnedLinkPreview:', '- (void)keepPinnedLinkPreviewInView',
    '- (BOOL)isActivePreviewPart', '- (void)pinLinkPreview', '- (void)killTransientLinkPreview',
    '- (void)closePinnedLinkPreview',
    # The ways to go to another place, which close the pinned popup, and the ways that keep it (#35).
    '- (void) goBack:', '- (void) goForward:', '- (IBAction) takeDestinationFromOutline:', '- (void)setIndexForMark:',
    '- (void) mouseUp:', '- (PDFDestination *)internalLinkDestinationAtPoint:', '- (void) firstPage:', '- (void) lastPage:',
    '- (void) previousPage:', '- (void) nextPage:', '- (void) changeScale:', '- (void) goToKitPageNumber:'))
view_mutations = {
    'magnifier-kills-pin': ('[self keepingPinnedLinkPreview:^{ [self fancyMouseDownKeepingPinnedLinkPreview: theEvent]; }];',
                            '[self fancyMouseDownKeepingPinnedLinkPreview: theEvent];'),
    'switch-kills-pin': ('    [self keepingPinnedLinkPreview:^{ [self cleanupMarquee: YES]; }];\n}\n- (BOOL)hasPinnedLinkPreview',
                         '    [self cleanupMarquee: YES];\n}\n- (BOOL)hasPinnedLinkPreview'),
    'keep-marquee': ('    [self keepingPinnedLinkPreview:^{ [self cleanupMarquee: YES]; }];\n}\n- (BOOL)hasPinnedLinkPreview',
                     '    [self keepingPinnedLinkPreview:^{ }];\n}\n- (BOOL)hasPinnedLinkPreview'),
    'contains-unpinned': ('    return pinnedLinkPreview.superview != nil;',
                          '    return (pinnedLinkPreview ?: linkPreview).superview != nil;'),
    'contains-hidden-part': ('    return NSPointInRect(local, documentView.visibleRect) && NSPointInRect(local, pinnedLinkPreview.frame);',
                             '    return NSPointInRect(local, pinnedLinkPreview.frame);'),
    'detach-keeps-state': ('    [preview removeFromSuperview];\n    pinnedLinkPreview = nil;\n    [self doKillPopup];\n    return preview;',
                           '    [preview removeFromSuperview];\n    return preview;'),
    'attach-keeps-old-tool': ('        return view && view->mouseMode == NEW_MOUSE_MODE_SCROLL;\n    };\n    [documentView addSubview:pinnedLinkPreview];',
                              '        return NO;\n    };\n    [documentView addSubview:pinnedLinkPreview];'),
    'attach-replaces-pin': ('    if (!preview || !documentView || [self hasPinnedLinkPreview]) return;', '    if (!preview || !documentView) return;'),
    'not-kept-in-view': ('    if ([self hasPinnedLinkPreview]) [pinnedLinkPreview keepInView];', ''),
    'escape-ignores-active-part': ('        if (![self isActivePreviewPart])\n            return event;\n', ''),
    # The behavior before: with none in the active part, Escape went to the other part (#14).
    'escape-falls-to-other-part': ('        if (![self isActivePreviewPart])\n            return event;\n',
                                   '        if (![self isActivePreviewPart] && [(MyPDFKitView *)self.myPDFWindow.activeView hasPinnedLinkPreview])\n            return event;\n'),
    'escape-closes-hover': ('        [self closePinnedLinkPreview];\n        return nil;\n', '        [self doKillPopup];\n        return nil;\n'),
    # The behavior before: a pinned popup kept other links from showing theirs.
    'pinned-blocks-hover': ('if (self.handlingLink > 0 || [self showsLinkPopupsWithModifierFlags: [theEvent modifierFlags]])',
                            'if (!pinnedLinkPreview && (self.handlingLink > 0 || [self showsLinkPopupsWithModifierFlags: [theEvent modifierFlags]]))'),
    'pin-keeps-old': ('    if (!linkPreview) return;\n    [pinnedLinkPreview removeFromSuperview];\n', '    if (!linkPreview) return;\n'),
    'over-pin-keeps-hover': ('        if (self.handlingLink) [self killTransientLinkPreview];\n        [previewCursor set];', '        [previewCursor set];'),
    'pin-times-out': ('    pinnedLinkPreview.pinned = YES;\n    [self increaseTimerNumber];\n', '    pinnedLinkPreview.pinned = YES;\n'),
    'link-keeps-pin': ('\t\t\tif ([self internalLinkDestinationAtPoint: [self convertPoint: [theEvent locationInWindow] fromView: nil]])\n\t\t\t\t[self closePinnedLinkPreview];\n', ''),
    'outline-keeps-pin': ('\tif (destination)\n\t\t[self closePinnedLinkPreview];\n', ''),
    'empty-outline-kills-pin': ('\tif (destination)\n\t\t[self closePinnedLinkPreview];\n', '\t[self closePinnedLinkPreview];\n'),
    'back-keeps-pin': ('\tif ([self canGoBack])\n\t\t[self closePinnedLinkPreview];\n', ''),
    'stuck-back-kills-pin': ('\tif ([self canGoForward])\n\t\t[self closePinnedLinkPreview];\n', '\t[self closePinnedLinkPreview];\n'),
    'forward-keeps-pin': ('\tif ([self canGoForward])\n\t\t[self closePinnedLinkPreview];\n', ''),
    'page-number-keeps-pin': ('\t// A page number goes to another place: the pinned popup of this part closes (#35).\n\t[self closePinnedLinkPreview];\n', ''),
    'last-page-keeps-pin': ('- (void) lastPage: (id)sender\n{\n\t[self closePinnedLinkPreview];\n', '- (void) lastPage: (id)sender\n{\n'),
    'sync-keeps-pin': ('\t[self closePinnedLinkPreview];\n\tpageIndexForMark = idx;', '\tpageIndexForMark = idx;'),
    'zoom-kills-pin': ('\t// A pinned popup stays, growing and shrinking with the page it is on (#35).\n\t[self cleanupMarqueeKeepingPinnedLinkPreview];',
                       '\t[self cleanupMarquee: YES];'),
    'next-page-kills-pin': ('\t\t[self cleanupMarqueeKeepingPinnedLinkPreview];\n\t[self stepPageForward:YES sender:sender];', '\t\t[self cleanupMarquee: YES];\n\t[self stepPageForward:YES sender:sender];'),
    'popup-side-fitted': ('            BOOL keepSide = displayMode == kPDFDisplaySinglePageContinuous ||\n                            displayMode == kPDFDisplayTwoUpContinuous;\n',
                          '            BOOL keepSide = displayMode != displayMode;\n'),
    'no-next-page': ('            if (keepSide && linkedIndex != NSNotFound', '            if (NO && linkedIndex != NSNotFound'),
    'popup-side-always-kept': ('            BOOL keepSide = displayMode == kPDFDisplaySinglePageContinuous ||\n                            displayMode == kPDFDisplayTwoUpContinuous;\n',
                               '            BOOL keepSide = displayMode == displayMode;\n'),
}
if args.mutation in view_mutations:
    old, new = view_mutations[args.mutation]
    assert methods.count(old) == 1, args.mutation
    methods = methods.replace(old, new)
control_mutations = {
    'control-ignored-when-off': ('    return !self.skipLinks != ((flags & NSEventModifierFlagControl) != 0);',
                                 '    return !self.skipLinks && (flags & NSEventModifierFlagControl) == 0;'),
    'control-ignored-when-on': ('    return !self.skipLinks != ((flags & NSEventModifierFlagControl) != 0);',
                                '    return !self.skipLinks || (flags & NSEventModifierFlagControl) != 0;'),
    'command-still-shows': ('    return !self.skipLinks != ((flags & NSEventModifierFlagControl) != 0);',
                            '    return (!self.skipLinks != ((flags & NSEventModifierFlagControl) != 0)) || (flags & NSEventModifierFlagCommand) != 0;'),
    'control-popup-stays': ('if (self.handlingLink > 0 || [self showsLinkPopupsWithModifierFlags: [theEvent modifierFlags]])',
                            'if ([self showsLinkPopupsWithModifierFlags: [theEvent modifierFlags]])'),
    'timer-ignores-release': ('    if (![self showsLinkPopupsWithModifierFlags: modifiers]) {',
                              '    if (![self showsLinkPopupsWithModifierFlags: [(NSEvent *)theTimer.userInfo[2] modifierFlags]]) {'),
    'tooltip-ignores-control': ('    BOOL showsPopups = [self showsLinkPopupsWithModifierFlags: [NSEvent modifierFlags]] ||',
                                '    BOOL showsPopups = !self.skipLinks ||'),
    'tooltip-back-under-popup': ('                       self.handlingLink != 0;', '                       NO;'),
}
if args.mutation in control_mutations:
    old, new = control_mutations[args.mutation]
    assert methods.count(old) == 1, args.mutation
    methods = methods.replace(old, new)
if args.mutation == 'move-dismisses':
    old = '            [self killTransientLinkPreview]; // sets handlingLink to 0'
    assert methods.count(old) == 1
    methods = methods.replace(old, '            [self doKillPopup]; // sets handlingLink to 0')
elif args.mutation == 'stale-timer':
    methods = methods.replace('aTimerNumber != self.timerNumber || ', '')
elif args.mutation == 'other-window':
    old = '    if (!self.window || event.window != self.window)\n        return event;'
    assert methods.count(old) == 1
    methods = methods.replace(old, '    if (!self.window)\n        return event;')
elif args.mutation == 'cleanup-state':
    old = '    if (!keepsPinnedLinkPreview && (self.handlingLink || pinnedLinkPreview)) { [self doKillPopup]; return; }\n'
    assert methods.count(old) == 1
    methods = methods.replace(old, '')
elif args.mutation == 'ordinary-escape':
    old = 'if (pinnedLinkPreview && event.type == NSEventTypeKeyDown'
    assert methods.count(old) == 1
    methods = methods.replace(old, 'if ((pinnedLinkPreview || linkPreview) && event.type == NSEventTypeKeyDown')
elif args.mutation == 'option-not-forwarded':
    old = '        && self.handlingLink == 2 && linkPreview)\n        [self pinLinkPreview];'
    assert methods.count(old) == 1
    methods = methods.replace(old, '        && self.handlingLink == 2 && linkPreview)\n        ;')
elif args.mutation == 'kill-leaves-view':
    old = '    [pinnedLinkPreview removeFromSuperview];\n    pinnedLinkPreview = nil;\n    [self observeLinkPreviewEvents];'
    assert methods.count(old) == 1
    methods = methods.replace(old, '    pinnedLinkPreview = nil;\n    [self observeLinkPreviewEvents];')
elif args.mutation == 'cursor-overridden':
    methods = methods.replace('        [previewCursor set];\n        showsLinkPreviewCursor = YES;\n        return;', '        [previewCursor set];\n        showsLinkPreviewCursor = YES;')
elif args.mutation == 'cleanup-in-click-kills-pin':
    old = 'if (!keepsPinnedLinkPreview && (self.handlingLink || pinnedLinkPreview))'
    assert methods.count(old) == 1
    methods = methods.replace(old, 'if (self.handlingLink || pinnedLinkPreview)')
elif args.mutation == 'tool-change-kills-pin':
    methods = methods.replace('[self keepingPinnedLinkPreview:^{ [self cleanupMarquee: YES]; }];', '[self cleanupMarquee: YES];')
elif args.mutation == 'flag-not-restored':
    methods = methods.replace('    @finally {\n        keepsPinnedLinkPreview = previous;\n    }', '    @finally {\n    }')
elif args.mutation == 'cursor-not-restored':
    assert methods.count('    [[self cursorForToolWithEvent: theEvent] set];\n') == 1
    methods = methods.replace('    [[self cursorForToolWithEvent: theEvent] set];\n', '')
elif args.mutation == 'label-from-index':
    methods = methods.replace('if (linkedPage.label.length)', 'if ((linkedPage = [linkedPage.document pageAtIndex:[linkedPage.document indexForPage:linkedPage]]).label.length)').replace(
        '@"Page label in the corner of a link popup; %@ is the page label given in the PDF"), linkedPage.label]',
        '@"Page label in the corner of a link popup; %@ is the page label given in the PDF"), @([linkedPage.document indexForPage:linkedPage] + 1).stringValue]')
elif args.mutation == 'tooltip-always-hidden':
    old = 'return showsPopups && mouseMode != NEW_MOUSE_MODE_SELECT_PDF &&'
    assert methods.count(old) == 1
    methods = methods.replace(old, 'return')
elif args.mutation == 'copy-ignores-popup':
    methods = methods.replace('\tif (previewText.length) {', '\tif (NO) {')
elif args.mutation == 'modified-escape':
    methods = methods.replace('&& !(event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl\n                                    | NSEventModifierFlagOption | NSEventModifierFlagShift))', '')
preview_source = (root / 'Sources/Preview/TSLinkPreviewView.m').read_text()
preview_mutations = {
    'unpinned-interactive': ('return self.pinned ? [super hitTest:point] : nil;', 'return [super hitTest:point];'),
    'pinned-transparent': ('return self.pinned ? [super hitTest:point] : nil;', 'return nil;'),
    'scroll-moves-frame': ('    [self setNeedsDisplay:YES];\n}\n\n@end', '    self.frame = NSOffsetRect(self.frame, 0.1, 0);\n    [self setNeedsDisplay:YES];\n}\n\n@end'),
    'scroll-chains': ('    [self setNeedsDisplay:YES];\n}\n\n@end', '    [self setNeedsDisplay:YES];\n    [super scrollWheel:event];\n}\n\n@end'),
    'hand-selects': ('return _pageCount && !(self.usesHandTool && self.usesHandTool());', 'return _pageCount != 0;'),
    'no-selection': ('} else if ([self selectsText] && [self isTextOnPage:page atPoint:pagePoint]) {', '} else if (NO) {'),
    'move-confined': ('frame = TSLinkPreviewMove(_startFrame, delta, [self availableRect], [self keptSizeForFrame:frame], flipped);',
                      'frame = TSLinkPreviewMove(_startFrame, delta, [self availableRect], _startFrame.size, flipped);'),
    'click-keeps-selection': ('NSEqualRects(self.frame, _startFrame)) self.selection = nil;', 'NO) self.selection = nil;'),
    'click-keeps-focus': ('    if (owner && self.window.firstResponder != owner) [self.window makeFirstResponder:owner];\n', ''),
    'no-page-label': ('    if (!self.pageLabel.length) return;\n', '    return;\n'),
    'label-unscaled': ('[NSFont boldSystemFontOfSize:TSLinkPreviewLabelFontSize * unit]', '[NSFont boldSystemFontOfSize:TSLinkPreviewLabelFontSize]'),
    'tooltip-kept': ('if (annotation && (__bridge void *)annotation == data && [pdfView showsLinkPreviewForAnnotation:annotation])', 'if (NO)'),
    'tooltip-trusts-data': ('if (annotation && (__bridge void *)annotation == data && [pdfView showsLinkPreviewForAnnotation:annotation])',
                            'if (annotation && [pdfView showsLinkPreviewForAnnotation:annotation])'),
    'resize-scales': ('                            [self availableRect], _pageSize, flipped, &frame, &source);',
                      '                            [self availableRect], _pageSize, flipped, &frame, &source);\n        source = _startSource;'),
    'drag-cursor-stays': ('    else [self showCursorOutsideWithEvent:event];\n', ''),
    'hidden-part-cursor': (' || !NSPointInRect(point, self.superview.visibleRect)) return nil;', ') return nil;'),
    'no-exit-tracking': ('        [self addTrackingArea:', '        if (NO) [self addTrackingArea:'),
    'exit-ignored': ('    [self showCursorOutsideWithEvent:event];\n}\n\n- (void)mouseDown:', '}\n\n- (void)mouseDown:'),
    'outside-always-arrow': ('    if (owner && owner.window == event.window', '    if (NO && owner && owner.window == event.window'),
    'visible-beyond-bounds': ('NSIntersectionRect(owner.bounds, owner.visibleRect)', 'owner.visibleRect'),
    'selection-first-page': ('        if (d < distance) { distance = d; nearest = i; }\n', ''),
}
if args.mutation in preview_mutations:
    old, new = preview_mutations[args.mutation]
    assert preview_source.count(old) == 1, args.mutation
    preview_source = preview_source.replace(old, new)
document_source = (root / 'Sources/Document/TSDocument.m').read_text(encoding='latin1')
start = document_source.index('- (void)toggleLinkPopups:(id)sender')
document_methods = document_source[start:document_source.index('\n}', start) + 2]
if args.mutation == 'toggle-keeps-popup':
    document_methods = document_methods.replace('    [self.myPDFKitView linkPopupsChanged];\n', '')
if args.mutation == 'link-popups-per-view':
    methods = methods.replace('    return document ? !document.linkPopups : _skipLinks;', '    return _skipLinks;').replace(
        '    if (document)\n        document.linkPopups = !skip;\n    else\n        _skipLinks = skip;', '    _skipLinks = skip;')
if args.mutation == 'reads-settings-again':
    methods = methods.replace('    if (!self.myDocument)\n        self.skipLinks = (! [SUD boolForKey: LinkPopupsKey]);', '    self.skipLinks = (! [SUD boolForKey: LinkPopupsKey]);')
# The preview windows hand clicks in a pinned popup to it, keep pinned popups when another
# window becomes main, and keep or move them when the window is split or unsplit (#14).
preview_window = (root / 'Sources/Windows/TSPreviewWindow.m').read_text(encoding='latin1')
split_window = (root / 'Sources/Windows/TSFullSplitWindow.m').read_text(encoding='latin1')
window_mutations = {
    'window-magnifier-bypass': ('preview', '          if (inPDF && ! [(MyPDFKitView *)aView pinnedLinkPreviewContainsWindowPoint: thePoint])', '          if (inPDF)'),
    'window-resign-kills-pin': ('preview', '    [(MyPDFKitView *)self.myPDFKitView cleanupMarqueeKeepingPinnedLinkPreview];\n    [(MyPDFKitView *)self.myPDFKitView2 cleanupMarqueeKeepingPinnedLinkPreview];\n    [super resignMainWindow];',
                                '    [(MyPDFKitView *)self.myPDFKitView cleanupMarquee: YES];\n    [(MyPDFKitView *)self.myPDFKitView2 cleanupMarquee: YES];\n    [super resignMainWindow];'),
    'window-split-kills-pin': ('preview', '    [(MyPDFKitView *)self.myPDFKitView cleanupMarqueeKeepingPinnedLinkPreview];\n    [(MyPDFKitView *)self.myPDFKitView2 cleanupMarqueeKeepingPinnedLinkPreview];\n    \n',
                               '    [(MyPDFKitView *)self.myPDFKitView cleanupMarquee: YES];\n    [(MyPDFKitView *)self.myPDFKitView2 cleanupMarquee: YES];\n    \n'),
    'window-unsplit-drops-pin': ('preview', '        [(MyPDFKitView *)self.myPDFKitView attachPinnedLinkPreview: movedPreview windowFrame: movedPreviewFrame];', '        ;'),
    'window-layout-not-kept': ('preview', 'windowFrame: movedPreviewFrame];\n    [self keepPinnedLinkPreviewsInView];\n}',
                               'windowFrame: movedPreviewFrame];\n}'),
}
if args.mutation in window_mutations:
    which, old, new = window_mutations[args.mutation]
    assert preview_window.count(old) == 1, args.mutation
    preview_window = preview_window.replace(old, new)
def window_method(text, signature, after=0):
    start = text.index(signature, after)
    return text[start:text.index('\n}\n', start) + 3]
window_problems = []
for name, text in (('TSPreviewWindow', preview_window), ('TSFullSplitWindow', split_window)):
    send = window_method(text, '- (void)sendEvent:')
    guard = send[send.index('BOOL inPDF'):send.index('fancyMouseDown: theEvent')]
    if 'pinnedLinkPreviewContainsWindowPoint: thePoint' not in guard.split('if (inPDF')[1].split('\n')[0]:
        window_problems.append(f'{name} hands clicks in a pinned popup to the magnifying glass')
resign = window_method(preview_window, '- (void)resignMainWindow')
if 'cleanupMarquee: YES' in resign or resign.count('cleanupMarqueeKeepingPinnedLinkPreview') != 2:
    window_problems.append('another window becoming main closes pinned popups')
first = preview_window.index('- (void) mainSplitPdfKitWindow')
split = window_method(preview_window, '- (void) mainSplitPdfKitWindow', preview_window.index('- (void) mainSplitPdfKitWindow', first + 1))
if 'cleanupMarquee: YES' in split or split.count('cleanupMarqueeKeepingPinnedLinkPreview') != 2:
    window_problems.append('splitting closes pinned popups')
detach, remove, attach = (split.find(x) for x in ('detachPinnedLinkPreviewWithWindowFrame: &movedPreviewFrame',
    '[self.myPDFKitView2 removeFromSuperview]', 'attachPinnedLinkPreview: movedPreview windowFrame: movedPreviewFrame'))
if not (0 <= detach < remove < attach) or 'if (! [(MyPDFKitView *)self.myPDFKitView hasPinnedLinkPreview])' not in split:
    window_problems.append('unsplitting drops the pinned popup of the pane that goes away')
if not split.rstrip().endswith('[self keepPinnedLinkPreviewsInView];\n}'):
    window_problems.append('splitting does not bring pinned popups back into view')
keep = window_method(preview_window, '- (void)keepPinnedLinkPreviewsInView')
if keep.count('keepPinnedLinkPreviewInView]') != 4 or 'dispatch_async(dispatch_get_main_queue()' not in keep:
    window_problems.append('pinned popups are not brought back into view after layout')
if args.mutation in window_mutations:
    assert window_problems, args.mutation
    print('PASS: detected mutation ' + args.mutation + ': ' + window_problems[0])
    raise SystemExit(0)
assert not window_problems, window_problems
print('PASS: preview windows keep pinned popups through the magnifying glass, other windows and splitting')
program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"
#import "TSLinkPreviewGeometry.h"
#import "OverView.h"
#import "TSLinkPreviewView.h"
#import "TSScrollPageTurn.h"
#import "TSPreviewScrollerKeeper.h"
#define SUD NSUserDefaults.standardUserDefaults
#define FlashFixKey @"flash"
#define FlashDelayKey @"delay"
#define LinkPopupsKey @"links"
#define ShowSyncMarksKey @"sync"
#define PdfPageStyleKey @"pageStyle"
#define PdfFirstPageStyleKey @"firstPage"
#define PdfKitFitSizeKey @"fit"
#define NEW_PDF_FIT_TO_WIDTH 2
#define NEW_PDF_FIT_TO_HEIGHT 3
#define PDF_FIT_TO_WINDOW 4
// The values of Sources/App/globals.h, which mouseMoved: also uses as numbers.
#define NEW_MOUSE_MODE_SCROLL 1
#define NEW_MOUSE_MODE_SELECT_TEXT 2
#define NEW_MOUSE_MODE_SELECT_PDF 5
#define NEW_MOUSE_MODE_MAG_GLASS 3
#define NEW_MOUSE_MODE_MAG_GLASS_L 4
#define PDF_SINGLE_PAGE_STYLE 1
#define PDF_TWO_PAGE_STYLE 2
#define PDF_MULTI_PAGE_STYLE 3
#define PDF_MAX_SCALE 2000
#define PdfCopyTypeKey @"copyType"
#define IMAGE_TYPE_PDF 3
#define IMAGE_TYPE_EPS 4
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSEventModifierFlags flags;
static NSEventModifierFlags currentFlags(id self, SEL sel) { return flags; }
static NSPoint currentMouse(id self, SEL sel) { return NSZeroPoint; }
// handleLink: reads Shift and Command from the event being handled.
static NSEventModifierFlags eventFlags;
static NSEvent *currentEvent(id self, SEL sel) {
    return eventFlags ? [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint modifierFlags:eventFlags
        timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:0] : nil;
}
// The page point that the pointer hovers over, on the first page's link.
static NSPoint linkPoint = {30, 730};
static NSMutableArray *handlers;
static id addMonitor(id self, SEL sel, NSEventMask mask, id handler) {
    // Text views add monitors of their own; only the popup's is recorded.
    if (mask != (NSEventMaskKeyDown | NSEventMaskFlagsChanged)) return [NSObject new];
    id block = [handler copy]; [handlers addObject:block]; return block;
}
static void removeMonitor(id self, SEL sel, id monitor) { [handlers removeObjectIdenticalTo:monitor]; }
// Whether a click also cleans up the marquee on its way, as selecting text or the magnifying glass do.
static BOOL cleanupInClick;
// Makes the click fail on its way, as an exception would.
static BOOL throwInClick;
// Copy writes to a private pasteboard, never the user's clipboard.
static NSPasteboard *testPasteboard;
static NSPasteboard *generalPasteboard(id self, SEL sel) { return testPasteboard; }
@interface NSObject (TestLinkPopups)
- (void)linkPopupsChanged;
@end
@interface TestDocument : NSObject
@property BOOL previewDisplaysAsBook, previewDisplaysRTL, pdfSinglePage, linkPopups;
@property id myPDFKitView, myPDFKitView2;
- (void)toggleLinkPopups:(id)sender;
@property NSInteger stringWindowAlignment;
- (void)updatePreviewLayoutControls;
- (BOOL)validatePreviewLayoutItem:(NSMenuItem *)item;
- (NSMenu *)mousemodeMenu;
- (NSMatrix *)mousemodeMatrix;
- (NSWindow *)magnificationPanel;
@end
@implementation TestDocument
- (void)updatePreviewLayoutControls {}
- (BOOL)validatePreviewLayoutItem:(NSMenuItem *)item { return YES; }
- (NSMenu *)mousemodeMenu { return nil; }
- (NSMatrix *)mousemodeMatrix { return nil; }
- (NSWindow *)magnificationPanel { return nil; }
DOCUMENTMETHODS
@end
#define TSDocument TestDocument
// The preview window's active view, which the toolbar and Escape work with (#14).
@interface TestPreviewWindow : NSWindow
@property PDFView *activeView;
@end
@implementation TestPreviewWindow
@end
@interface MyPDFKitView : PDFView {
    NSInteger mouseMode, currentMouseMode;
    NSInteger pageIndexForMark, scaleMag;
    id myScale, myScale1, smyScale, myStepper, smyStepper, myStepper1, currentPage0, scurrentPage, currentPage1;
    BOOL _editMode,protectFind,downOverLink,showSync,fromTypesetOrQuit,firstTimeSave,drawMark;
    NSInteger pageStyle,firstPageStyle,resizeOption;
    NSRect oldVisibleRect,rect,selectedRect;
    BOOL _pdfViewReady;
    id linkPreviewEventMonitor;
    TSLinkPreviewView *linkPreview;
    TSLinkPreviewView *pinnedLinkPreview;
    BOOL showsLinkPreviewCursor;
    BOOL keepsPinnedLinkPreview;
    BOOL _skipLinks;
}
@property BOOL skipLinks, inLink;
@property (readonly) BOOL globalLongTerm;
- (void)linkPopupsChanged;
@property TestDocument *myDocument;
@property NSInteger handlingLink, timerNumber;
@property OverView *overView;
@property BOOL firstTime,oldUsed,doScroll,PDFFlashFix;
@property NSInteger stringAlignment;
@property NSString *oneOffSearchString;
@property TestPreviewWindow *myPDFWindow;
@property NSTimeInterval PDFFlashDelay;
@property NSView *myHideView1,*myHideView2;
@property NSTimer *selRectTimer;
- (void)initializeDisplay;
- (void)cleanupMarquee:(BOOL)terminate;
- (void)setupPageStyle;
- (void)setupMagnificationStyle;
- (void)doKillPopup;
- (NSEvent *)handleLinkPreviewEvent:(NSEvent *)event;
- (void)observeLinkPreviewEvents;
- (void)handleLink:(NSTimer *)timer;
- (void)killPopup:(NSTimer *)timer;
- (TSLinkPreviewView *)preview;
- (TSLinkPreviewView *)transientPreview;
- (void)closePinnedLinkPreview;
- (void)killTransientLinkPreview;
- (void)setTestMouseMode:(NSInteger)mode;
- (void)setTestPageStyle:(NSInteger)style;
- (void)setTestScaleField:(NSTextField *)field;
- (void)setTestDownOverLink;
- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
- (IBAction)takeDestinationFromOutline:(id)sender;
- (void)setIndexForMark:(NSInteger)index;
- (void)firstPage:(id)sender;
- (void)lastPage:(id)sender;
- (void)previousPage:(id)sender;
- (void)nextPage:(id)sender;
- (void)changeScale:(id)sender;
- (void)goToKitPageNumber:(NSInteger)page;
- (void)fancyMouseDown:(NSEvent *)event;
- (void)cleanupMarqueeKeepingPinnedLinkPreview;
- (BOOL)hasPinnedLinkPreview;
- (BOOL)pinnedLinkPreviewContainsWindowPoint:(NSPoint)point;
- (TSLinkPreviewView *)detachPinnedLinkPreviewWithWindowFrame:(NSRect *)frame;
- (void)attachPinnedLinkPreview:(TSLinkPreviewView *)preview windowFrame:(NSRect)frame;
- (void)keepPinnedLinkPreviewInView;
@end
@implementation MyPDFKitView
// The popup on show, the pinned one if there is one; and whether one is pinned.
- (TSLinkPreviewView *)preview { return pinnedLinkPreview ?: linkPreview; }
- (TSLinkPreviewView *)transientPreview { return linkPreview; }
- (BOOL)globalLongTerm { return pinnedLinkPreview != nil; }
- (void)setupPageStyle {}
- (void)setupMagnificationStyle {}
- (void)updateBackground:(NSRect)rect {}
- (void)setDrawMark:(BOOL)value { drawMark=value; }
- (void)setTestMouseMode:(NSInteger)mode { mouseMode = currentMouseMode = mode; }
- (void)setTestPageStyle:(NSInteger)style { pageStyle = style; }
- (void)setTestScaleField:(NSTextField *)field { myScale = field; }
- (void)setTestDownOverLink { downOverLink = YES; }
- (BOOL)annotationMouseUp:(NSEvent *)event { return NO; }
- (void)stepPageForward:(BOOL)forward sender:(id)sender {
    if (forward) [self goToNextPage:sender]; else [self goToPreviousPage:sender];
}
- (NSData *)imageDataFromSelectionType:(NSInteger)type { return nil; }
// Stop the rest of mouseDown after its production popup-cleanup entry path. Clicks clean up
// the marquee on their way (selecting text, the magnifying glass), so do that here too.
- (BOOL)annotationMouseDown:(NSEvent *)event {
    if (cleanupInClick) [self cleanupMarquee:YES];
    if (throwInClick) [NSException raise:@"TestException" format:@"click fails"];
    return YES;
}
- (void)doSync:(NSPoint)point {}
- (void)doMagnifyingGlass:(NSEvent *)event level:(NSInteger)level {}
- (void)scrollByDragging:(NSEvent *)event {}
- (void)startDragging:(NSEvent *)event {}
- (void)selectARectForMavericks:(NSEvent *)event {}
- (void)updateDarkModeInversion {}
- (void)scaleChanged:(id)sender {}
- (PDFAreaOfInterest)areaOfInterestForMouse:(NSEvent *)event { return self.inLink ? kPDFLinkArea : kPDFPageArea; }
METHODS
@end
static NSEvent *event(NSWindow *window, NSEventType type, NSEventModifierFlags modifiers, NSString *text, NSPoint point) {
    if (type == NSEventTypeMouseMoved)
        return [NSEvent mouseEventWithType:type location:point modifierFlags:modifiers timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
    return [NSEvent keyEventWithType:type location:point modifierFlags:modifiers timestamp:0 windowNumber:window.windowNumber context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:0];
}
static NSTimer *timeout(MyPDFKitView *view) {
    return [NSTimer timerWithTimeInterval:4 target:view selector:@selector(killPopup:) userInfo:@[@(view.timerNumber)] repeats:NO];
}
static NSTimer *showTimer(MyPDFKitView *view) {
    NSPoint location = [view convertPoint:linkPoint fromPage:[view.document pageAtIndex:0]];
    location = [view convertPoint:location toView:nil];
    NSEvent *move = event(view.window, NSEventTypeMouseMoved, flags, @"", location);
    return [NSTimer timerWithTimeInterval:.2 target:view selector:@selector(handleLink:)
        userInfo:@[@(view.timerNumber), [NSValue valueWithPoint:NSZeroPoint], move] repeats:NO];
}
static void show(MyPDFKitView *view, NSEventModifierFlags modifiers) {
    flags = modifiers;
    view.handlingLink = 1;
    [view handleLink:showTimer(view)];
    check(view.handlingLink == 2 && view.preview.superview == view.documentView, @"real link produces popup");
    check(view.preview.pinned == ((modifiers & NSEventModifierFlagOption) != 0), @"popup is pinned only with Option");
}

static NSEvent *clicks(NSWindow *window, NSEventType type, NSPoint point, NSInteger count) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0 windowNumber:window.windowNumber
        context:nil eventNumber:0 clickCount:count pressure:1];
}
static NSEvent *mouse(NSWindow *window, NSEventType type, NSPoint point) { return clicks(window, type, point, 1); }
static NSEvent *scroll(int32_t dy, int32_t dx) {
    CGEventRef cg = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, dy, dx);
    NSEvent *result = [NSEvent eventWithCGEvent:cg]; CFRelease(cg); return result;
}
static BOOL approx(CGFloat a, CGFloat b) { return fabs(a-b) < 0.01; }
// Window coordinates of a point inside the popup, `inset` screen points from its right edge.
static NSPoint windowPoint(TSLinkPreviewView *preview, CGFloat fromLeft, CGFloat fromBottom) {
    NSRect frame = [preview.superview convertRect:preview.frame toView:nil];
    return NSMakePoint(NSMinX(frame) + fromLeft, NSMinY(frame) + fromBottom);
}
static void testInteraction(MyPDFKitView *view, NSWindow *window) {
    NSView *root = window.contentView.superview;
    show(view, 0);
    TSLinkPreviewView *preview = view.preview;
    NSPoint center = windowPoint(preview, NSWidth([preview convertRect:preview.bounds toView:nil])/2,
                                 NSHeight([preview convertRect:preview.bounds toView:nil])/2);
    check([root hitTest:center] != preview, @"hovering popup leaves the mouse to the preview");
    check([preview cursorAtPoint:[view.documentView convertPoint:center fromView:nil]] == nil, @"hovering popup keeps the preview cursor");
    flags = NSEventModifierFlagOption;
    NSEvent *(^handler)(NSEvent *) = handlers.lastObject;
    handler(event(window,NSEventTypeFlagsChanged,NSEventModifierFlagOption,@"",NSZeroPoint));
    flags = 0;
    check(preview.pinned, @"Option while shown makes the popup interactive");
    check([root hitTest:center] == preview, @"pinned popup takes clicks inside it");
    NSRect outside = [view.documentView convertRect:view.documentView.visibleRect toView:nil];
    NSPoint far = NSMakePoint(NSMinX(outside) + 2, NSMinY(outside) + 2);
    check([root hitTest:far] != preview, @"clicks outside the pinned popup reach the preview");

    NSRect startFrame = preview.frame, startSource = preview.source;
    CGFloat scale = NSWidth(startFrame) / NSWidth(startSource);
    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, center)];
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, center)];
    check(view.preview == preview && preview.superview && view.handlingLink == 2 && handlers.count == 1,
          @"click inside pinned popup keeps it");
    check(NSEqualRects(preview.frame, startFrame) && NSEqualRects(preview.source, startSource), @"click without drag changes nothing");

    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, center)];
    check(NSCursor.currentCursor == NSCursor.closedHandCursor, @"dragging shows a closed hand");
    [preview mouseDragged:mouse(window, NSEventTypeLeftMouseDragged, NSMakePoint(center.x - 30, center.y - 20))];
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, NSMakePoint(center.x - 30, center.y - 20))];
    NSRect moved = [view.documentView convertRect:preview.frame toView:nil];
    NSRect before = [view.documentView convertRect:startFrame toView:nil];
    check(approx(NSMinX(moved), NSMinX(before) - 30) && approx(NSMinY(moved), NSMinY(before) - 20) &&
          approx(NSWidth(moved), NSWidth(before)) && NSEqualRects(preview.source, startSource),
          @"dragging the inside moves the popup with its contents");

    NSRect frame = preview.frame, source = preview.source;
    NSRect onScreen = [view.documentView convertRect:frame toView:nil];
    NSPoint edge = windowPoint(preview, NSWidth(onScreen) - 2, NSHeight(onScreen) / 2);
    NSPoint edgeInView = [view.documentView convertPoint:edge fromView:nil];
    check([preview cursorAtPoint:edgeInView] != NSCursor.openHandCursor && [preview cursorAtPoint:edgeInView] != nil,
          @"edge shows a resize cursor");
    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, edge)];
    [preview mouseDragged:mouse(window, NSEventTypeLeftMouseDragged, NSMakePoint(edge.x - 40, edge.y + 15))];
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, NSMakePoint(edge.x - 40, edge.y + 15))];
    NSRect resized = [view.documentView convertRect:preview.frame toView:nil];
    check(approx(NSWidth(resized), NSWidth(onScreen) - 40) && approx(NSMinX(resized), NSMinX(onScreen)) &&
          approx(NSHeight(resized), NSHeight(onScreen)), @"dragging the right edge resizes the popup");
    check(approx(NSWidth(preview.frame) / NSWidth(preview.source), scale) && approx(NSMinX(preview.source), NSMinX(source)),
          @"resizing keeps the text size and the left side of the page");

    NSRect clip = view.documentView.enclosingScrollView.contentView.bounds;
    source = preview.source; frame = preview.frame;
    CGFloat unit = NSWidth([view.documentView convertRect:NSMakeRect(0,0,1,1) fromView:nil]);
    [preview scrollWheel:scroll(12, -9)];
    check(approx(NSMinY(preview.source), NSMinY(source) + 12 * unit / scale) &&
          approx(NSMinX(preview.source), NSMinX(source) + 9 * unit / scale) &&
          approx(NSWidth(preview.source), NSWidth(source)),
          @"scrolling moves the page inside the popup");
    check(NSEqualRects(preview.frame, frame), @"scrolling leaves the popup in place");
    check(NSEqualRects(view.documentView.enclosingScrollView.contentView.bounds, clip),
          @"scrolling the popup leaves the preview where it is");
    for (int i = 0; i < 400; i++) [preview scrollWheel:scroll(-40, 0)];
    check(approx(NSMinY(preview.source), 0) && NSEqualRects(view.documentView.enclosingScrollView.contentView.bounds, clip),
          @"scrolling stops at the bottom of the page");
    check(NSEqualRects(preview.frame, frame), @"scrolling to the page edge leaves the popup in place");

    [NSCursor.arrowCursor set];
    [view mouseMoved:mouse(window, NSEventTypeMouseMoved, windowPoint(preview, 20, 15))];
    check(NSCursor.currentCursor == NSCursor.openHandCursor, @"pointer over pinned popup shows an open hand");

    check(handler(event(window,NSEventTypeKeyDown,0,@"\033",NSZeroPoint)) == nil, @"Escape closes a moved popup");
    check(!view.preview && !preview.superview && !handlers.count, @"closing removes the popup view");
}
// A page whose text starts at the link destination (20, 600).
static PDFDocument *textDocument(void) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 600, 800);
    CGContextRef context = CGPDFContextCreate(consumer, &box, NULL);
    CGPDFContextBeginPage(context, NULL);
    NSDictionary *attributes = @{(id)kCTFontAttributeName: (__bridge id)CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL)};
    NSArray *lines = @[@"Lemma 2. Every bounded sequence of real numbers has a convergent subsequence.",
                       @"Proof. Choose a monotone subsequence and apply the monotone convergence theorem.",
                       @"This completes the proof of the lemma, which is used again in the next section."];
    for (NSUInteger i = 0; i < lines.count; i++) {
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)
            [[NSAttributedString alloc] initWithString:lines[i] attributes:attributes]);
        CGContextSetTextPosition(context, 20, 588 - 16 * i);
        CTLineDraw(line, context);
        CFRelease(line);
    }
    CGPDFContextEndPage(context);
    CGPDFContextClose(context);
    CGContextRelease(context);
    CGDataConsumerRelease(consumer);
    PDFDocument *doc = [[PDFDocument alloc] initWithData:data];
    PDFPage *page = [doc pageAtIndex:0];
    PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,720,100,25) forType:PDFAnnotationSubtypeLink withProperties:nil];
    link.destination = [[PDFDestination alloc] initWithPage:page atPoint:NSMakePoint(20,600)]; [page addAnnotation:link];
    return doc;
}
// Window points inside the popup where the cursor is `cursor`, away from the edges.
static NSPoint findPoint(MyPDFKitView *view, NSCursor *cursor) {
    TSLinkPreviewView *preview = view.preview;
    NSRect frame = [preview.superview convertRect:preview.frame toView:nil];
    for (CGFloat y = NSMaxY(frame) - 10; y > NSMinY(frame) + 10; y -= 2)
        for (CGFloat x = NSMinX(frame) + 10; x < NSMaxX(frame) - 10; x += 3) {
            NSPoint point = NSMakePoint(x, y);
            if ([preview cursorAtPoint:[view.documentView convertPoint:point fromView:nil]] == cursor) return point;
        }
    return NSMakePoint(NAN, NAN);
}
// Some system cursors are new objects on each call.
static BOOL sameCursor(NSCursor *a, NSCursor *b) {
    return a == b || (a && b && NSEqualPoints(a.hotSpot, b.hotSpot) &&
                      [a.image.TIFFRepresentation isEqualToData:b.image.TIFFRepresentation]);
}
static void drag(TSLinkPreviewView *preview, NSWindow *window, NSPoint from, NSPoint to) {
    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, from)];
    [preview mouseDragged:mouse(window, NSEventTypeLeftMouseDragged, to)];
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, to)];
}
static void testTools(MyPDFKitView *view, NSWindow *window, PDFDocument *doc) {
    view.document = doc; [view layoutDocumentView];
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    show(view, NSEventModifierFlagOption);
    flags = 0;
    TSLinkPreviewView *preview = view.preview;
    NSPoint text = findPoint(view, NSCursor.IBeamCursor), blank = findPoint(view, NSCursor.openHandCursor);
    check(!isnan(text.x), @"pointer over text in a pinned popup shows an I-beam");
    check(!isnan(blank.x), @"pointer away from text shows an open hand to move the popup");
    NSRect frame = preview.frame;
    drag(preview, window, text, NSMakePoint(text.x + 120, text.y));
    check(preview.selection.string.length > 3 && preview.selectionIsRecent && NSEqualRects(preview.frame, frame),
          @"dragging over text selects it and leaves the popup in place");
    NSString *selected = preview.selection.string;
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
    check([view validateMenuItem:copyItem], @"Copy is enabled for text selected in the popup");
    [testPasteboard clearContents];
    [view copy:nil];
    check([[testPasteboard stringForType:NSPasteboardTypeString] isEqualToString:selected], @"Copy copies the popup selection");
    // With the keyboard elsewhere, a click in the popup brings Copy to its preview.
    NSTextView *field = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)];
    [window.contentView addSubview:field];
    field.string = @"sourceSentinel"; [field selectAll:nil];
    [window makeFirstResponder:field];
    [preview mouseDown:clicks(window, NSEventTypeLeftMouseDown, text, 2)];
    [preview mouseUp:clicks(window, NSEventTypeLeftMouseUp, text, 2)];
    check(window.firstResponder == view, @"clicking the popup makes its preview the active view");
    [testPasteboard clearContents];
    check([window.firstResponder tryToPerform:@selector(copy:) with:nil] &&
          [[testPasteboard stringForType:NSPasteboardTypeString] isEqualToString:preview.selection.string],
          @"Copy through the responder chain copies the popup selection");
    [field removeFromSuperview];
    [preview mouseDown:clicks(window, NSEventTypeLeftMouseDown, text, 1)];
    [preview mouseUp:clicks(window, NSEventTypeLeftMouseUp, text, 1)];
    drag(preview, window, text, NSMakePoint(text.x + 120, text.y));
    cleanupInClick = YES;
    [view mouseDown:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    cleanupInClick = NO;
    check(view.preview == preview && !preview.selectionIsRecent && preview.selection,
          @"clicking the preview keeps the popup and its highlight but not for Copy");
    [preview mouseDown:clicks(window, NSEventTypeLeftMouseDown, text, 2)];
    [preview mouseUp:clicks(window, NSEventTypeLeftMouseUp, text, 2)];
    check(preview.selection.string.length > 0 && preview.selection.string.length < 20 && preview.selectionIsRecent,
          @"double-clicking selects a word");
    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, blank)];
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, blank)];
    check(!preview.selection && NSEqualRects(preview.frame, frame), @"a click away from text clears the selection");
    drag(preview, window, blank, NSMakePoint(blank.x + 7, blank.y - 5));
    NSRect moved = [view.documentView convertRect:preview.frame toView:nil];
    NSRect before = [view.documentView convertRect:frame toView:nil];
    check(approx(NSMinX(moved), NSMinX(before) + 7) && approx(NSMinY(moved), NSMinY(before) - 5),
          @"dragging away from text moves the popup");

    [view setTestMouseMode:NEW_MOUSE_MODE_MAG_GLASS];
    check(!isnan(findPoint(view, NSCursor.IBeamCursor).x), @"the magnifying glass acts as the pointer inside the popup");
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_PDF];
    check(!isnan(findPoint(view, NSCursor.IBeamCursor).x), @"the selection tool acts as the pointer inside the popup");

    [view setTestMouseMode:NEW_MOUSE_MODE_SCROLL];
    check(isnan(findPoint(view, NSCursor.IBeamCursor).x), @"with the hand tool the whole popup moves");
    text = findPoint(view, NSCursor.openHandCursor);
    frame = preview.frame;
    drag(preview, window, text, NSMakePoint(text.x + 5, text.y + 4));
    check(!preview.selection && !NSEqualRects(preview.frame, frame), @"hand tool moves over text instead of selecting");

    // Leaving the popup shows the tool's cursor, however fast the pointer moves.
    NSRect visible = [view.documentView convertRect:view.documentView.visibleRect toView:nil];
    NSPoint away = NSMakePoint(NSMinX(visible) + 3, NSMinY(visible) + 3);
    NSDictionary *expected = @{@(NEW_MOUSE_MODE_SCROLL): NSCursor.openHandCursor, @(NEW_MOUSE_MODE_MAG_GLASS): NSCursor.arrowCursor,
                               @(NEW_MOUSE_MODE_SELECT_PDF): NSCursor.crosshairCursor, @(NEW_MOUSE_MODE_SELECT_TEXT): NSCursor.arrowCursor};
    for (NSNumber *mode in expected) {
        [view setTestMouseMode:mode.integerValue];
        NSPoint edge = windowPoint(preview, 2, 20);
        [view mouseMoved:mouse(window, NSEventTypeMouseMoved, edge)];
        check(!sameCursor(NSCursor.currentCursor, expected[mode]), @"edge of the popup shows a resize cursor");
        [view mouseMoved:mouse(window, NSEventTypeMouseMoved, away)];
        check(sameCursor(NSCursor.currentCursor, expected[mode]), @"leaving the popup shows the tool's cursor");
    }

    // A pinned popup can be pushed almost out of the preview.
    [view setTestMouseMode:NEW_MOUSE_MODE_SCROLL];
    CGFloat unit = NSWidth([view.documentView convertRect:NSMakeRect(0,0,1,1) fromView:nil]);
    NSRect available = NSInsetRect(view.documentView.visibleRect, 5, 5);
    for (NSValue *direction in @[[NSValue valueWithSize:NSMakeSize(-5000,-5000)], [NSValue valueWithSize:NSMakeSize(5000,5000)]]) {
        NSPoint start = findPoint(view, NSCursor.openHandCursor);
        frame = preview.frame;
        drag(preview, window, start, NSMakePoint(start.x + direction.sizeValue.width, start.y + direction.sizeValue.height));
        NSRect shown = NSIntersectionRect(preview.frame, available);
        check(approx(NSWidth(shown), MAX(NSWidth(frame) * 0.05, 20 * unit)) &&
              approx(NSHeight(shown), MAX(NSHeight(frame) * 0.05, 20 * unit)) &&
              approx(NSWidth(preview.frame), NSWidth(frame)),
              @"moved popup keeps only a small part in view");
        drag(preview, window, findPoint(view, NSCursor.openHandCursor), findPoint(view, NSCursor.openHandCursor));
    }
    // Changing the tool keeps a pinned popup; the selection tool's marquee goes away.
    for (NSNumber *target in @[@(NEW_MOUSE_MODE_SELECT_TEXT), @(NEW_MOUSE_MODE_MAG_GLASS), @(NEW_MOUSE_MODE_SCROLL)]) {
        [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_PDF];
        OverView *marquee = [[OverView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [view.documentView addSubview:marquee]; view.overView = marquee;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""]; item.tag = target.integerValue;
        [view changeMouseMode:item];
        check(view.preview == preview && preview.superview && view.globalLongTerm && handlers.count == 1,
              @"changing the tool keeps a pinned popup");
        if (target.integerValue != NEW_MOUSE_MODE_SCROLL)
            check(!view.overView && !marquee.superview, @"changing the tool still removes the marquee");
        [marquee removeFromSuperview]; view.overView = nil;
    }
    // A click that fails on its way leaves later cleanups as they were.
    throwInClick = YES;
    @try { [view mouseDown:mouse(window, NSEventTypeLeftMouseDown, away)]; } @catch (NSException *exception) {}
    throwInClick = NO;
    check(view.preview == preview, @"a failed click keeps the pinned popup");
    [view cleanupMarquee:YES];
    check(!view.preview && !handlers.count, @"after a failed click, cleanup outside a click dismisses the popup");

    // Hovering shows popups with every tool but the selection tool.
    for (NSNumber *mode in @[@(NEW_MOUSE_MODE_SCROLL), @(NEW_MOUSE_MODE_SELECT_TEXT), @(NEW_MOUSE_MODE_MAG_GLASS), @(NEW_MOUSE_MODE_SELECT_PDF)]) {
        [view setTestMouseMode:mode.integerValue];
        view.inLink = YES; view.handlingLink = 0;
        [view mouseMoved:mouse(window, NSEventTypeMouseMoved, away)];
        check((view.handlingLink == 1) == (mode.integerValue != NEW_MOUSE_MODE_SELECT_PDF), @"hovering a link starts a popup unless the selection tool is chosen");
        view.inLink = NO; [view doKillPopup];
    }
    [view doKillPopup];
    [view setTestMouseMode:0];
}
static NSEvent *exited(NSWindow *window, NSPoint point) {
    return [NSEvent enterExitEventWithType:NSEventTypeMouseExited location:point modifierFlags:0 timestamp:0
        windowNumber:window.windowNumber context:nil eventNumber:0 trackingNumber:0 userData:NULL];
}
// The pointer leaves a pinned popup, or a drag of it ends, outside the popup: no cursor of the
// popup stays there, as the resize arrows did over the toolbar (#14).
static void testCursorOutside(MyPDFKitView *view, NSWindow *window) {
    view.document = textDocument(); [view layoutDocumentView];
    NSRect content = window.contentLayoutRect;
    // TeXShop's toolbar lies above the content, as the title bar does in this window.
    NSPoint toolbar = NSMakePoint(NSMidX(content), NSMaxY(content) + 5);
    NSRect visible = [view.documentView convertRect:view.documentView.visibleRect toView:nil];
    NSPoint away = NSMakePoint(NSMinX(visible) + 3, NSMinY(visible) + 3);
    check(!NSPointInRect(toolbar, content) && toolbar.y < NSHeight(window.frame) && NSMaxY(visible) <= NSMaxY(content),
          @"the toolbar point lies above the preview, in the window");

    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_PDF];
    show(view, NSEventModifierFlagOption); flags = 0;
    TSLinkPreviewView *preview = view.preview;
    BOOL watches = NO;
    for (NSTrackingArea *area in preview.trackingAreas)
        watches |= area.owner == preview && (area.options & NSTrackingMouseEnteredAndExited) && (area.options & NSTrackingInVisibleRect);
    check(watches, @"the popup watches the pointer leave it");
    NSRect onScreen = [preview.superview convertRect:preview.frame toView:nil];
    NSPoint top = NSMakePoint(NSMidX(onScreen), NSMaxY(onScreen) - 2);
    NSCursor *resize = [preview cursorAtPoint:[view.documentView convertPoint:top fromView:nil]];
    check(resize && !sameCursor(resize, NSCursor.openHandCursor) && !sameCursor(resize, NSCursor.arrowCursor),
          @"the top edge of the popup shows a resize cursor");
    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, top)];
    [preview mouseDragged:mouse(window, NSEventTypeLeftMouseDragged, toolbar)];
    [preview mouseExited:exited(window, toolbar)];
    check(sameCursor(NSCursor.currentCursor, resize), @"a drag keeps its cursor when the pointer leaves the popup");
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, toolbar)];
    NSRect resized = [preview.superview convertRect:preview.frame toView:nil];
    check(NSMaxY(resized) > NSMaxY(onScreen) && NSMaxY(resized) < NSMaxY(visible) && approx(NSMinY(resized), NSMinY(onScreen)),
          @"the top edge stops below the toolbar");
    check(sameCursor(NSCursor.currentCursor, NSCursor.arrowCursor), @"releasing the edge over the toolbar shows the arrow");

    // Released in the preview but outside the popup: the tool's cursor, whichever tool it is.
    NSDictionary *expected = @{@(NEW_MOUSE_MODE_SCROLL): NSCursor.openHandCursor, @(NEW_MOUSE_MODE_SELECT_PDF): NSCursor.crosshairCursor,
                               @(NEW_MOUSE_MODE_MAG_GLASS): NSCursor.arrowCursor, @(NEW_MOUSE_MODE_SELECT_TEXT): NSCursor.arrowCursor};
    for (NSNumber *mode in expected) {
        [view setTestMouseMode:mode.integerValue];
        NSPoint edge = windowPoint(preview, 2, 20);
        [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, edge)];
        [preview mouseDragged:mouse(window, NSEventTypeLeftMouseDragged, away)];
        check(!sameCursor(NSCursor.currentCursor, expected[mode]), @"a drag of the edge shows a resize cursor");
        [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, away)];
        check([preview cursorAtPoint:[view.documentView convertPoint:away fromView:nil]] == nil &&
              sameCursor(NSCursor.currentCursor, expected[mode]),
              @"releasing a drag in the preview outside the popup shows the tool's cursor");
    }

    // Leaving the popup straight onto the toolbar, with no move over the preview between.
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_PDF];
    NSPoint edge = windowPoint(preview, 2, 20);
    [view mouseMoved:mouse(window, NSEventTypeMouseMoved, edge)];
    check(!sameCursor(NSCursor.currentCursor, NSCursor.arrowCursor), @"the edge shows a resize cursor before leaving");
    [preview mouseExited:exited(window, toolbar)];
    check(sameCursor(NSCursor.currentCursor, NSCursor.arrowCursor), @"leaving the popup straight onto the toolbar shows the arrow");
    [view mouseMoved:mouse(window, NSEventTypeMouseMoved, edge)];
    [preview mouseExited:exited(window, away)];
    check(sameCursor(NSCursor.currentCursor, NSCursor.crosshairCursor), @"leaving the popup into the preview shows the tool's cursor");
    [view mouseMoved:mouse(window, NSEventTypeMouseMoved, edge)];
    NSCursor *before = NSCursor.currentCursor;
    [preview mouseExited:exited(window, edge)];
    check(NSCursor.currentCursor == before, @"an exit while the pointer is still on the popup changes nothing");

    // Moved under the toolbar, the popup's hidden part shows no hand there.
    [view setTestMouseMode:NEW_MOUSE_MODE_SCROLL];
    NSPoint start = findPoint(view, NSCursor.openHandCursor);
    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, start)];
    [preview mouseDragged:mouse(window, NSEventTypeLeftMouseDragged, toolbar)];
    check(sameCursor(NSCursor.currentCursor, NSCursor.closedHandCursor), @"moving the popup shows a closed hand");
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, toolbar)];
    check(NSPointInRect([view.documentView convertPoint:toolbar fromView:nil], preview.frame),
          @"the moved popup lies under the toolbar point");
    check(sameCursor(NSCursor.currentCursor, NSCursor.arrowCursor), @"releasing a moved popup over the toolbar shows the arrow");
    check(![preview cursorAtPoint:[view.documentView convertPoint:toolbar fromView:nil]],
          @"the hidden part of the popup shows no cursor of its own");

    // An ordinary popup leaves the cursor to the preview.
    [view doKillPopup];
    show(view, 0);
    [NSCursor.IBeamCursor set];
    [view.preview mouseExited:exited(window, toolbar)];
    check(NSCursor.currentCursor == NSCursor.IBeamCursor, @"leaving an ordinary popup changes no cursor");
    [view doKillPopup];
    [view setTestMouseMode:0];
}
// Fraction of the pixels in `rect` (view points, y up) that are the label's gray, not page white or text black.
static double grayShare(NSBitmapImageRep *rep, NSView *view, NSRect rect) {
    double scale = rep.pixelsWide / NSWidth(view.bounds); NSUInteger gray = 0, all = 0;
    for (NSInteger y = (NSInteger)(NSMinY(rect) * scale); y < (NSInteger)(NSMaxY(rect) * scale); y++)
        for (NSInteger x = (NSInteger)(NSMinX(rect) * scale); x < (NSInteger)(NSMaxX(rect) * scale); x++) {
            NSColor *c = [[rep colorAtX:x y:rep.pixelsHigh - 1 - y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            CGFloat l = (c.redComponent + c.greenComponent + c.blueComponent) / 3;
            all++; if (l > 0.55 && l < 0.75 && fabs(c.redComponent - c.blueComponent) < 0.05) gray++;
        }
    return all ? (double)gray / all : 0;
}
static NSBitmapImageRep *render(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    return rep;
}
// Stands in front of PDFKit's tool tip method before the filter is installed, so that user
// data PDFKit would not pass reaches it intact instead of being read by the filter.
static struct { int notAnObject; } opaqueToolTipData = {77};
static NSString *(*pdfKitToolTip)(id, SEL, NSView *, NSToolTipTag, NSPoint, void *);
static NSString *fakeToolTip(id self, SEL sel, NSView *view, NSToolTipTag tag, NSPoint point, void *data) {
    if (data == &opaqueToolTipData) return opaqueToolTipData.notAnObject == 77 ? @"opaque" : @"changed";
    return pdfKitToolTip(self, sel, view, tag, point, data);
}
static void installFakeToolTip(void) {
    Method method = class_getInstanceMethod(NSClassFromString(@"PDFPageView"), @selector(view:stringForToolTip:point:userData:));
    check(method != NULL, @"PDFKit's page view has a tool tip method");
    pdfKitToolTip = (NSString *(*)(id, SEL, NSView *, NSToolTipTag, NSPoint, void *))method_setImplementation(method, (IMP)fakeToolTip);
}
static NSView *pageViewOf(PDFView *view) {
    NSMutableArray *views = [NSMutableArray arrayWithObject:view];
    while (views.count) {
        NSView *candidate = views.lastObject; [views removeLastObject];
        if ([NSStringFromClass(candidate.class) isEqualToString:@"PDFPageView"] && candidate.window) return candidate;
        [views addObjectsFromArray:candidate.subviews];
    }
    return nil;
}
// The tool tip PDFKit's page view gives for `annotation`, asked at its center as the tool tip manager would.
static NSString *toolTip(PDFView *view, PDFAnnotation *annotation, void *data) {
    NSView *pageView = pageViewOf(view);
    check(pageView != nil, @"PDFKit draws pages in page views");
    NSPoint center = [view convertPoint:NSMakePoint(NSMidX(annotation.bounds), NSMidY(annotation.bounds)) fromPage:annotation.page];
    return [(id<NSViewToolTipOwner>)pageView view:pageView stringForToolTip:0 point:[pageView convertPoint:center fromView:view] userData:data];
}
// Physical page 1 is labeled i and page 2 is 157, as in a book with front matter.
static PDFDocument *labeledDocument(void) {
    PDFDocument *doc = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:@(getenv("TS_LABELED_PDF"))]];
    check(doc.pageCount == 2 && [[doc pageAtIndex:0].label isEqualToString:@"i"] && [[doc pageAtIndex:1].label isEqualToString:@"157"],
          @"labeled test PDF");
    PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,720,100,25) forType:PDFAnnotationSubtypeLink withProperties:nil];
    link.destination = [[PDFDestination alloc] initWithPage:[doc pageAtIndex:1] atPoint:NSMakePoint(20,600)];
    [[doc pageAtIndex:0] addAnnotation:link];
    PDFAnnotation *web = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,650,100,25) forType:PDFAnnotationSubtypeLink withProperties:nil];
    web.URL = [NSURL URLWithString:@"https://example.com/"];
    [[doc pageAtIndex:0] addAnnotation:web];
    return doc;
}
static void testPageLabelAndToolTips(MyPDFKitView *view, NSWindow *window, PDFDocument *doc) {
    view.document = doc; view.autoScales = NO; view.scaleFactor = 2; [view layoutDocumentView];
    [view goToPage:[doc pageAtIndex:0]];
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    show(view, 0);
    TSLinkPreviewView *preview = view.preview;
    check([preview.pageLabel isEqualToString:[@"Page " stringByAppendingString:[doc pageAtIndex:0].label]],
          @"popup names the target page by its label");
    check([[doc pageAtIndex:0].label isEqualToString:@"1"], @"a PDF without page labels numbers its pages");
    CGFloat unit = NSWidth([view.documentView convertRect:NSMakeRect(0,0,1,1) fromView:nil]);
    NSRect bounds = preview.bounds;
    NSBitmapImageRep *rep = render(preview);
    NSRect corner = NSMakeRect(NSMaxX(bounds) - 30 * unit, NSMinY(bounds) + 3 * unit, 26 * unit, 10 * unit);
    NSRect left = NSMakeRect(NSMinX(bounds) + 4 * unit, NSMinY(bounds) + 3 * unit, 26 * unit, 10 * unit);
    check(grayShare(rep, preview, corner) > 0.3 && grayShare(rep, preview, left) < 0.01,
          @"page label is drawn in the lower right corner");
    NSRect beyond = NSMakeRect(NSMaxX(bounds) - 90 * unit, NSMinY(bounds) + 3 * unit, 20 * unit, 10 * unit);
    check(grayShare(rep, preview, beyond) < 0.01, @"page label keeps its size on screen");
    if (getenv("TS_LABEL_PNG")) [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(getenv("TS_LABEL_PNG")) atomically:YES];
    [view doKillPopup];
    view.autoScales = YES; [view layoutDocumentView];

    // The popup names the linked page by its label, not by its position or the page with the link.
    PDFDocument *labeled = labeledDocument();
    view.document = labeled; [view layoutDocumentView]; [view goToPage:[labeled pageAtIndex:0]];
    show(view, 0);
    check([view.preview.pageLabel isEqualToString:@"Page 157"], @"popup shows the label of the linked page");
    [view doKillPopup];

    // PDFKit's "Go to page" tool tip gives way to the popup.
    [window.contentView display];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    PDFAnnotation *link = nil, *web = nil;
    for (PDFAnnotation *annotation in [labeled pageAtIndex:0].annotations) {
        if (annotation.destination) link = annotation;
        if (annotation.URL) web = annotation;
    }
    check(toolTip(view, link, (__bridge void *)link) == nil, @"internal link gets no PDFKit tool tip while popups are on");
    check([toolTip(view, web, (__bridge void *)web) length] > 0, @"a web link keeps its tool tip");
    check([toolTip(view, link, &opaqueToolTipData) isEqualToString:@"opaque"],
          @"user data that is not the link reaches PDFKit untouched");
    view.skipLinks = YES;
    check([toolTip(view, link, (__bridge void *)link) length] > 0, @"tool tip stays when link popups are off");
    // Control reverses Link Popups: with it off, Control brings the popup and keeps the tool
    // tip away; with it on, Control leaves the tool tip as with popups off (#30).
    flags = NSEventModifierFlagCommand;
    check([toolTip(view, link, (__bridge void *)link) length] > 0, @"with link popups off, Command alone keeps the tool tip");
    flags = NSEventModifierFlagControl;
    check(toolTip(view, link, (__bridge void *)link) == nil, @"with link popups off, Control leaves out the tool tip");
    eventFlags = NSEventModifierFlagControl;
    show(view, NSEventModifierFlagControl);
    flags = 0; eventFlags = 0;
    check(toolTip(view, link, (__bridge void *)link) == nil,
          @"a popup shown with Control keeps the tool tip away after Control is released");
    [view doKillPopup];
    check([toolTip(view, link, (__bridge void *)link) length] > 0, @"once that popup is gone, the tool tip is back");
    view.skipLinks = NO;
    flags = NSEventModifierFlagControl;
    check([toolTip(view, link, (__bridge void *)link) length] > 0, @"with link popups on, Control lets the tool tip through");
    flags = 0;
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_PDF];
    check([toolTip(view, link, (__bridge void *)link) length] > 0, @"tool tip stays with the selection tool, which shows no popups");
    [view setTestMouseMode:0];
    // Another PDFView showing the same document keeps PDFKit's tool tips.
    PDFView *plain = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 650, 850)];
    NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,850) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    other.releasedWhenClosed = NO;
    [other.contentView addSubview:plain];
    plain.document = labeled; plain.autoScales = YES; [plain layoutDocumentView];
    [other.contentView display];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    check([toolTip(plain, link, (__bridge void *)link) length] > 0, @"a PDFView without popups keeps the tool tip");
    [plain removeFromSuperview];
    view.autoScales = YES; [view layoutDocumentView];
    [view setTestMouseMode:0];
}
// A document reads Link Popups when it is opened; both panes follow it from then on (the
// second pane may get its document only when the window is split, without initializing).
// Two pages: a statement that starts at the bottom of the first page, where the link points,
// and goes on at the top of the second.
static PDFDocument *brokenStatementDocument(void) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 600, 800);
    CGContextRef context = CGPDFContextCreate(consumer, &box, NULL);
    NSDictionary *attributes = @{(id)kCTFontAttributeName: (__bridge id)CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL)};
    NSArray *pages = @[@[@"Theorem 4. Every alpha sequence in a compact metric space has a limit point,"],
                       @[@"and every omega sequence that is monotone converges in the given space."]];
    CGFloat baselines[] = {60, 770};
    for (NSUInteger p = 0; p < 2; p++) {
        CGPDFContextBeginPage(context, NULL);
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)
            [[NSAttributedString alloc] initWithString:pages[p][0] attributes:attributes]);
        CGContextSetTextPosition(context, 20, baselines[p]);
        CTLineDraw(line, context);
        CFRelease(line);
        CGPDFContextEndPage(context);
    }
    CGPDFContextClose(context);
    CGContextRelease(context);
    CGDataConsumerRelease(consumer);
    PDFDocument *doc = [[PDFDocument alloc] initWithData:data];
    PDFPage *page = [doc pageAtIndex:0];
    PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,720,100,25) forType:PDFAnnotationSubtypeLink withProperties:nil];
    link.destination = [[PDFDestination alloc] initWithPage:page atPoint:NSMakePoint(20,72)]; [page addAnnotation:link];
    return doc;
}
// Window coordinates of a point given in the popup's image.
static NSPoint imageToWindow(TSLinkPreviewView *preview, NSPoint image) {
    NSRect bounds = preview.bounds, source = preview.source;
    NSPoint local = NSMakePoint(NSMinX(bounds) + (image.x - NSMinX(source)) * NSWidth(bounds) / NSWidth(source),
                                NSMinY(bounds) + (image.y - NSMinY(source)) * NSHeight(bounds) / NSHeight(source));
    return [preview convertPoint:local toView:nil];
}
// A destination near the bottom of its page: in the continuous displays the popup goes on with
// the next page, whose text can be selected with the rest; elsewhere it becomes lower instead
// of filling up with what comes before the destination (#14).
static void testNextPage(MyPDFKitView *view, NSWindow *window) {
    PDFDocument *previous = view.document;
    PDFDisplayMode previousMode = view.displayMode;
    PDFDocument *doc = brokenStatementDocument();
    view.document = doc;
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    linkPoint = NSMakePoint(30,730);
    for (NSNumber *mode in @[@(kPDFDisplaySinglePageContinuous), @(kPDFDisplayTwoUpContinuous), @(kPDFDisplaySinglePage), @(kPDFDisplayTwoUp)]) {
        view.displayMode = mode.integerValue; view.autoScales = YES; [view layoutDocumentView];
        BOOL continuous = mode.integerValue == kPDFDisplaySinglePageContinuous || mode.integerValue == kPDFDisplayTwoUpContinuous;
        eventFlags = NSEventModifierFlagCommand;
        show(view, NSEventModifierFlagOption);
        eventFlags = 0; flags = 0;
        TSLinkPreviewView *preview = view.preview;
        NSRect source = preview.source;
        if (!continuous) {
            check(approx(NSMinY(source), 0) && approx(NSMaxY(source), 82),
                  @"without the next page, a destination near the bottom gives a lower popup");
            [view doKillPopup];
            continue;
        }
        // The linked page lies above the next one, 6 points apart.
        CGFloat first = 800 + TSLinkPreviewPageGap;
        check(approx(NSHeight(source), 360) && approx(NSMaxY(source), first + 82) && NSMinY(source) < 760,
              @"in the continuous displays the popup goes on with the next page");
        NSPoint onFirst = imageToWindow(preview, NSMakePoint(24, first + 64));
        NSPoint onSecond = imageToWindow(preview, NSMakePoint(200, 774));
        NSPoint inGap = imageToWindow(preview, NSMakePoint(200, 800 + TSLinkPreviewPageGap / 2));
        check(sameCursor([preview cursorAtPoint:[view.documentView convertPoint:onSecond fromView:nil]], NSCursor.IBeamCursor),
              @"the text of the next page shows an I-beam");
        check(!sameCursor([preview cursorAtPoint:[view.documentView convertPoint:inGap fromView:nil]], NSCursor.IBeamCursor),
              @"the gap between the pages is no text");
        drag(preview, window, onFirst, onSecond);
        NSString *selected = preview.selection.string;
        check([selected containsString:@"alpha"] && [selected containsString:@"omega"],
              @"text can be selected across the two pages");
        [view doKillPopup];
    }
    [view setTestMouseMode:NEW_MOUSE_MODE_SCROLL];
    view.displayMode = previousMode; view.document = previous; [view layoutDocumentView];
}
// In Multi-Page and Double Multi-Page display the popup stays below the link, or above it with
// Shift, even when part of it falls outside the window; in Single Page and Double Page display
// a popup that does not fit there moves to the other side of the link (#14).
static void testPopupSide(MyPDFKitView *view, NSWindow *window) {
    PDFDocument *previous = view.document;
    PDFDisplayMode previousMode = view.displayMode;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600,800)];
    [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,600,800)); [image unlockFocus];
    PDFDocument *doc = [PDFDocument new];
    PDFPage *page = [[PDFPage alloc] initWithImage:image]; [doc insertPage:page atIndex:0];
    for (NSValue *bounds in @[[NSValue valueWithRect:NSMakeRect(20,720,100,25)], [NSValue valueWithRect:NSMakeRect(20,30,100,25)]]) {
        PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:bounds.rectValue forType:PDFAnnotationSubtypeLink withProperties:nil];
        link.destination = [[PDFDestination alloc] initWithPage:page atPoint:NSMakePoint(20,600)]; [page addAnnotation:link];
    }
    view.document = doc;
    struct { PDFDisplayMode mode; BOOL kept; } modes[] = {
        {kPDFDisplaySinglePageContinuous, YES}, {kPDFDisplayTwoUpContinuous, YES},
        {kPDFDisplaySinglePage, NO}, {kPDFDisplayTwoUp, NO}};
    for (int m = 0; m < 4; m++) {
        view.displayMode = modes[m].mode; view.autoScales = YES; [view layoutDocumentView];
        // Window coordinates, with y up.
        NSRect visible = [view.documentView convertRect:view.documentView.visibleRect toView:nil];
        struct { NSPoint point; NSEventModifierFlags modifiers; BOOL below, fits; } cases[] = {
            {{30,730}, 0, YES, YES},                                                        // fits below
            {{30,42}, 0, YES, NO},                                                          // no room below the bottom link
            {{30,730}, NSEventModifierFlagShift, NO, NO},                                   // no room above the top link
            {{30,730}, NSEventModifierFlagShift | NSEventModifierFlagCommand, NO, NO},
            {{30,42}, NSEventModifierFlagCommand, YES, NO},                                 // no room below the bottom link
            {{30,730}, NSEventModifierFlagCommand, YES, YES}};
        for (int c = 0; c < 6; c++) {
            linkPoint = cases[c].point;
            NSPoint cursor = [view convertPoint:[view convertPoint:linkPoint fromPage:page] toView:nil];
            check(NSPointInRect(cursor, visible), @"the link is in view");
            eventFlags = cases[c].modifiers;
            show(view, 0);
            eventFlags = 0;
            NSRect frame = [view.documentView convertRect:view.preview.frame toView:nil];
            BOOL below = NSMaxY(frame) < cursor.y, above = NSMinY(frame) > cursor.y;
            check(below || above, @"the popup does not cover the link");
            BOOL inside = NSMinX(frame) >= NSMinX(visible) - 0.01 && NSMaxX(frame) <= NSMaxX(visible) + 0.01;
            check(inside, @"the popup stays in view sideways");
            if (cases[c].fits || modes[m].kept) {
                check(below == cases[c].below,
                      @"in the continuous displays the popup stays below the link, or above it with Shift");
                if (!cases[c].fits)
                    check(cases[c].below ? NSMinY(frame) < NSMinY(visible) : NSMaxY(frame) > NSMaxY(visible),
                          @"a popup that does not fit is left partly outside the window");
            } else {
                check(below != cases[c].below && NSMinY(frame) >= NSMinY(visible) - 0.01 && NSMaxY(frame) <= NSMaxY(visible) + 0.01,
                      @"in Single Page and Double Page display a popup that does not fit moves to the other side");
            }
            [view doKillPopup];
        }
    }
    linkPoint = NSMakePoint(30,730);
    view.displayMode = previousMode; view.document = previous; [view layoutDocumentView];
}
static void testDocumentLinkPopups(MyPDFKitView *view, NSWindow *window, PDFDocument *pdf) {
    for (NSNumber *setting in @[@NO, @YES]) {
        TestDocument *document = [TestDocument new];
        document.linkPopups = setting.boolValue;          // as TSDocument's init reads it
        [SUD setBool:!setting.boolValue forKey:LinkPopupsKey]; // Settings changed after opening
        MyPDFKitView *second = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 300, 300)];
        view.myDocument = document; document.myPDFKitView = view; document.myPDFKitView2 = second;
        [view initializeDisplay];                          // the first PDF after the first typesetting
        check(view.skipLinks == !setting.boolValue && document.linkPopups == setting.boolValue,
              @"the first PDF uses the value from when the document was opened");
        second.myDocument = document;                      // split later
        check(second.skipLinks == view.skipLinks, @"a pane added by splitting matches the other pane");
        for (int round = 0; round < 2; round++) {
            BOOL before = document.linkPopups;
            if (!view.skipLinks) show(view, NSEventModifierFlagOption);
            [document toggleLinkPopups:nil];
            check(document.linkPopups == !before && view.skipLinks == before && second.skipLinks == before,
                  @"Link Popups in the menu switches both panes together");
            if (!document.linkPopups) check(!view.preview && !handlers.count, @"switching link popups off closes a pinned popup");
        }
        [view doKillPopup];
        view.myDocument = nil;
    }
    [SUD removeObjectForKey:LinkPopupsKey];
}

// A pinned popup stays through clicks with the magnifying glass, another window becoming
// main, and splitting the window; unsplitting moves it to the pane that stays (#14).
static void testKeepingPinned(MyPDFKitView *view, MyPDFKitView *second, NSWindow *window) {
    show(view, NSEventModifierFlagOption);
    TSLinkPreviewView *preview = view.preview;
    NSPoint inside = windowPoint(preview, 20, 15);
    NSRect visible = [view.documentView convertRect:view.documentView.visibleRect toView:nil];
    NSPoint away = NSMakePoint(NSMinX(visible) + 2, NSMinY(visible) + 2);
    check([view pinnedLinkPreviewContainsWindowPoint:inside], @"the window finds a click in a pinned popup");
    check(![view pinnedLinkPreviewContainsWindowPoint:away], @"the window leaves a click outside the popup to the tool");
    for (NSNumber *mode in @[@(NEW_MOUSE_MODE_MAG_GLASS), @(NEW_MOUSE_MODE_MAG_GLASS_L)]) {
        [view setTestMouseMode:mode.integerValue];
        [view fancyMouseDown:mouse(window, NSEventTypeLeftMouseDown, away)];
        check(view.preview == preview && preview.superview && view.globalLongTerm && handlers.count == 1,
              @"a click with the magnifying glass keeps a pinned popup");
    }
    OverView *marquee = [[OverView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    [view.documentView addSubview:marquee]; view.overView = marquee;
    [view cleanupMarqueeKeepingPinnedLinkPreview];
    check(view.preview == preview && preview.superview && view.globalLongTerm && handlers.count == 1,
          @"another window becoming main keeps a pinned popup");
    check(!view.overView && !marquee.superview, @"another window becoming main still removes the marquee");

    // The part of a popup outside the pane is not clickable there.
    NSRect saved = preview.frame;
    NSRect available = NSInsetRect(view.documentView.visibleRect, 5, 5);
    preview.frame = NSOffsetRect(saved, NSMaxX(available) - NSMinX(saved) - 10, 0);
    NSRect onScreen = [view.documentView convertRect:preview.frame toView:nil];
    check(![view pinnedLinkPreviewContainsWindowPoint:NSMakePoint(NSMaxX(onScreen) - 3, NSMidY(onScreen))],
          @"the hidden part of a pinned popup is not taken for a click");
    // After the pane changes size, the popup comes back into view as far as dragging allows.
    preview.frame = NSOffsetRect(saved, 5000, 5000);
    [view keepPinnedLinkPreviewInView];
    CGFloat unit = NSWidth([view.documentView convertRect:NSMakeRect(0,0,1,1) fromView:nil]);
    NSRect shown = NSIntersectionRect(preview.frame, available);
    check(approx(NSWidth(shown), MAX(NSWidth(saved) * 0.05, 20 * unit)) &&
          approx(NSHeight(shown), MAX(NSHeight(saved) * 0.05, 20 * unit)) && NSEqualSizes(preview.frame.size, saved.size),
          @"a pinned popup outside the pane comes back into view");
    preview.frame = saved;
    [view keepPinnedLinkPreviewInView];
    check(NSEqualRects(preview.frame, saved), @"a popup in view stays where it is");

    // Unsplitting: the popup of the pane that goes away moves to the pane that stays.
    [view doKillPopup];
    show(second, NSEventModifierFlagOption);
    preview = second.preview;
    NSRect windowFrame = NSZeroRect;
    NSRect expected = [second.documentView convertRect:preview.frame toView:nil];
    check([second detachPinnedLinkPreviewWithWindowFrame:&windowFrame] == preview && NSEqualRects(windowFrame, expected),
          @"detaching gives the popup and its place in the window");
    check(!second.preview && !preview.superview && !second.handlingLink && !second.globalLongTerm && !handlers.count,
          @"the pane that gives up its popup is left without one");
    check([second detachPinnedLinkPreviewWithWindowFrame:&windowFrame] == nil, @"a pane without a pinned popup has none to give");
    [second removeFromSuperview];
    view.frame = window.contentView.bounds; [view layoutDocumentView];
    [view setTestMouseMode:NEW_MOUSE_MODE_SCROLL];
    [view attachPinnedLinkPreview:preview windowFrame:windowFrame];
    check(view.preview == preview && preview.superview == view.documentView && !view.transientPreview &&
          view.globalLongTerm && preview.pinned && handlers.count == 1, @"the pane that stays shows the moved popup pinned");
    NSRect moved = [view.documentView convertRect:preview.frame toView:nil];
    check(approx(NSMinX(moved), NSMinX(windowFrame)) && approx(NSMinY(moved), NSMinY(windowFrame)) &&
          approx(NSWidth(moved), NSWidth(windowFrame)) && approx(NSHeight(moved), NSHeight(windowFrame)),
          @"the moved popup keeps its place and size on screen");
    check(preview.usesHandTool(), @"the moved popup follows the tool of its new pane");
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    check(!preview.usesHandTool(), @"the moved popup follows a change of tool in its new pane");
    [window.contentView addSubview:second]; [second layoutDocumentView];
    show(second, NSEventModifierFlagOption);
    TSLinkPreviewView *other = second.preview;
    NSRect otherFrame = NSZeroRect;
    [second detachPinnedLinkPreviewWithWindowFrame:&otherFrame];
    [view attachPinnedLinkPreview:other windowFrame:otherFrame];
    check(view.preview == preview && !other.superview && handlers.count == 1, @"a pane keeps its own pinned popup");
    NSEvent *(^escape)(NSEvent *) = handlers.lastObject;
    check(escape(event(window,NSEventTypeKeyDown,0,@"\033",NSZeroPoint)) == nil && !view.preview && !preview.superview &&
          !handlers.count, @"Escape closes the moved popup");
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    show(view, 0);
    check([view detachPinnedLinkPreviewWithWindowFrame:&windowFrame] == nil && view.preview, @"an ordinary popup is not moved");
    [view cleanupMarqueeKeepingPinnedLinkPreview];
    check(!view.preview && !handlers.count, @"another window becoming main closes an ordinary popup");
}
// AppKit calls each local monitor with what the one before returned and stops at nil;
// try both orders, since both parts watch Escape while they show a pinned popup.
static NSEvent *dispatchEvent(NSEvent *e, BOOL lastFirst) {
    NSArray *monitors = lastFirst ? handlers.reverseObjectEnumerator.allObjects : [handlers copy];
    for (NSEvent *(^monitor)(NSEvent *) in monitors) {
        if (![handlers containsObject:monitor]) continue;
        e = monitor(e);
        if (!e) break;
    }
    return e;
}
// In a split window Escape dismisses the pinned popup of the active part only; the other
// part keeps its own (#14).
static void testSplitEscape(MyPDFKitView *view, MyPDFKitView *second, TestPreviewWindow *window) {
    NSRect bounds = window.contentView.bounds;
    view.frame = NSMakeRect(0, 0, NSWidth(bounds) / 2, NSHeight(bounds));
    second.frame = NSMakeRect(NSWidth(bounds) / 2, 0, NSWidth(bounds) / 2, NSHeight(bounds));
    [view layoutDocumentView]; [second layoutDocumentView];
    view.myPDFWindow = window; second.myPDFWindow = window;
    for (NSNumber *lastFirst in @[@YES, @NO]) {
        for (MyPDFKitView *active in @[view, second]) {
            MyPDFKitView *other = active == view ? second : view;
            for (MyPDFKitView *pinnedFirst in @[view, second]) {
                MyPDFKitView *pinnedLast = pinnedFirst == view ? second : view;
                [view doKillPopup]; [second doKillPopup];
                show(pinnedFirst, NSEventModifierFlagOption);
                show(pinnedLast, NSEventModifierFlagOption);
                flags = 0;
                TSLinkPreviewView *otherPreview = other.preview;
                window.activeView = active;
                check(handlers.count == 2 && active.preview && otherPreview, @"both parts show a pinned popup");
                NSEvent *escape = event(window, NSEventTypeKeyDown, 0, @"\033", NSZeroPoint);
                check(dispatchEvent(escape, lastFirst.boolValue) == nil, @"Escape is used by a pinned popup");
                check(!active.preview && other.preview == otherPreview && otherPreview.superview && other.globalLongTerm &&
                      handlers.count == 1, @"Escape dismisses the pinned popup of the active part, whichever was shown last");
                check(dispatchEvent(escape, lastFirst.boolValue) == escape && other.preview == otherPreview &&
                      otherPreview.superview && handlers.count == 1,
                      @"with none in the active part, Escape leaves the pinned popup of the other part");
                [other doKillPopup];
            }
            // An ordinary popup in the active part, too, leaves the pinned one in the other part.
            show(other, NSEventModifierFlagOption);
            show(active, 0);
            window.activeView = active;
            NSEvent *escape = event(window, NSEventTypeKeyDown, 0, @"\033", NSZeroPoint);
            check(dispatchEvent(escape, lastFirst.boolValue) == escape && other.preview.pinned && active.preview,
                  @"an ordinary popup in the active part leaves Escape and the pinned popup of the other part alone");
            [active doKillPopup]; [other doKillPopup];
        }
        // Without an active part in this window, as when the other window of the document has it,
        // Escape still dismisses one of the popups.
        show(view, NSEventModifierFlagOption); show(second, NSEventModifierFlagOption); flags = 0;
        window.activeView = nil;
        NSEvent *escape = event(window, NSEventTypeKeyDown, 0, @"\033", NSZeroPoint);
        check(dispatchEvent(escape, lastFirst.boolValue) == nil && handlers.count == 1 && (!view.preview) != (!second.preview),
              @"without an active part Escape dismisses one pinned popup");
        check(dispatchEvent(escape, lastFirst.boolValue) == nil && !view.preview && !second.preview && !handlers.count,
              @"and the next Escape the other");
    }
    view.frame = bounds; [view layoutDocumentView];
}
// While a popup is pinned, hovering over other links still shows their popups, above the pinned
// one; Option pins such a popup in place of the one pinned before, and moving onto the pinned
// popup dismisses a popup shown by hovering (#35).
static void testHoverWhilePinned(MyPDFKitView *view, NSWindow *window) {
    [view doKillPopup];
    view.skipLinks = NO;
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    show(view, NSEventModifierFlagOption);
    flags = 0;
    TSLinkPreviewView *pinned = view.preview;
    check(view.handlingLink == 2 && !view.transientPreview, @"pinning leaves the pointer over its link without another popup");
    NSRect visible = [view.documentView convertRect:view.documentView.visibleRect toView:nil];
    NSPoint far = NSMakePoint(NSMinX(visible) + 2, NSMinY(visible) + 2);
    view.inLink = NO;
    [view mouseMoved:mouse(window, NSEventTypeMouseMoved, far)];
    check(view.preview == pinned && pinned.superview && !view.handlingLink, @"leaving the link keeps the pinned popup");
    view.inLink = YES;
    [view mouseMoved:mouse(window, NSEventTypeMouseMoved, far)];
    check(view.handlingLink == 1, @"while a popup is pinned, hovering over a link starts its popup");
    [view handleLink:showTimer(view)];
    TSLinkPreviewView *hover = view.transientPreview;
    check(view.handlingLink == 2 && hover.superview == view.documentView && !hover.pinned && pinned.superview &&
          view.preview == pinned && handlers.count == 1, @"while a popup is pinned, hovering over a link shows its popup");
    NSArray *subviews = view.documentView.subviews;
    check([subviews indexOfObjectIdenticalTo:hover] > [subviews indexOfObjectIdenticalTo:pinned],
          @"the popup shown by hovering is above the pinned popup");
    [view killPopup:timeout(view)];
    check(!view.transientPreview && !hover.superview && pinned.superview && handlers.count == 1,
          @"the popup shown by hovering times out and the pinned popup stays");
    NSEvent *(^handler)(NSEvent *) = handlers.lastObject;
    view.handlingLink = 1;
    [view handleLink:showTimer(view)];
    hover = view.transientPreview;
    NSTimer *hoverTimeout = timeout(view);
    flags = NSEventModifierFlagOption;
    handler(event(window, NSEventTypeFlagsChanged, NSEventModifierFlagOption, @"", NSZeroPoint));
    flags = 0;
    check(view.preview == hover && hover.pinned && !pinned.superview && !view.transientPreview,
          @"pinning another popup replaces the one pinned before");
    pinned = hover;
    [view killPopup:hoverTimeout];
    check(pinned.superview && view.preview == pinned, @"a popup pinned while shown no longer times out");
    check(view.handlingLink == 2 && !view.transientPreview,
          @"pinning leaves the pointer over its link without another popup after the timeout");
    view.inLink = NO;
    [view mouseMoved:mouse(window, NSEventTypeMouseMoved, far)];
    view.handlingLink = 1;
    [view handleLink:showTimer(view)];
    check(view.transientPreview != nil, @"a second popup is shown beside the pinned one");
    [view mouseMoved:mouse(window, NSEventTypeMouseMoved, windowPoint(pinned, 20, 15))];
    check(!view.transientPreview && !view.handlingLink && pinned.superview,
          @"moving onto the pinned popup dismisses the popup shown by hovering");
    view.handlingLink = 1;
    [view handleLink:showTimer(view)];
    handler = handlers.lastObject;
    check(handler(event(window, NSEventTypeKeyDown, 0, @"\033", NSZeroPoint)) == nil && !pinned.superview &&
          view.transientPreview && handlers.count == 1, @"Escape dismisses the pinned popup and leaves the one shown by hovering");
    [view doKillPopup];
    check(!handlers.count, @"closing both popups stops watching the keyboard");
}

@interface TestOutlineItem : NSObject
@property PDFDestination *destination;
@end
@implementation TestOutlineItem
@end
@interface TestOutlineView : NSObject
@property TestOutlineItem *item;
@end
@implementation TestOutlineView
- (NSInteger)selectedRow { return 0; }
- (id)itemAtRow:(NSInteger)row { return self.item; }
@end

// Going to another place closes the pinned popup of the part that goes there: following an
// internal link, the outline, Back and Forward, a page number, the first or last page and a
// sync. Back and Forward do not bring it back. Scrolling, zoom and turning one page keep it,
// in view (#35).
static void testJumps(MyPDFKitView *view, NSWindow *window) {
    [view doKillPopup];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600,800)];
    [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,600,800)); [image unlockFocus];
    PDFDocument *doc = [PDFDocument new];
    for (NSUInteger i = 0; i < 4; i++) [doc insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    PDFPage *first = [doc pageAtIndex:0], *third = [doc pageAtIndex:2];
    PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,720,100,25) forType:PDFAnnotationSubtypeLink withProperties:nil];
    link.destination = [[PDFDestination alloc] initWithPage:third atPoint:NSMakePoint(20,600)]; [first addAnnotation:link];
    view.document = doc; view.displayMode = kPDFDisplaySinglePageContinuous; view.autoScales = NO; view.scaleFactor = 1;
    [view layoutDocumentView];
    [view setTestPageStyle:PDF_MULTI_PAGE_STYLE];
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    view.skipLinks = NO;
    flags = 0;
    void (^pin)(void) = ^{
        [view goToPage:first];
        [view.documentView scrollPoint:[view convertPoint:[view convertPoint:NSMakePoint(0, 800) fromPage:first] toView:view.documentView]];
        show(view, NSEventModifierFlagOption);
        flags = 0;
    };

    pin();
    TSLinkPreviewView *preview = view.preview;
    [view.documentView scrollPoint:NSMakePoint(0, NSMinY(view.documentView.visibleRect) - 300)];
    check(view.preview == preview && preview.superview, @"scrolling keeps the pinned popup");

    pin();
    NSPoint onLink = [view convertPoint:[view convertPoint:NSMakePoint(30, 730) fromPage:first] toView:nil];
    view.inLink = YES;
    [view setTestDownOverLink];
    [view mouseUp:mouse(window, NSEventTypeLeftMouseUp, onLink)];
    check(!view.preview && !handlers.count, @"following an internal link closes the pinned popup");

    pin();
    TestOutlineView *outline = [TestOutlineView new];
    outline.item = [TestOutlineItem new];
    [view takeDestinationFromOutline:outline];
    check(view.preview != nil, @"an outline item without a target keeps the pinned popup");
    outline.item.destination = [[PDFDestination alloc] initWithPage:third atPoint:NSMakePoint(0, 800)];
    [view takeDestinationFromOutline:outline];
    check(!view.preview && view.currentPage == third, @"the outline closes the pinned popup");

    pin();
    [view goToKitPageNumber:4];
    check(!view.preview && view.currentPage == [doc pageAtIndex:3], @"a page number closes the pinned popup");
    pin();
    [view lastPage:nil];
    check(!view.preview, @"going to the last page closes the pinned popup");
    pin();
    [view firstPage:nil];
    check(!view.preview, @"going to the first page closes the pinned popup");
    pin();
    [view setIndexForMark:2];
    check(!view.preview, @"a sync from the source closes the pinned popup");

    // Back and Forward close it and do not bring it back. The popup is shown from the first page
    // without going there, which would add to the history.
    void (^pinHere)(void) = ^{
        [view.documentView scrollPoint:[view convertPoint:[view convertPoint:NSMakePoint(0, 800) fromPage:first] toView:view.documentView]];
        show(view, NSEventModifierFlagOption);
        flags = 0;
    };
    [view goToPage:third];
    [view goToPage:first];
    pinHere();
    check(view.canGoBack && !view.canGoForward, @"PDFKit keeps the history");
    [view goBack:nil];
    check(!view.preview && !handlers.count, @"Back closes the pinned popup");
    [view goForward:nil];
    check(view.currentPage == first && !view.preview && !handlers.count, @"Forward does not bring back the pinned popup");
    [view goToPage:third];
    [view goBack:nil];
    pinHere();
    check(view.canGoForward, @"PDFKit keeps the history forward");
    [view goForward:nil];
    check(!view.preview && !handlers.count, @"Forward closes the pinned popup");
    while (view.canGoForward) [view goForward:nil];
    pin();
    while (view.canGoForward) [view goForward:nil];
    [view goForward:nil];
    check(view.preview != nil, @"Forward with nowhere to go keeps the pinned popup");

    // Zoom keeps it, in view.
    pin();
    preview = view.preview;
    NSTextField *scaleField = [NSTextField new];
    scaleField.integerValue = 300;
    [view setTestScaleField:scaleField];
    CGFloat widthBefore = NSWidth([view.documentView convertRect:preview.frame toView:nil]);
    [view changeScale:view];
    check(approx(view.scaleFactor, 3) && view.preview == preview && preview.superview && handlers.count == 1,
          @"zoom keeps the pinned popup");
    check(fabs(NSWidth([view.documentView convertRect:preview.frame toView:nil]) - 3 * widthBefore) < 1,
          @"the pinned popup grows with the page");
    check(NSIntersectsRect(preview.frame, view.documentView.visibleRect), @"after zoom the pinned popup is in view");
    scaleField.integerValue = 50;
    [view changeScale:view];
    check(view.preview == preview && NSIntersectsRect(preview.frame, view.documentView.visibleRect),
          @"zooming out keeps the pinned popup in view");
    [view setTestScaleField:nil];
    view.scaleFactor = 1;

    // Turning one page keeps it, also in Single Page display.
    for (NSNumber *style in @[@(PDF_MULTI_PAGE_STYLE), @(PDF_SINGLE_PAGE_STYLE)]) {
        [view setTestPageStyle:style.integerValue];
        view.displayMode = style.integerValue == PDF_SINGLE_PAGE_STYLE ? kPDFDisplaySinglePage : kPDFDisplaySinglePageContinuous;
        [view layoutDocumentView];
        pin();
        preview = view.preview;
        [view nextPage:nil];
        check(view.preview == preview && preview.superview, @"the next page keeps the pinned popup");
        [view previousPage:nil];
        check(view.preview == preview && preview.superview, @"the previous page keeps the pinned popup");
    }
    [view setTestPageStyle:PDF_MULTI_PAGE_STYLE];
    view.displayMode = kPDFDisplaySinglePageContinuous;
    [view doKillPopup];
    view.inLink = NO;
}
// Control reverses Link Popups for the link under the pointer: with it on, hovering with
// Control shows nothing, and with it off, hovering with Control shows the popup. The other
// keys keep their meanings: Command the larger popup, Shift above the link, Option pinned.
// Command alone shows nothing while Link Popups is off (#30).
static void testControlHover(MyPDFKitView *view, NSWindow *window) {
    [view doKillPopup];
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    // In the continuous display Shift keeps the popup above the link even where it does not fit.
    PDFDisplayMode previousMode = view.displayMode;
    view.displayMode = kPDFDisplaySinglePageContinuous; view.autoScales = YES; [view layoutDocumentView];
    linkPoint = NSMakePoint(30,730);
    NSRect visible = [view.documentView convertRect:view.documentView.visibleRect toView:nil];
    NSPoint away = NSMakePoint(NSMinX(visible) + 3, NSMinY(visible) + 3);
    const NSEventModifierFlags C = NSEventModifierFlagCommand, S = NSEventModifierFlagShift,
        O = NSEventModifierFlagOption, K = NSEventModifierFlagControl;
    // The combinations without Control come first, so that the popups they give with link
    // popups on are known when Control brings the same popups with link popups off.
    NSEventModifierFlags combinations[] = {0, S, O, S|O, C, C|S, C|O, C|S|O, K, K|S, K|O, K|S|O, K|C, K|C|S, K|C|O};
    const int count = sizeof(combinations) / sizeof(combinations[0]);
    NSMutableDictionary<NSNumber *, NSValue *> *framesWithPopupsOn = [NSMutableDictionary new];
    for (NSNumber *popupsOn in @[@YES, @NO]) {
        view.skipLinks = !popupsOn.boolValue;
        for (int c = 0; c < count; c++) {
            NSEventModifierFlags m = combinations[c];
            BOOL control = (m & K) != 0;
            BOOL shows = popupsOn.boolValue != control;
            // The pointer moves onto the link with the keys held down.
            view.inLink = YES; view.handlingLink = 0;
            flags = m; eventFlags = m;
            [view mouseMoved:event(window, NSEventTypeMouseMoved, m, @"", away)];
            NSString *starts = popupsOn.boolValue
                ? (control ? @"with link popups on, hovering with Control starts no popup"
                           : @"with link popups on, hovering without Control starts a popup")
                : (control ? @"with link popups off, hovering with Control starts a popup"
                           : ((m & C) ? @"with link popups off, hovering with Command alone starts no popup"
                                      : @"with link popups off, hovering without Control starts no popup"));
            check((view.handlingLink == 1) == shows, starts);
            if (!shows) {
                // Nor does a popup that is somehow pending appear while the keys are held.
                view.handlingLink = 1;
                [view handleLink:showTimer(view)];
                check(!view.preview && !view.handlingLink,
                      popupsOn.boolValue ? @"with link popups on, no popup appears with Control"
                                         : @"with link popups off, no popup appears without Control");
                flags = 0; eventFlags = 0;
                continue;
            }
            [view handleLink:showTimer(view)];
            check(view.handlingLink == 2 && view.preview.superview == view.documentView,
                  popupsOn.boolValue ? @"with link popups on, hovering without Control shows the popup"
                                     : @"with link popups off, hovering with Control shows the popup");
            check(view.preview.pinned == ((m & O) != 0), @"Option pins a popup, also one shown with Control");
            NSRect frame = view.preview.frame;
            if (popupsOn.boolValue)
                framesWithPopupsOn[@(m)] = [NSValue valueWithRect:frame];
            else
                check(NSEqualRects(frame, framesWithPopupsOn[@(m & ~K)].rectValue),
                      @"with link popups off, Control and the other keys give the popup those keys give with link popups on");
            flags = 0; eventFlags = 0;
            if (m & O) {
                // A pinned popup keeps new popups away, whatever the keys.
                view.inLink = YES;
                flags = m; eventFlags = m;
                [view mouseMoved:event(window, NSEventTypeMouseMoved, m, @"", away)];
                flags = 0; eventFlags = 0;
                check(view.preview && view.handlingLink == 2 && view.globalLongTerm,
                      @"a pinned popup keeps new popups away, also with Control");
                [view doKillPopup];
            } else {
                // Moving on within the link keeps the popup once the keys are released;
                // leaving the link dismisses it.
                [view mouseMoved:event(window, NSEventTypeMouseMoved, 0, @"", away)];
                check(view.preview && view.handlingLink == 2, @"moving within the link keeps a popup after the keys are released");
                view.inLink = NO;
                [view mouseMoved:event(window, NSEventTypeMouseMoved, 0, @"", away)];
                check(!view.preview && !view.handlingLink && !handlers.count,
                      popupsOn.boolValue ? @"leaving the link dismisses the popup"
                                         : @"leaving the link dismisses a popup shown with Control");
            }
        }
    }
    NSRect plain = framesWithPopupsOn[@0].rectValue, larger = framesWithPopupsOn[@(C)].rectValue,
        above = framesWithPopupsOn[@(S)].rectValue;
    check(NSWidth(larger) > NSWidth(plain) && NSHeight(larger) > NSHeight(plain), @"Command gives the larger popup");
    check(view.documentView.isFlipped ? NSMinY(above) < NSMinY(plain) : NSMinY(above) > NSMinY(plain),
          @"Shift puts the popup above the link");

    // With link popups on, Control pressed after the pointer reaches the link, before the
    // popup appears, keeps it away; with Control released and the pointer moved on, it comes.
    view.skipLinks = NO; view.inLink = YES; view.handlingLink = 0;
    [view mouseMoved:event(window, NSEventTypeMouseMoved, 0, @"", away)];
    NSTimer *pending = showTimer(view);
    flags = K; eventFlags = K;
    [view handleLink:pending];
    check(!view.preview && !view.handlingLink, @"with link popups on, pressing Control before the popup appears keeps it away");
    [view mouseMoved:event(window, NSEventTypeMouseMoved, K, @"", away)];
    check(!view.handlingLink, @"moving on with Control held starts no popup");
    flags = 0; eventFlags = 0;
    [view mouseMoved:event(window, NSEventTypeMouseMoved, 0, @"", away)];
    check(view.handlingLink == 1, @"moving on after Control is released starts the popup");
    [view handleLink:showTimer(view)];
    check(view.preview != nil, @"the popup appears without Control");
    [view doKillPopup];

    // With link popups off, Control released before the popup appears leaves it out; pressing
    // it again over the link brings it, and it goes like any other popup.
    view.skipLinks = YES; view.inLink = YES; view.handlingLink = 0;
    flags = K; eventFlags = K;
    [view mouseMoved:event(window, NSEventTypeMouseMoved, K, @"", away)];
    pending = showTimer(view);
    flags = 0; eventFlags = 0;
    [view handleLink:pending];
    check(!view.preview && !view.handlingLink, @"releasing Control before the popup appears shows none");
    [view mouseMoved:event(window, NSEventTypeMouseMoved, 0, @"", away)];
    check(!view.handlingLink, @"moving on without Control starts no popup");
    flags = K; eventFlags = K;
    [view mouseMoved:event(window, NSEventTypeMouseMoved, K, @"", away)];
    check(view.handlingLink == 1, @"pressing Control again over the link starts the popup");
    [view handleLink:showTimer(view)];
    flags = 0; eventFlags = 0;
    check(view.preview != nil, @"the popup appears with Control held");
    [view killPopup:timeout(view)];
    check(!view.preview && !view.handlingLink && !handlers.count, @"a popup shown with Control goes after its time");
    // Option pins it once it is shown, as with link popups on.
    flags = K; eventFlags = K;
    [view mouseMoved:event(window, NSEventTypeMouseMoved, K, @"", away)];
    [view handleLink:showTimer(view)];
    flags = NSEventModifierFlagOption; eventFlags = 0;
    NSEvent *(^handler)(NSEvent *) = handlers.lastObject;
    handler(event(window, NSEventTypeFlagsChanged, NSEventModifierFlagOption, @"", NSZeroPoint));
    flags = 0;
    check(view.preview.pinned && view.globalLongTerm, @"Option pins a popup shown with Control");
    [view killPopup:timeout(view)];
    check(view.preview != nil, @"a pinned popup shown with Control stays after its time");
    check(handler(event(window, NSEventTypeKeyDown, 0, @"\033", NSZeroPoint)) == nil && !view.preview,
          @"Escape dismisses a pinned popup shown with Control");
    // Switching link popups on and off again closes such a pinned popup, as before.
    flags = K|O; eventFlags = K|O;
    [view mouseMoved:event(window, NSEventTypeMouseMoved, K|O, @"", away)];
    [view handleLink:showTimer(view)];
    flags = 0; eventFlags = 0;
    [view changeLinkPopups];
    check(view.preview && !view.skipLinks, @"switching link popups on keeps a popup shown with Control");
    [view changeLinkPopups];
    check(!view.preview && !handlers.count && view.skipLinks, @"switching link popups off closes it");
    // The Select PDF tool shows no popups, also with Control.
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_PDF];
    flags = K; eventFlags = K;
    [view mouseMoved:event(window, NSEventTypeMouseMoved, K, @"", away)];
    flags = 0; eventFlags = 0;
    check(!view.handlingLink, @"the Select PDF tool shows no popups, also with Control");
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    view.inLink = NO; view.skipLinks = NO;
    [view doKillPopup];
    view.displayMode = previousMode; [view layoutDocumentView];
}
// In a split window both parts follow the document's Link Popups. With it off, Control shows
// a popup in the part under the pointer only; with it on, Control keeps it away there (#30).
static void testSplitControlHover(MyPDFKitView *view, MyPDFKitView *second, NSWindow *window) {
    TestDocument *document = [TestDocument new];
    view.myDocument = document; second.myDocument = document;
    document.myPDFKitView = view; document.myPDFKitView2 = second;
    for (NSNumber *popupsOn in @[@NO, @YES]) {
        document.linkPopups = popupsOn.boolValue;
        check(view.skipLinks == !popupsOn.boolValue && second.skipLinks == !popupsOn.boolValue,
              @"both parts follow Link Popups");
        [view doKillPopup]; [second doKillPopup];
        for (MyPDFKitView *pane in @[view, second]) {
            MyPDFKitView *other = pane == view ? second : view;
            NSRect visible = [pane.documentView convertRect:pane.documentView.visibleRect toView:nil];
            NSPoint inside = NSMakePoint(NSMinX(visible) + 3, NSMinY(visible) + 3);
            pane.inLink = YES; other.inLink = NO;
            NSEventModifierFlags still = popupsOn.boolValue ? NSEventModifierFlagControl : 0;
            NSEventModifierFlags brings = popupsOn.boolValue ? 0 : NSEventModifierFlagControl;
            flags = still; eventFlags = still;
            [pane mouseMoved:event(window, NSEventTypeMouseMoved, still, @"", inside)];
            flags = 0; eventFlags = 0;
            check(!pane.handlingLink, popupsOn.boolValue ? @"in a split window, no popup appears with Control"
                                                         : @"in a split window, no popup appears without Control");
            flags = brings; eventFlags = brings;
            [pane mouseMoved:event(window, NSEventTypeMouseMoved, brings, @"", inside)];
            [pane handleLink:showTimer(pane)];
            flags = 0; eventFlags = 0;
            check(pane.preview && !other.preview && !other.handlingLink,
                  @"in a split window, the popup appears in the part under the pointer");
            pane.inLink = NO;
            [pane mouseMoved:event(window, NSEventTypeMouseMoved, 0, @"", inside)];
            check(!pane.preview, @"in a split window, leaving the link dismisses that popup");
        }
    }
    view.myDocument = nil; second.myDocument = nil;
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    installFakeToolTip();
    handlers = [NSMutableArray new];
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(modifierFlags)), (IMP)currentFlags);
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(mouseLocation)), (IMP)currentMouse);
    TSReplaceTestMethod(class_getInstanceMethod(NSApplication.class,@selector(currentEvent)), (IMP)currentEvent);
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(addLocalMonitorForEventsMatchingMask:handler:)), (IMP)addMonitor);
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(removeMonitor:)), (IMP)removeMonitor);
    testPasteboard = [NSPasteboard pasteboardWithUniqueName];
    TSReplaceTestMethod(class_getClassMethod(NSPasteboard.class,@selector(generalPasteboard)), (IMP)generalPasteboard);
    TestPreviewWindow *window = [[TestPreviewWindow alloc] initWithContentRect:NSMakeRect(0,0,650,850) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSWindow *otherWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,850) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO; otherWindow.releasedWhenClosed = NO;
    MyPDFKitView *view = [[MyPDFKitView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:view];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600,800)];
    [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,600,800)); [image unlockFocus];
    PDFDocument *doc = [PDFDocument new];
    PDFPage *page = [[PDFPage alloc] initWithImage:image]; [doc insertPage:page atIndex:0];
    PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,720,100,25) forType:PDFAnnotationSubtypeLink withProperties:nil];
    link.destination = [[PDFDestination alloc] initWithPage:page atPoint:NSMakePoint(20,600)]; [page addAnnotation:link];
    view.document = doc; view.autoScales = YES; [view layoutDocumentView];
    testInteraction(view, window);
    testTools(view, window, textDocument());
    testCursorOutside(view, window);
    testPageLabelAndToolTips(view, window, textDocument());
    testDocumentLinkPopups(view, window, doc);
    view.document = doc; [view layoutDocumentView];
    testControlHover(view, window);
    testHoverWhilePinned(view, window);
    testJumps(view, window);
    view.document = doc; view.autoScales = YES; [view layoutDocumentView];
    {
        // A second pane beside the first, as when the window is split.
        NSRect bounds = window.contentView.bounds;
        view.frame = NSMakeRect(0, 0, NSWidth(bounds) / 2, NSHeight(bounds));
        MyPDFKitView *second = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(NSWidth(bounds) / 2, 0, NSWidth(bounds) / 2, NSHeight(bounds))];
        [window.contentView addSubview:second];
        second.document = doc; second.autoScales = YES; [view layoutDocumentView]; [second layoutDocumentView];
        testKeepingPinned(view, second, window);
        testSplitEscape(view, second, window);
        testSplitControlHover(view, second, window);
        [second removeFromSuperview];
        view.frame = bounds; [view layoutDocumentView];
    }
    testPopupSide(view, window);
    testNextPage(view, window);
    show(view, 0);
    for (NSNumber *modifier in @[@0,@(NSEventModifierFlagOption)]) {
        NSEvent *escape = event(window,NSEventTypeKeyDown,modifier.unsignedIntegerValue,@"\033",NSZeroPoint);
        NSEvent *(^normalHandler)(NSEvent *) = handlers.lastObject;
        check(normalHandler(escape) == escape && view.preview, @"ordinary popup leaves Escape for editor and search");
    }
    flags = NSEventModifierFlagOption;
    check(!view.globalLongTerm, @"ordinary hover is not pinned");
    [view killPopup:timeout(view)];
    check(!view.preview && !view.handlingLink && !handlers.count, @"ordinary timeout removes overlay and monitor");
    show(view, 0);
    [view mouseMoved:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    check(!view.preview, @"ordinary move away dismisses");
    show(view, NSEventModifierFlagOption);
    flags = 0;
    check(view.globalLongTerm, @"Option at show pins");
    NSTimer *oldTimeout = timeout(view);
    for (NSNumber *inLink in @[@NO,@YES]) {
        view.inLink = inLink.boolValue;
        [view mouseMoved:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
        check(view.globalLongTerm && view.preview, @"pinned popup survives pointer on or off links");
    }
    [view killPopup:oldTimeout]; check(view.preview != nil, @"pin survives timeout and modifier release");
    NSEvent *(^handler)(NSEvent *) = handlers.lastObject;
    NSEvent *foreignEscape = event(otherWindow,NSEventTypeKeyDown,0,@"\033",NSZeroPoint);
    check(handler(foreignEscape) == foreignEscape && view.preview, @"other windows retain Escape");
    for (NSNumber *modifier in @[@(NSEventModifierFlagOption),@(NSEventModifierFlagCommand),@(NSEventModifierFlagControl),@(NSEventModifierFlagShift)]) {
        NSEvent *escape = event(window,NSEventTypeKeyDown,modifier.unsignedIntegerValue,@"\033",NSZeroPoint);
        check(handler(escape) == escape && view.preview, @"modified Escape is not consumed even when pinned");
    }
    NSEvent *ordinaryKey = event(window,NSEventTypeKeyDown,0,@"a",NSZeroPoint);
    check(handler(ordinaryKey) == ordinaryKey, @"ordinary keys pass through");
    check(handler(event(window,NSEventTypeKeyDown,0,@"\033",NSZeroPoint)) == nil, @"Escape consumed in owner window");
    check(!view.preview && !view.globalLongTerm && !handlers.count, @"Escape clears state and monitor");
    show(view, 0);
    [view killPopup:oldTimeout]; check(view.preview != nil, @"old timer cannot dismiss newer popup");
    handler = handlers.lastObject;
    NSEvent *option = event(window,NSEventTypeFlagsChanged,NSEventModifierFlagOption,@"",NSZeroPoint);
    check(handler(option) == option && view.globalLongTerm, @"Option after show pins without consuming modifier");
    handler(event(window,NSEventTypeFlagsChanged,0,@"",NSZeroPoint));
    check(view.globalLongTerm, @"releasing Option leaves pin");
    [view changeLinkPopups]; check(!view.preview && !handlers.count && view.skipLinks, @"disabling popups clears pin");
    [view changeLinkPopups];
    view.handlingLink = 1;
    NSTimer *pending = showTimer(view);
    [view doKillPopup]; [view handleLink:pending];
    check(!view.preview && !view.handlingLink, @"cancelled pending timer cannot recreate popup");
    show(view,NSEventModifierFlagOption);
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:otherWindow];
    check(view.preview != nil, @"other window closing has no effect");
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:window];
    check(!view.preview && !handlers.count, @"owner close cleans overlay and monitor");
    show(view,NSEventModifierFlagOption);
    view.document = doc;
    check(!view.preview && !handlers.count, @"PDF reload clears popup and monitor");
    show(view,NSEventModifierFlagOption);
    [view cleanupMarquee:YES];
    check(!view.preview && !view.handlingLink && !view.globalLongTerm && !handlers.count, @"cleanupMarquee clears popup state and monitor");
    flags=0; view.inLink=YES;
    [view mouseMoved:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    check(view.handlingLink == 1, @"hover resumes after cleanupMarquee");
    [view handleLink:showTimer(view)];
    check(view.preview != nil, @"next hover displays overlay after cleanupMarquee");
    [view doKillPopup];
    show(view,0);
    [view mouseDown:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    check(!view.preview && !view.handlingLink && !handlers.count, @"click clears an ordinary popup and monitor before annotation handling");
    show(view,NSEventModifierFlagOption);
    cleanupInClick = YES;
    [view mouseDown:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    cleanupInClick = NO;
    check(view.preview && view.preview.superview && view.globalLongTerm && handlers.count == 1,
          @"click outside keeps a pinned popup, also through the marquee cleanup");
    [view cleanupMarquee:YES];
    check(!view.preview && !handlers.count, @"cleanup outside a click still clears a pinned popup");
    show(view,NSEventModifierFlagOption);
    [SUD registerDefaults:@{LinkPopupsKey:@YES}];
    [view initializeDisplay];
    check(!view.preview && !view.handlingLink && !handlers.count, @"initializeDisplay clears popup and monitor");
    // The Settings switch is the default that a newly shown preview starts with.
    check(!view.skipLinks, @"a preview starts with link popups on by default");
    [SUD setBool:NO forKey:LinkPopupsKey]; [view initializeDisplay];
    check(view.skipLinks, @"a preview starts with link popups off when the setting is off");
    [SUD removeObjectForKey:LinkPopupsKey]; [view initializeDisplay];
    view.handlingLink=1; NSTimer *beforeInitialize=showTimer(view);
    [view initializeDisplay];
    view.handlingLink=1; [view handleLink:beforeInitialize];
    check(!view.preview, @"initializeDisplay invalidates pending timer");
    [view doKillPopup];
    show(view,NSEventModifierFlagOption);
    [view removeFromSuperview];
    check(!view.preview && !handlers.count, @"detaching view clears popup");
    [testPasteboard releaseGlobally];
    printf("PASS: %lu popup event/lifecycle checks\n", (unsigned long)checks);
    return 0;
}}
'''.replace('DOCUMENTMETHODS', document_methods).replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-pinned-link-') as directory:
    temporary = Path(directory)
    native = temporary / 'probe.m'
    native.write_text(program)
    preview_file = temporary / 'TSLinkPreviewView.m'
    preview_file.write_text(preview_source)
    exe = temporary / 'probe'
    subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',
                    *include_args(root),'-I'+str(root/'Tests'),str(native),
                    str(root/'Sources/Preview/OverView.m'),str(preview_file),str(root/'Sources/Preview/TSPreviewScrollerKeeper.m'),'-o',str(exe)],check=True)
    home = temporary/'home'
    (home/'Library/Preferences').mkdir(parents=True)
    # Two empty pages with a PageLabels tree: i, then 157.
    objects = [b'<< /Type /Catalog /Pages 2 0 R /PageLabels << /Nums [0 << /S /r >> 1 << /S /D /St 157 >>] >> >>',
               b'<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << >> >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << >> >>']
    pdf = bytearray(b'%PDF-1.4\n'); offsets = []
    for number, body in enumerate(objects, 1):
        offsets.append(len(pdf)); pdf += b'%d 0 obj\n' % number + body + b'\nendobj\n'
    xref = len(pdf)
    pdf += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1) + b''.join(b'%010d 00000 n \n' % o for o in offsets)
    pdf += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objects) + 1, xref)
    (temporary / 'labeled.pdf').write_bytes(bytes(pdf))
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TS_LABELED_PDF=str(temporary / 'labeled.pdf'))
    result = subprocess.run([str(exe)], env=env, capture_output=True, text=True, timeout=30)
    print(result.stdout, end='')
    if args.mutation:
        expected = {'move-dismisses':('pinned popup survives', 'edge of the popup shows a resize cursor', 'leaving the link keeps the pinned popup'), 'stale-timer':('old timer cannot dismiss', 'pinning leaves the pointer over its link without another popup after the timeout'),
                    'other-window':'other windows retain Escape', 'cleanup-state':('cleanupMarquee clears', 'after a failed click, cleanup outside a click dismisses'),
                    'ordinary-escape':('ordinary popup leaves Escape', 'an ordinary popup in the active part leaves Escape'), 'modified-escape':'modified Escape is not consumed',
                    'click-cleanup':'click clears an ordinary popup', 'initialize-cleanup':'initializeDisplay clears popup',
                    'click-kills-pin':('click outside keeps a pinned popup', 'clicking the preview keeps the popup'),
                    'cleanup-in-click-kills-pin':('click outside keeps a pinned popup', 'clicking the preview keeps the popup'),
                    'cursor-not-restored':"leaving the popup shows the tool's cursor", 'hand-selects':'with the hand tool the whole popup moves',
                    'no-selection':'dragging over text selects it', 'move-confined':'moved popup keeps only a small part',
                    'copy-ignores-popup':'Copy copies the popup selection',
                    'toggle-keeps-popup':'switching link popups off closes a pinned popup',
                    'link-popups-per-view':('a pane added by splitting matches', 'the first PDF uses the value from when the document was opened'),
                    'reads-settings-again':'the first PDF uses the value from when the document was opened',
                    'tool-change-kills-pin':'changing the tool keeps a pinned popup', 'flag-not-restored':'after a failed click',
                    'click-keeps-focus':'clicking the popup makes its preview the active view', 'click-keeps-selection':'a click away from text clears',
                    'no-page-label':'page label is drawn in the lower right corner', 'label-unscaled':'page label keeps its size on screen',
                    'tooltip-kept':'internal link gets no PDFKit tool tip', 'tooltip-trusts-data':'user data that is not the link',
                    'label-from-index':'popup shows the label of the linked page', 'tooltip-always-hidden':'tool tip stays when link popups are off',
                    'unpinned-interactive':'hovering popup leaves the mouse', 'pinned-transparent':'pinned popup takes clicks',
                    'scroll-chains':'scrolling the popup leaves the preview', 'scroll-moves-frame':'scrolling leaves the popup in place', 'option-not-forwarded':'Option while shown makes',
                    'kill-leaves-view':'closing removes the popup view', 'cursor-overridden':'shows an open hand',
                    'resize-scales':'resizing keeps the text size',
                    'magnifier-kills-pin':'a click with the magnifying glass keeps a pinned popup',
                    'switch-kills-pin':('another window becoming main keeps a pinned popup', 'zoom keeps the pinned popup'),
                    'keep-marquee':'another window becoming main still removes the marquee',
                    'contains-unpinned':'an ordinary popup is not moved',
                    'contains-hidden-part':'the hidden part of a pinned popup is not taken for a click',
                    'detach-keeps-state':'the pane that gives up its popup is left without one',
                    'attach-keeps-old-tool':'the moved popup follows the tool of its new pane',
                    'attach-replaces-pin':'a pane keeps its own pinned popup',
                    'not-kept-in-view':('a pinned popup outside the pane comes back into view', 'after zoom the pinned popup is in view'),
                    'drag-cursor-stays':'releasing the edge over the toolbar shows the arrow',
                    'hidden-part-cursor':'releasing a moved popup over the toolbar shows the arrow',
                    'no-exit-tracking':'the popup watches the pointer leave it',
                    'exit-ignored':'leaving the popup straight onto the toolbar shows the arrow',
                    'outside-always-arrow':"releasing a drag in the preview outside the popup shows the tool's cursor",
                    'visible-beyond-bounds':'releasing the edge over the toolbar shows the arrow',
                    'escape-ignores-active-part':'Escape dismisses the pinned popup of the active part',
                    'escape-falls-to-other-part':'with none in the active part, Escape leaves the pinned popup of the other part',
                    'escape-closes-hover':'Escape dismisses the pinned popup and leaves the one shown by hovering',
                    'pinned-blocks-hover':('while a popup is pinned, hovering over a link starts its popup', 'leaving the link keeps the pinned popup'),
                    'pin-keeps-old':'pinning another popup replaces the one pinned before',
                    'over-pin-keeps-hover':'moving onto the pinned popup dismisses the popup shown by hovering',
                    'pin-times-out':'pinning leaves the pointer over its link without another popup after the timeout',
                    'link-keeps-pin':'following an internal link closes the pinned popup',
                    'outline-keeps-pin':'the outline closes the pinned popup',
                    'empty-outline-kills-pin':'an outline item without a target keeps the pinned popup',
                    'back-keeps-pin':'Back closes the pinned popup',
                    'forward-keeps-pin':'Forward closes the pinned popup',
                    'stuck-back-kills-pin':'Forward with nowhere to go keeps the pinned popup',
                    'page-number-keeps-pin':'a page number closes the pinned popup',
                    'last-page-keeps-pin':'going to the last page closes the pinned popup',
                    'sync-keeps-pin':'a sync from the source closes the pinned popup',
                    'zoom-kills-pin':'zoom keeps the pinned popup',
                    'next-page-kills-pin':'the next page keeps the pinned popup',
                    'popup-side-fitted':('in the continuous displays the popup stays below the link, or above it with Shift', 'Shift puts the popup above the link'),
                    'popup-side-always-kept':'in Single Page and Double Page display a popup that does not fit moves to the other side',
                    'no-next-page':'in the continuous displays the popup goes on with the next page',
                    'selection-first-page':('the text of the next page shows an I-beam', 'text can be selected across the two pages'),
                    'control-ignored-when-off':('with link popups off, hovering with Control starts a popup', 'with link popups off, Control leaves out the tool tip'),
                    'control-ignored-when-on':('with link popups on, hovering with Control starts no popup', 'with link popups on, Control lets the tool tip through'),
                    'command-still-shows':('with link popups off, hovering with Command alone starts no popup', 'with link popups off, Command alone keeps the tool tip'),
                    'control-popup-stays':'leaving the link dismisses a popup shown with Control',
                    'timer-ignores-release':('with link popups on, pressing Control before the popup appears keeps it away', 'releasing Control before the popup appears shows none'),
                    'tooltip-ignores-control':'with link popups off, Control leaves out the tool tip',
                    'tooltip-back-under-popup':'a popup shown with Control keeps the tool tip away'}[args.mutation]
        if isinstance(expected, str): expected = (expected,)
        assert result.returncode == 1 and any(message in result.stderr for message in expected), result.stderr
        print('PASS: detected mutation ' + args.mutation)
    else:
        if result.returncode: print(result.stderr)
        result.check_returncode()
