#!/usr/bin/env python3
"""Check that the ways to go to another place close the pinned link popup of the part that
goes there, and that zoom, the magnification menu, the display format and turning one page
keep it (#35). run-pinned-link-preview.py runs the ways that MyPDFKitView handles itself;
this checks the ways that go through the document, the search and the preview window."""
from pathlib import Path
import argparse
import re

MUTATIONS = {
    'search-keeps-pin': ('Sources/Preview/MyPDFKitView.m', '- (void) doFindAgain',
                         '        [(MyPDFKitView *)self.myDocument.pdfKitWindow.activeView closePinnedLinkPreview];\n', ''),
    'search-list-keeps-pin': ('Sources/Preview/MyPDFKitView.m', '- (void) tableViewSelectionDidChange:',
                              '\t\t[self closePinnedLinkPreview];\n', ''),
    'mark-keeps-pin': ('Sources/Preview/MyPDFKitView.m', '- (void)setIndexForMark:',
                       '\t[self closePinnedLinkPreview];\n', ''),
    'sync-marks-other-part': ('Sources/Sync/TSDocument-SyncConTeXt.m', '- (BOOL)finishForwardContextSync',
                              'self.pdfKitWindow.activeView setIndexForMark', 'self.myPDFKitView setIndexForMark'),
    'link-part-closes': ('Sources/Windows/TSPreviewWindow.m', '- (void)showLinkDestination:',
                         '    [otherView closePinnedLinkPreview];\n', '    [linkView closePinnedLinkPreview];\n'),
    'fit-kills-pin': ('Sources/Preview/MyPDFKitView.m', '- (void)changePDFViewSizeTo:',
                      '        [self cleanupMarqueeKeepingPinnedLinkPreview];\n', '        [self cleanupMarquee: YES];\n'),
    'format-not-kept-in-view': ('Sources/Preview/MyPDFKitView.m', '- (void)changePageStyleTo:',
                                '    [self keepPinnedLinkPreviewInView];\n', ''),
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
# Search results: the part that goes to the result closes its popup before it goes there.
body = method(kit, '- (void) tableViewSelectionDidChange:')
expect(0 <= body.find('[self closePinnedLinkPreview]') < body.find('[self goToPage: aPage]'),
       'a search result in the drawer does not close the pinned popup')
for signature in ('- (void) doFindOne:', '- (void) doFindOneFullWindow:', '- (void) doFindAgain'):
    body = method(kit, signature)
    close = body.find('[(MyPDFKitView *)self.myDocument.pdfKitWindow.activeView closePinnedLinkPreview]')
    go = body.find('[self.myDocument.pdfKitWindow.activeView goToPage: thePage]')
    found = body.find('if (searchSelection != NULL)')
    expect(0 <= found < close < go, f'{signature.split()[-1]} does not close the pinned popup of the part that shows the result')

# Syncs from the source: every one marks the place it goes to in the part that goes there,
# and marking closes the pinned popup of that part.
mark = method(kit, '- (void)setIndexForMark:')
expect('[self closePinnedLinkPreview];' in mark, 'marking the place of a sync does not close the pinned popup')
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
expect(syncs >= 7, f'only {syncs} syncs from the source were found')

# Split Window with Link: the part that goes to the target closes its popup; the part with
# the link keeps its own (#31).
body = method('Sources/Windows/TSPreviewWindow.m', '- (void)showLinkDestination:')
expect(0 <= body.find('[otherView closePinnedLinkPreview]') < body.find('[otherView goToDestination: destination]'),
       'Split Window with Link does not close the pinned popup of the part that goes to the target')
expect('[linkView closePinnedLinkPreview]' not in body and '[linkView cleanupMarquee' not in body,
       'Split Window with Link closes the pinned popup of the part with the link')

# Zoom, the magnification menu, the display format and turning one page keep the popup, and
# bring it back into view.
for signature in ('- (void) changeScale:', '- (void)setMagnification:', '- (void)changePDFViewSizeTo:',
                  '- (void)changePageStyleTo:', '- (void) previousPage:', '- (void) nextPage:'):
    body = method(kit, signature)
    expect(not re.search(r'cleanupMarquee: ?YES', body), f'{signature} closes the pinned popup')
    expect('[self keepPinnedLinkPreviewInView]' in body, f'{signature} does not bring the pinned popup back into view')
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
print(f'PASS: search, {syncs} syncs and Split Window with Link close the pinned popup of the part that moves; zoom and turning pages keep it')
