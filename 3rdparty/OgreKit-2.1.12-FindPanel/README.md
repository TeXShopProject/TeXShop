# OgreKit Find panel sources

These are the sources of the Find panel of OgreKit 2.1.12 (`OgreAdvancedFindPanel.nib`
in each localization), from https://github.com/sonoisa/OgreKit, tag `2.1.12`
(commit 6bcba98). Compiled with ibtool, the unedited sources give the same nibs as
the framework bundled in `Frameworks/OgreKit.framework`.

They are edited so that the eight push buttons below the options are small buttons,
20 points high and 8 points apart, lined up with the boxes above them and as wide as
their titles need, instead of frames placed edge to edge for older versions of macOS,
which now draw over each other.

After editing a source, compile it into the framework:

    python3 Scripts/compile-ogrekit-find-panel.py

`Tests/run-ogrekit-find-panel.py` checks the layout in every localization and that the
framework is compiled from these sources.

OgreKit is distributed under the license in `License.txt`.
