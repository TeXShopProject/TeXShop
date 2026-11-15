# Resources read from macOS

TeXShop reads one file of macOS itself at run time. It is not part of the
application and not documented by Apple, so it has to be checked after each major
update of macOS.

## Unicode block names of the Character Viewer

| | |
| --- | --- |
| File | `/System/Library/Input Methods/CharacterPalette.app/Contents/Resources/UnicodeBlocks_Title.loctable` |
| Format | Binary property list: `{language: {block name: translated name}}` |
| Used by | Character Info (Edit menu): the block of a character, in the language of the interface |
| Code | `Sources/Panels/TSUnicodeBlockNames.m` (`TSLocalizedUnicodeBlockName`) |

The file is read once, when Character Info first shows a block. TeXShop takes the
names of its interface language (`pt` is `pt_BR`, `pt-PT` is `pt_PT`). The block of
a character comes from ICU (`libicucore`); its name is matched to the names of the
table by letters and digits, ignoring case, spaces and punctuation, with the
abbreviations of the table spelled out (`Ext.`, `Supp.`, `Desc.`, `Math`).

If the file is missing or cannot be read, or has no names for the language or for
a block, Character Info shows the English name of the block from Blocks.txt of
the Unicode Character Database. Nothing else depends on the file.

## After each major update of macOS

For every new major version of macOS, including its betas, run

```sh
python3 Scripts/check-unicode-block-titles.py
```

on that version. It checks that the file is there and can be read, that it has
the twelve languages of TeXShop, and that every name in it matches a block of ICU,
and it lists the blocks of ICU that the file does not name. It exits with a status
other than 0 when the file, a language or a match is missing. A copy of the file
from another Mac can be given as an argument. Add the result to the table below.

| macOS | Names in the file | Blocks of ICU without a name | Checked |
| --- | --- | --- | --- |
| 14.6.1 | 307 | 39 | 2026-11-15 |
| 15.6.1 | 334 | 12 | 2026-11-15 |
| 26.6.2 | 334 | 12 | 2026-11-15 |
| 27.2.1 | 335 | 11 | 2026-11-15 |

The blocks of ICU are those of the Mac the script runs on (Unicode 17.0 on 27.2.1);
the counts above were made against it.

## When the check fails

- The file moved or changed its format: find the new place or format (the
  Character Viewer is `CharacterPalette.app` in `/System/Library/Input Methods`),
  and change `TSCharacterViewerBlockTable` or `TSUnicodeBlockTranslations` in
  `Sources/Panels/TSUnicodeBlockNames.m`. Until then Character Info shows English
  names; it does not fail.
- A language is missing: Character Info shows English names in that language.
  Look for the language under another code and add it to `TableLanguage`.
- A name of the file matches no block of ICU: Apple spelled a block another way,
  for example with a new abbreviation. Add the abbreviation to `TSUnicodeBlockKey`
  and to `key()` in the script and in `Tests/run-glyph-popover.py`.
- A block of ICU has no name in the file: usually a block newer than the file. It is
  shown in English, which needs no change. If Unicode added blocks that TeXShop
  does not know by name, update the English names from Blocks.txt with
  `python3 Scripts/update-unicode-block-names.py Blocks.txt`.

`python3 Tests/run-glyph-popover.py --tables COPY...` checks Character Info with the
file of this Mac and with copies from other versions.
