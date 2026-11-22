#!/usr/bin/env python3
"""Put the notes of notes.pdf (letter size) on the first page of the older Help documents, keeping their links,
bookmarks and named destinations, and copy the results to where TeXShop bundles them.
Run from this folder after building notes.tex with pdflatex."""
from pathlib import Path
import shutil
import re
from pypdf import PdfWriter, Transformation
from pypdf.generic import ContentStream, NameObject

here = Path(__file__).resolve().parent
interfaces = here.parents[1] / 'Resources/Interfaces'
DOCUMENTS = [  # (original, bundled copies)
    ('RecentTexFonts-original.pdf', ['Base.lproj/RecentTexFonts.pdf', 'en.lproj/RecentTexFonts.pdf']),
    ('NotesOnApplescript-original.pdf', ['Base.lproj/Notes on Applescript in TeXShop.pdf', 'en.lproj/Notes on Applescript in TeXShop.pdf']),
    ('TipsAndTricks-fr-original.pdf', ['fr.lproj/TeXShop Tips & Tricks.pdf']),
]
def renamed_fonts(page):
    """The note page with its font resources renamed (/F44 -> /TSNote44), so that a font of the same
    name on the document's page does not take their place when the pages are merged."""
    fonts = page['/Resources']['/Font']
    content = page.get_contents().get_data()
    for name in list(fonts.keys()):
        new = NameObject('/TSNote' + name[2:])
        fonts[new] = fonts.pop(name)
        content = re.sub(re.escape(name.encode()) + rb'(?=[\s/\[<(])', new.encode(), content)
    stream = ContentStream(None, None)
    stream.set_data(content)
    page.replace_contents(stream)
    return page


notes = PdfWriter(clone_from=here / 'notes.pdf')
for number, (original, copies) in enumerate(DOCUMENTS):
    writer = PdfWriter(clone_from=here / original)
    # The notes are letter size: keep the note at the same distance from the top, centered.
    page, note = writer.pages[0], renamed_fonts(notes.pages[number])
    dx = (float(page.mediabox.width) - float(note.mediabox.width)) / 2
    dy = float(page.mediabox.top) - float(note.mediabox.top)
    page.merge_transformed_page(note, Transformation().translate(dx, dy))
    result = here / original.replace('-original', '')
    with open(result, 'wb') as f:
        writer.write(f)
    for copy in copies:
        shutil.copyfile(result, interfaces / copy)
    print(result.name, '->', ', '.join(copies))
