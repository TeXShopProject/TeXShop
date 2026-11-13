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


class PrereleaseTest(unittest.TestCase):
    def item(self, channel, short, prerelease):
        item = ET.SubElement(channel, 'item')
        ET.SubElement(item, f'{{{release.SPARKLE}}}shortVersionString').text = short
        if prerelease:
            ET.SubElement(item, f'{{{release.SPARKLE}}}channel').text = 'prerelease'
        return item

    def shorts(self, channel):
        return [i.findtext(f'{{{release.SPARKLE}}}shortVersionString') for i in channel.findall('item')]

    def test_identity_of_a_beta(self):
        self.assertEqual(release.prerelease_identity({'CFBundleShortVersionString': '5.60 beta-11', 'CFBundleVersion': '5.60b11'}),
                         ('v.5.60-beta.11', 'TeXShop-5.60-beta-11.zip'))
        for info in [{'CFBundleShortVersionString': '5.60', 'CFBundleVersion': '5.60'},
                     {'CFBundleShortVersionString': '5.60 beta-11', 'CFBundleVersion': '5.60b10'}]:
            with self.assertRaisesRegex(ValueError, 'Expected a beta'):
                release.prerelease_identity(info)

    def test_a_beta_replaces_the_previous_beta_only(self):
        channel = ET.Element('channel')
        self.item(channel, '5.60 beta-10', True)
        self.item(channel, '5.59', False)
        release.retire_prereleases(channel, '5.60 beta-11', True)
        self.assertEqual(self.shorts(channel), ['5.59'])

    def test_a_release_retires_its_own_betas(self):
        channel = ET.Element('channel')
        self.item(channel, '5.61 beta-1', True)
        self.item(channel, '5.60 beta-11', True)
        self.item(channel, '5.59', False)
        release.retire_prereleases(channel, '5.60', False)
        self.assertEqual(self.shorts(channel), ['5.61 beta-1', '5.59'])

    def test_prerelease_item_carries_the_channel_and_notes(self):
        item = ET.Element('item')
        release.append_prerelease(item, [('en', '## Changes since Beta 10')], 'v.5.60-beta.11')
        parsed = ET.fromstring(ET.tostring(item, encoding='utf-8'))
        self.assertEqual(parsed.findtext(f'{{{release.SPARKLE}}}channel'), 'prerelease')
        self.assertEqual(parsed.findtext('description'), '## Changes since Beta 10')
        self.assertEqual(parsed.findtext(f'{{{release.SPARKLE}}}fullReleaseNotesLink'),
                         'https://github.com/TeXShopProject/TeXShop/releases/tag/v.5.60-beta.11')

    def test_channel_matches_the_application(self):
        source = (ROOT / 'Sources/App/TSSparkleController.m').read_text(encoding='utf-8')
        self.assertIn(f'TSSparklePrereleaseChannel = @"{release.PRERELEASE_CHANNEL}";', source)


if __name__ == '__main__':
    unittest.main()
