#!/usr/bin/env python3
"""Use Color Mapping recolors bitmap copies only. PDF and EPS copies are
written by MyDragView from the page's own PDF data, so they keep the page's
colors and add no background; the Preview note says so in every language."""
from pathlib import Path
import re, subprocess, sys, tempfile, plistlib, json
from production_fragments import method
root = Path(__file__).resolve().parents[1]
mutation = sys.argv[1] if len(sys.argv) > 1 else ''

# The production selection routine: only the bitmap branch maps colors.
pdfkit = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin-1')
routine = method(pdfkit, '- (NSData *)imageDataFromSelectionType:')
if mutation == 'pdf-branch-mapped':
    routine = routine.replace('data = [myDragView dataWithPDFInsideRect: pageDataRect];',
                              'data = [myDragView dataWithPDFInsideRect: pageDataRect]; transformColor(nil, nil, nil, 0);')
live = re.sub(r'/\*.*?\*/', '', routine, flags=re.S)
live = '\n'.join(line.split('//')[0] for line in live.splitlines())
start = live.index('NSPDFImageRep *myRep')
vector = live[start:live.index('data = nil;', start)]
assert 'data = [myDragView dataWithPDFInsideRect: pageDataRect];' in vector and 'data = [myDragView dataWithEPSInsideRect: pageDataRect];' in vector, 'PDF and EPS copies come from MyDragView'
assert not re.search(r'transformColor|PdfColorMapKey|ImageBackgroundColor|ImageForegroundColor', vector), 'PDF and EPS branch does not map colors'
bitmap = live[live.index('if (bitmap && [SUD boolForKey:PdfColorMapKey])'):]
assert 'transformColor(bitmap, foreColor, backColor, colorParam1)' in bitmap[:bitmap.index('convert to the specified format') if 'convert to the specified format' in bitmap else len(bitmap)], 'Bitmap copies map colors'
print('PASS: only bitmap copies pass through the color map')

# MyDragView, compiled from production, keeps black and leaves the unpainted page transparent.
drag = (root / 'Sources/Preview/MyDragView.m').read_text(encoding='latin-1')
if mutation == 'drag-view-fills':
    drag = drag.replace('[self.myRep draw];', '[[NSColor redColor] set]; NSRectFill(aRect); [self.myRep draw];')
program = r'''
#import <Cocoa/Cocoa.h>
#import "MyDragView.h"
#define REQUIRE(c, m) do { if (!(c)) { fprintf(stderr, "FAIL: %s\n", m); return 1; } } while (0)
int main(void) { @autoreleasepool {
    NSMutableData *page = [NSMutableData data];
    CGRect box = CGRectMake(0, 0, 200, 100);
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)page);
    CGContextRef pdf = CGPDFContextCreate(consumer, &box, NULL);
    CGPDFContextBeginPage(pdf, NULL);
    CGContextSetRGBFillColor(pdf, 0, 0, 0, 1); CGContextFillRect(pdf, CGRectMake(20, 20, 60, 60));
    CGPDFContextEndPage(pdf); CGPDFContextClose(pdf); CGContextRelease(pdf); CGDataConsumerRelease(consumer);
    NSPDFImageRep *rep = [NSPDFImageRep imageRepWithData:page];
    MyDragView *view = [[MyDragView alloc] initWithFrame:NSRectFromCGRect(box)];
    [view setImageRep:rep];
    for (int eps = 0; eps < 2; eps++) {
        NSData *copy = eps ? [view dataWithEPSInsideRect:NSRectFromCGRect(box)] : [view dataWithPDFInsideRect:NSRectFromCGRect(box)];
        REQUIRE(copy.length > 0, "copy produced");
        if (eps) { REQUIRE([[[NSString alloc] initWithData:[copy subdataWithRange:NSMakeRange(0, 4)] encoding:NSASCIIStringEncoding] isEqual:@"%!PS"], "EPS copy"); continue; }
        NSPDFImageRep *result = [NSPDFImageRep imageRepWithData:copy];
        NSBitmapImageRep *pixels = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:200 pixelsHigh:100 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:32];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:pixels]];
        [result drawInRect:NSMakeRect(0, 0, 200, 100)];
        [NSGraphicsContext restoreGraphicsState];
        NSColor *ink = [pixels colorAtX:50 y:50], *paper = [pixels colorAtX:150 y:50];
        REQUIRE(ink.alphaComponent > 0.99 && ink.redComponent < 0.01 && ink.greenComponent < 0.01 && ink.blueComponent < 0.01, "PDF copy keeps black");
        REQUIRE(paper.alphaComponent < 0.01, "PDF copy adds no background");
    }
    puts("PASS: PDF and EPS copies keep the page colors and add no background");
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix='texshop-color-map-note-') as tmp:
    tmp = Path(tmp)
    (tmp / 'MyDragView.m').write_text(drag, encoding='latin-1')
    (tmp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(root / 'Sources/Preview'),
                    str(tmp / 'test.m'), str(tmp / 'MyDragView.m'), '-o', str(tmp / 'test')], check=True)
    result = subprocess.run([str(tmp / 'test')], capture_output=True, text=True, timeout=60)
    print(result.stdout, end='')
    assert result.returncode == 0, result.stderr

# The note in every language names the PDF and EPS exception without a background claim.
notes = {}
for strings in sorted((root / 'Resources/Interfaces').glob('*.lproj/SettingsCategories.strings')):
    values = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(strings)]))
    notes[strings.parent.name] = values['catalog.preview.4.1.note']
if mutation == 'note-background':
    notes['ja.lproj'] = notes['ja.lproj'].replace('PDFとEPSには適用されません。', 'PDFとEPSでは背景の色だけが付きます。')
assert len(notes) == 12, notes.keys()
for language, note in notes.items():
    assert 'PDF' in note and 'EPS' in note, ('note names PDF and EPS', language)
assert notes['Base.lproj'].endswith('PDF and EPS copies are not changed.'), 'English note'
assert notes['ja.lproj'].endswith('PDFとEPSには適用されません。'), 'Japanese note'
for language, note in notes.items():
    last = [part for part in re.split(r'[.。]\s*', note) if part.strip()][-1]
    assert 'PDF' in last and 'EPS' in last, ('last sentence is the PDF and EPS exception', language)
    assert not re.search(r'background|背景|Hintergrund|fondo|fond|sfondo|배경|achtergrond|fundo|fundal', last), ('note claims no background for PDF and EPS', language, last)
print('PASS: the Preview note in 12 languages says PDF and EPS copies are not changed')
