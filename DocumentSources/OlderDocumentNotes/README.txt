These wrappers add the note "This document was written in ..." to the first page of older Help
documents whose sources no longer build with a current TeX Live (Recent TeX Fonts and Notes on
Applescript need the non-free garamondx fonts), or whose source of the bundled version is not in
the repository (the French TeXShop Tips & Tricks, v0.8.2). Each wrapper includes the bundled PDF
of the version before the note (the *-original.pdf beside it) with pdfpages and writes the note
in the top margin of its first page. Build with pdflatex and copy the result to the bundled places
named at the top of each wrapper.
