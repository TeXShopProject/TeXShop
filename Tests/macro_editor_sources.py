"""The macro editor's own layout code, copied from its source, and the production units it needs, for the
offscreen checks of its window (run-macro-shortcut-layout.py, run-interface-label-fit.py)."""
from pathlib import Path
from shortcut_sources import production_source, companion_sources
from source_tree import source_file

FRAMEWORKS = ['-framework', 'Cocoa', '-framework', 'Carbon']


def layout_body(root):
    editor = (Path(root) / 'Sources/Macros/TSMacroEditor.m').read_text()
    return editor[editor.index('- (void)installShortcutStatus'):editor.index('- (void)collectShortcutCandidates:')]


def write_sources(root, directory, inc_name):
    """Writes the layout code as inc_name and returns the sources to compile with it."""
    root, directory = Path(root), Path(directory)
    (directory / inc_name).write_text(layout_body(root))
    menu = (root / 'Sources/Macros/TSMacroMenuController.m').read_text()
    (directory / 'MacroKeyFunctions.m').write_text('#import "TSMacroMenuController.h"\n#import "TSKeyboardShortcuts.h"\n'
                                                   + menu[menu.index('NSString *getKeyEquivalentFromString('):])
    (directory / 'ShortcutProduction.m').write_text(production_source(root))
    return [str(directory / 'MacroKeyFunctions.m'), str(directory / 'ShortcutProduction.m'), *companion_sources(root),
            *(str(source_file(root, name)) for name in ('TSDialogButtonLayout.m', 'TSMarkMenu.m', 'TSListBottomBar.m',
                                                        'TSMacroShortcutField.m', 'TSMacroTreeNode.m'))]
