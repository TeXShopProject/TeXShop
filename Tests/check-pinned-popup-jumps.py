#!/usr/bin/env python3
"""Check that the ways to go to another place keep the pinned link popup of the part that
goes there at its place on its page, bringing it into view only when its page is no longer
shown, and that zoom, the magnification menu, the display format and turning one page keep it
too (#35): the magnification leaves it at its place on its page and a new display format
puts it back there (#56). run-pinned-link-preview.py runs the ways that MyPDFKitView handles itself;
this checks the ways that go through the document, the search and the preview window."""
from pathlib import Path
import argparse
import re

MUTATIONS = {
    # The behavior up to 6.00 beta 5: going to another place closed the pinned popup.
    'search-closes-pin': ('Sources/Preview/MyPDFKitView.m', '- (void) doFindAgain',
                          'activeView keepPinnedLinkPreviewThroughMove];', 'activeView closePinnedLinkPreview];'),
    'search-list-closes-pin': ('Sources/Preview/MyPDFKitView.m', '- (void) tableViewSelectionDidChange:',
                               '[self keepPinnedLinkPreviewThroughMove];', '[self closePinnedLinkPreview];'),
    'mark-closes-pin': ('Sources/Preview/MyPDFKitView.m', '- (void)setIndexForMark:',
                        '[self keepPinnedLinkPreviewThroughMove];', '[self closePinnedLinkPreview];'),
    'back-closes-pin': ('Sources/Preview/MyPDFKitView.m', '- (void) goBack:',
                        '[self keepPinnedLinkPreviewThroughMove];', '[self closePinnedLinkPreview];'),
    'link-closes-pin': ('Sources/Preview/MyPDFKitView.m', '- (void) mouseUp:',
                        '[self keepPinnedLinkPreviewThroughMove];', '[self closePinnedLinkPreview];'),
    'sync-marks-other-part': ('Sources/Sync/TSDocument-SyncConTeXt.m', '- (BOOL)finishForwardContextSync',
                              'self.pdfKitWindow.activeView setIndexForMark', 'self.myPDFKitView setIndexForMark'),
    'link-part-closes': ('Sources/Windows/TSPreviewWindow.m', '- (void)showLinkDestination:',
                         '    [otherView keepPinnedLinkPreviewThroughMove];\n', '    [otherView closePinnedLinkPreview];\n'),
    'link-part-wrong': ('Sources/Windows/TSPreviewWindow.m', '- (void)showLinkDestination:',
                        '    [otherView keepPinnedLinkPreviewThroughMove];\n', '    [linkView keepPinnedLinkPreviewThroughMove];\n'),
    # e74cc066: the page number box cleaned up the selection with the pinned popup.
    'page-box-kills-pin': ('Sources/Preview/MyPDFKitView.m', '- (void) goToKitPage: (id)sender',
                           '\t\t[self cleanupMarqueeKeepingPinnedLinkPreview];\n', '\t\t[self cleanupMarquee: YES];\n'),
    # The popup takes its place before the move but never goes back to it.
    'move-not-restored': ('Sources/Preview/MyPDFKitView.m', '- (void)keepPinnedLinkPreviewThroughMove',
                          '            [view endKeepingPinnedLinkPreviewOnPage: YES];\n', '            ;\n'),
    # d8aa5c5a: turning one page moved the popup into view without taking its place first.
    'page-turn-in-view': ('Sources/Preview/MyPDFKitView.m', '- (void) nextPage:',
                          '\t[self keepPinnedLinkPreviewThroughMove];\n', ''),
    # e7623b40: a drag held at an edge, which changes nothing, forgot the place the popup is away from.
    'held-drag-forgets-place': ('Sources/Preview/TSLinkPreviewView.m', '- (void)mouseDragged:',
                                '    if (!NSEqualRects(frame, self.frame) || !NSEqualRects(source, _source)) _awayFromPlace = NO;\n', '    _awayFromPlace = NO;\n'),
    'fit-kills-pin': ('Sources/Preview/MyPDFKitView.m', '- (void)changePDFViewSizeTo:',
                      '        [self cleanupMarqueeKeepingPinnedLinkPreview];\n', '        [self cleanupMarquee: YES];\n'),
    # The behavior before #56: the magnification moved the popup into view, off its place.
    'zoom-kept-in-view': ('Sources/Preview/MyPDFKitView.m', '- (void) changeScale:',
                          '\tresizeOption = NEW_PDF_FIT_TO_NONE;\n', '\tresizeOption = NEW_PDF_FIT_TO_NONE;\n\t[self keepPinnedLinkPreviewInView];\n'),
    'fit-kept-in-view': ('Sources/Preview/MyPDFKitView.m', '- (void)changePDFViewSizeTo:',
                         '        [self setupMagnificationStyle];\n', '        [self setupMagnificationStyle];\n        [self keepPinnedLinkPreviewInView];\n'),
    'format-forgets-page': ('Sources/Preview/MyPDFKitView.m', '- (BOOL)beginKeepingPinnedLinkPreviewOnPage',
                            '    [pinnedLinkPreview rememberPlaceOnPage];\n', ''),
    'format-not-kept-in-view': ('Sources/Preview/MyPDFKitView.m', '- (void)endKeepingPinnedLinkPreviewOnPage:',
                                '        [pinnedLinkPreview keepInView];\n', '        ;\n'),
    'format-ends-early': ('Sources/Preview/MyPDFKitView.m', '- (void)performPreviewLayoutChange:',
                          '    BOOL keepsPopup = [self beginKeepingPinnedLinkPreviewOnPage];\n    change();\n',
                          '    BOOL keepsPopup = [self beginKeepingPinnedLinkPreviewOnPage];\n    change();\n    [self endKeepingPinnedLinkPreviewOnPage: keepsPopup];\n'),
    'contextual-format-loses-page': ('Sources/Preview/MyPDFKitView.m', '- (void)setDisplayMode:',
                                     '    BOOL keepsPopup = [self beginKeepingPinnedLinkPreviewOnPage];\n', '    BOOL keepsPopup = NO;\n'),
    'nested-change-returns': ('Sources/Preview/MyPDFKitView.m', '- (BOOL)beginKeepingPinnedLinkPreviewOnPage',
                              'if (keepsPinnedLinkPreviewOnPage || ![self hasPinnedLinkPreview]) return NO;',
                              'if (![self hasPinnedLinkPreview]) return NO;'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
sources = {}
def source(name):
    if name not in sources:
        sources[name] = (root / name).read_text(encoding='latin1')
    return sources[name]
if args.mutation:
    name, signature, old, new = MUTATIONS[args.mutation]
    text = source(name)
    start = text.index(signature)
    end = text.index('\n}\n', start) + 1
    body = text[start:end]
    assert body.count(old) >= 1, args.mutation
    sources[name] = text[:start] + body.replace(old, new) + text[end:]

def code(text):
    # Comments out, line breaks kept.
    text = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)
def methods(text):
    text = code(text)
    starts = [m.start() for m in re.finditer(r'^[-+] *\(', text, re.M)] + [len(text)]
    for a, b in zip(starts, starts[1:]):
        yield text[a:b].split('\n')[0], text[a:b]
def method(name, signature):
    found = [body for head, body in methods(source(name)) if head.startswith(signature)]
    assert len(found) == 1, (name, signature, len(found))
    return found[0]

problems = []
def expect(ok, message):
    if not ok:
        problems.append(message)

kit = 'Sources/Preview/MyPDFKitView.m'
# Going to another place keeps the pinned popup: its place on its page is taken before the move,
# and it goes back there once the move is done, in the next pass of the main queue, or into view
# when its page is no longer shown.
keep = method(kit, '- (void)keepPinnedLinkPreviewThroughMove')
expect(re.search(r'if \(!\[self beginKeepingPinnedLinkPreviewOnPage\]\) return;', keep) and
       re.search(r'dispatch_async\(dispatch_get_main_queue\(\), \^\{.*?\[view endKeepingPinnedLinkPreviewOnPage: YES\];', keep, re.S),
       'going to another place does not put the pinned popup back on its page after the move')
# A popup away from its place forgets it only when a drag really moves or resizes it.
drag = method('Sources/Preview/TSLinkPreviewView.m', '- (void)mouseDragged:')
expect(re.search(r'if \(!NSEqualRects\(frame, self\.frame\) \|\| !NSEqualRects\(source, _source\)\) _awayFromPlace = NO;', drag)
       and drag.count('_awayFromPlace = NO') == 1,
       'a drag that changes nothing forgets the place the pinned popup is away from')
# The page number box cleans up the selection without the pinned popup before it goes there.
body = method(kit, '- (void) goToKitPage: (id)sender')
expect('[self cleanupMarqueeKeepingPinnedLinkPreview]' in body and not re.search(r'cleanupMarquee: ?YES', body),
       'the page number box closes the pinned popup in Single Page and Double Page display')
for signature in ('- (void) firstPage:', '- (void) lastPage:', '- (void) goToKitPageNumber:'):
    expect(not re.search(r'cleanupMarquee: ?YES', method(kit, signature)),
           f'{signature} closes the pinned popup in Single Page and Double Page display')
for signature in ('- (void) goBack:', '- (void) goForward:', '- (void) firstPage:', '- (void) lastPage:',
                  '- (void) goToKitPageNumber:', '- (IBAction) takeDestinationFromOutline:', '- (void) mouseUp:'):
    body = method(kit, signature)
    expect('[self keepPinnedLinkPreviewThroughMove]' in body and 'closePinnedLinkPreview' not in body,
           f'{signature} does not keep the pinned popup on its page')
# Search results: the part that goes to the result keeps its popup on its page.
body = method(kit, '- (void) tableViewSelectionDidChange:')
expect(0 <= body.find('[self keepPinnedLinkPreviewThroughMove]') < body.find('[self goToPage: aPage]')
       and 'closePinnedLinkPreview' not in body, 'a search result in the drawer does not keep the pinned popup')
for signature in ('- (void) doFindOne:', '- (void) doFindOneFullWindow:', '- (void) doFindAgain'):
    body = method(kit, signature)
    keep = body.find('[(MyPDFKitView *)self.myDocument.pdfKitWindow.activeView keepPinnedLinkPreviewThroughMove]')
    go = body.find('[self.myDocument.pdfKitWindow.activeView goToPage: thePage]')
    found = body.find('if (searchSelection != NULL)')
    expect(0 <= found < keep < go and 'closePinnedLinkPreview' not in body,
           f'{signature.split()[-1]} does not keep the pinned popup of the part that shows the result')

# Syncs from the source: every one marks the place it goes to in the part that goes there,
# and marking keeps the pinned popup of that part on its page.
mark = method(kit, '- (void)setIndexForMark:')
expect('[self keepPinnedLinkPreviewThroughMove];' in mark and 'closePinnedLinkPreview' not in mark,
       'marking the place of a sync does not keep the pinned popup')
syncs = 0
for name in ('Sources/Sync/TSDocument-SyncTeX.m', 'Sources/Sync/TSDocument-SyncOld.m',
             'Sources/Sync/TSDocument-SyncConTeXt.m', 'Sources/Document/TSDocument.m'):
    for head, body in methods(source(name)):
        movers = set(re.findall(r'\[(self\.pdfKitWindow\.activeView|self\.myPDFKitView)\s+goToPage', body))
        if not movers:
            continue
        syncs += 1
        marked = set(re.findall(r'\[(?:\(MyPDFKitView \*\))?(self\.pdfKitWindow\.activeView|self\.myPDFKitView)\s+setIndexForMark', body))
        expect(movers <= marked, f'{Path(name).name} {head[:70]} goes to a page of a part that it does not mark')
expect(syncs >= 5, f'only {syncs} syncs from the source were found')

# Split Window with Link: the part that goes to the target keeps its popup on its page; the part
# with the link keeps its own where it is (#31).
body = method('Sources/Windows/TSPreviewWindow.m', '- (void)showLinkDestination:')
expect(0 <= body.find('[otherView keepPinnedLinkPreviewThroughMove]') < body.find('[otherView goToDestination: destination]')
       and 'closePinnedLinkPreview' not in body,
       'Split Window with Link does not keep the pinned popup of the part that goes to the target on its page')
expect('[linkView keepPinnedLinkPreviewThroughMove]' not in body and '[linkView cleanupMarquee' not in body,
       'Split Window with Link moves the pinned popup of the part with the link')

# Zoom, the magnification menu, the display format and turning one page keep the popup.
for signature in ('- (void) changeScale:', '- (void)setMagnification:', '- (void)changePDFViewSizeTo:',
                  '- (void)changePageStyleTo:', '- (void) previousPage:', '- (void) nextPage:'):
    body = method(kit, signature)
    expect(not re.search(r'cleanupMarquee: ?YES', body), f'{signature} closes the pinned popup')
# Turning one page keeps it at its place on its page too: the place is taken before the page turns.
for signature in ('- (void) previousPage:', '- (void) nextPage:'):
    body = method(kit, signature)
    expect(0 <= body.find('[self keepPinnedLinkPreviewThroughMove]') < body.find('[self stepPageForward:'),
           f'{signature} does not keep the pinned popup at its place on its page')
# The magnification leaves it at its place on its page, which grows and shrinks with it; PDFKit
# keeps that place (run-pinned-popup-stays-on-page.py) (#56).
for signature in ('- (void) changeScale:', '- (void)setMagnification:', '- (void)changePDFViewSizeTo:',
                  '- (void)fitContentWidthKeepingTop:', '- (void)changePageStyleTo:'):
    body = method(kit, signature)
    expect('keepPinnedLinkPreviewInView' not in body and 'keepInView' not in body,
           f'{signature} moves the pinned popup off its place on its page')
# A new display format puts the pages elsewhere: the popup remembers its place on its page
# before and goes back to it once the place shown before is back, or else into view (#56).
expect('performPreviewLayoutChange:' in method(kit, '- (void)changePageStyleTo:'),
       'the display format does not change through performPreviewLayoutChange')
body = method(kit, '- (void)performPreviewLayoutChange:')
begin = body.find('BOOL keepsPopup = [self beginKeepingPinnedLinkPreviewOnPage];')
change = body.find('change();')
went = max(body.find('[self goToDestination:destination]'), body.find('[self goToPage:page]'))
end = body.find('[self endKeepingPinnedLinkPreviewOnPage: keepsPopup];')
expect(0 <= begin < change, 'the pinned popup does not remember its place on its page before the display format changes')
expect(change < went < end and body.count('endKeepingPinnedLinkPreviewOnPage') == 1,
       'the pinned popup does not go back to its place on its page after the display format changes')
begin_body = method(kit, '- (BOOL)beginKeepingPinnedLinkPreviewOnPage')
expect('[pinnedLinkPreview rememberPlaceOnPage]' in begin_body,
       'the pinned popup does not remember its place on its page before the display format changes')
# A change made within another one, as setupPageStyle within performPreviewLayoutChange:, leaves
# the popup to the outer one, which goes back only once the place shown before is back.
expect(re.search(r'if \(keepsPinnedLinkPreviewOnPage \|\| !\[self hasPinnedLinkPreview\]\) return NO;', begin_body),
       'a display format set within another change puts the pinned popup back before the place shown before is back')
end_body = method(kit, '- (void)endKeepingPinnedLinkPreviewOnPage:')
expect(re.search(r'!\[pinnedLinkPreview returnToPlaceOnPage\]\)\s*\[pinnedLinkPreview keepInView\]', end_body),
       'a pinned popup whose page is no longer shown does not come back into view')
# PDFKit's contextual menu sets the display format with setDisplayMode: (#56).
body = method(kit, '- (void)setDisplayMode:')
begin = body.find('BOOL keepsPopup = [self beginKeepingPinnedLinkPreviewOnPage];')
display = body.find('[super setDisplayMode: mode];')
end = body.find('[self endKeepingPinnedLinkPreviewOnPage: keepsPopup];')
expect(0 <= begin < display < end, 'a display format from the contextual menu does not keep the pinned popup on its page')
body = method(kit, '- (void)zoomToContentWidthOnly:')
expect('cleanupMarqueeKeepingPinnedLinkPreview' in body and not re.search(r'cleanupMarquee: ?YES', body),
       'Zoom to Content closes the pinned popup')
# Rotation still closes it: its picture and its text follow the page as it was.
for signature in ('- (void) rotateClockwise:', '- (void) rotateCounterclockwise:'):
    expect(re.search(r'cleanupMarquee: ?YES', method(kit, signature)), f'{signature} keeps a pinned popup of the page as it was')

if args.mutation:
    assert problems, args.mutation
    print(f'PASS: detected mutation {args.mutation}: {problems[0]}')
    raise SystemExit(0)
assert not problems, problems
print(f'PASS: links, the drawer, Back and Forward, page numbers, first and last page, search, {syncs} syncs and Split Window with Link keep the pinned popup of the part that moves on its page; zoom and turning pages keep it; '
      'the magnification and the display format leave it on its page')
