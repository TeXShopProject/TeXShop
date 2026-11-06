#!/usr/bin/env python3
"""Check release-document Markdown boundaries without invoking TeX."""
import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    'release_documents', Path(__file__).resolve().parents[1] / 'Scripts/build-release-documents.py')
documents = importlib.util.module_from_spec(spec)
spec.loader.exec_module(documents)


class ReleaseDocuments(unittest.TestCase):
    def test_sentence_punctuation_is_outside_url(self):
        self.assertEqual(documents.inline('See https://texshop.app/.'),
                         r'See \url{https://texshop.app/}.')
        self.assertEqual(documents.inline('(https://example.org/a(b)).'),
                         r'(\url{https://example.org/a(b)}).')

    def test_code_is_literal_and_bold_is_formatted(self):
        self.assertEqual(documents.inline('**Fix:** `a_b * [x]`'),
                         r'\textbf{Fix:} \texttt{a\_b * [x]}')

    def test_unsupported_markdown_is_rejected(self):
        for text in ('[site](https://texshop.app/)', '*emphasis*', '_emphasis_',
                     '**[site](https://texshop.app/)**', '- item\n  - nested',
                     '### Subheading', '1. ordered', '> quote', '```code```',
                     '| a | b |', '<!-- hidden -->', '**unclosed', 'text  ',
                     'https://example.org/{unsafe}'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                documents.markdown(text)

    def test_lists_close_before_following_paragraph(self):
        result = documents.markdown('# TeXShop 5.60\n\n- One\n- Two\n\nNext paragraph.')
        self.assertEqual(result.count(r'\begin{itemize}'), 1)
        self.assertEqual(result.count(r'\end{itemize}'), 1)
        self.assertLess(result.index(r'\end{itemize}'), result.index('Next paragraph.'))

    def test_draft_status_and_unicode(self):
        result = documents.markdown('<!-- release-status: draft -->\nSettings → Source’s options.')
        self.assertIn('Release preparation; not yet published.', result)
        self.assertIn(r'Settings \(\rightarrow\) Source’s options.', result)


if __name__ == '__main__':
    unittest.main()
