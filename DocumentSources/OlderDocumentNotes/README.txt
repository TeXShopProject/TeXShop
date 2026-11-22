The older Help documents Recent TeX Fonts and Notes on Applescript no longer build from their
sources with a current TeX Live (they need the non-free garamondx fonts), and the source of the
bundled French TeXShop Tips & Tricks (v0.8.2) is not in the repository. Their notes "This document
was written in ..." are put on the first page of the bundled PDFs instead:

  notes.tex          one letter-size page per note (build with pdflatex twice)
  make-notes.py      merges page N of notes.pdf onto the first page of document N (moved to keep
                     the note at the top of an A4 page too), keeping the
                     links, bookmarks and named destinations, and copies the results to
                     Resources/Interfaces (Base and en, or fr)
  *-original.pdf     the bundled PDFs before the notes
