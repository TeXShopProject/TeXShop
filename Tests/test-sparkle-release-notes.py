#!/usr/bin/env python3
"""Validate release-note packaging without signing, networking, or a real app."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release', ROOT / 'Scripts/prepare-sparkle-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseNotesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        for suffix in ['', '-ja']:
            (self.path / f'5.60{suffix}.md').write_text(
                '# TeXShop 5.60\n\n- TeX & PDF <preview> 日本語\n', encoding='utf-8')

    def test_xml_round_trip_preserves_both_languages_and_old_item(self):
        channel = ET.Element('channel')
        old = ET.SubElement(channel, 'item')
        ET.SubElement(old, 'title').text = 'TeXShop 5.59'
        previous = ET.tostring(old)
        item = ET.Element('item')
        notes = release.load_release_notes('5.60', self.path)
        release.append_release_notes(item, '5.60', notes)
        channel.insert(0, item)
        parsed = ET.fromstring(ET.tostring(channel, encoding='utf-8'))
        descriptions = parsed[0].findall('description')
        self.assertEqual([d.get('{http://www.w3.org/XML/1998/namespace}lang') for d in descriptions], ['en', 'ja'])
        self.assertEqual([d.text for d in descriptions], [text for _, text in notes])
        self.assertTrue(all(d.get(f'{{{release.SPARKLE}}}format') == 'markdown' for d in descriptions))
        self.assertEqual(ET.tostring(parsed[1]), previous)
        self.assertEqual(parsed[0].findtext(f'{{{release.SPARKLE}}}fullReleaseNotesLink'),
                         'https://texshop.app/release-notes.html#v5.60')

    def test_draft_is_rejected(self):
        with (self.path / '5.60-ja.md').open('a') as stream:
            stream.write('\n<!-- release-status: draft -->\n')
        with self.assertRaisesRegex(ValueError, 'Finalize the draft'):
            release.load_release_notes('5.60', self.path)

    def test_missing_translation_is_rejected(self):
        (self.path / '5.60-ja.md').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing ja'):
            release.load_release_notes('5.60', self.path)

    def test_wrong_version_is_rejected(self):
        (self.path / '5.60.md').write_text('# TeXShop 5.59\n\n- Old notes\n')
        with self.assertRaisesRegex(ValueError, 'wrong version'):
            release.load_release_notes('5.60', self.path)


if __name__ == '__main__':
    unittest.main()
