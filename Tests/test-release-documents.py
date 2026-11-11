#!/usr/bin/env python3
"""Check release-document Markdown boundaries without invoking TeX."""
import html
import importlib.util
import re
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    'release_documents', Path(__file__).resolve().parents[1] / 'Scripts/build-release-documents.py')
documents = importlib.util.module_from_spec(spec)
spec.loader.exec_module(documents)


ROOT = Path(__file__).resolve().parents[1]


def plain_markdown(text):
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text).replace('`', '').replace('**', '')
    return re.sub(r'\s+', ' ', text).strip()


def plain_html(text):
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', '', text)))


class ReleaseDocuments(unittest.TestCase):
    def test_hand_written_copies_contain_every_item(self):
        # The web pages and the help page are written by hand; each item of the
        # Markdown notes must appear in each copy of the same language.
        copies = {
            'Documentation/Releases/5.60.md': ['website/release-notes.html',
                                               'Resources/Interfaces/en.lproj/TeXShopHelp/pgs/whatisnew.htm'],
            'Documentation/Releases/5.60-ja.md': ['website/release-notes-ja.html'],
        }
        for notes, pages in copies.items():
            items = [plain_markdown(line[2:]) for line in (ROOT / notes).read_text().splitlines() if line.startswith('- ')]
            self.assertTrue(items, notes)
            for page in pages:
                text = plain_html((ROOT / page).read_text())
                missing = [item[:80] for item in items if item not in text]
                self.assertEqual(missing, [], page)

    def test_sentence_punctuation_is_outside_url(self):
        self.assertEqual(documents.inline('See https://texshop.app/.'),
                         r'See \url{https://texshop.app/}.')
        self.assertEqual(documents.inline('(https://example.org/a(b)).'),
                         r'(\url{https://example.org/a(b)}).')

    def test_code_is_literal_and_bold_is_formatted(self):
        self.assertEqual(documents.inline('**Fix:** `a_b * [x]`'),
                         r'\textbf{Fix:} \texttt{a\_b * [x]}')

    def test_unsupported_markdown_is_rejected(self):
        for text in ('[site](texshop.app)', '[site](https://example.org/a%20b)', '*emphasis*', '_emphasis_',
                     '**[site](https://texshop.app/)**', '- item\n  - nested',
                     '### Subheading', '1. ordered', '> quote', '```code```',
                     '| a | b |', '<!-- hidden -->', '**unclosed', 'text  ',
                     'https://example.org/{unsafe}'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                documents.markdown(text)

    def test_links_to_issues_and_pull_requests(self):
        self.assertEqual(
            documents.inline('Fixed ([#8](https://github.com/TeXShopProject/TeXShop/issues/8)).'),
            r'Fixed (\href{https://github.com/TeXShopProject/TeXShop/issues/8}{\#8}).')
        self.assertEqual(
            documents.inline('From ddd3h in [PR #1](https://github.com/TeXShopProject/TeXShop/pull/1).'),
            r'From ddd3h in \href{https://github.com/TeXShopProject/TeXShop/pull/1}{PR \#1}.')

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
