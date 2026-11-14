"""The sources of the Matrix and LaTeX panels' controllers, and what the offscreen checks of the localized nibs
need to load these panels as the application does (run-interface-label-fit.py, run-button-spacing.py)."""
import os, shutil
from pathlib import Path
from source_tree import source_file

DEFINE = '-DTS_PANEL_CONTROLLERS=1'


def panel_controller_sources(root):
    return [str(source_file(root, name)) for name in ('TSMatrixPanelController.m', 'TSMatrixTableView.m', 'TSLaTeXPanelController.m', 'globals.m')]


def panel_environment(root, home):
    """An isolated home with the LaTeX and Matrix panels' files as TeXShop installs them on first launch
    (~/Library/TeXShop/LatexPanel, MatrixPanel), the folder of the pictures the panels name, and the
    application's factory defaults."""
    root, home = Path(root), Path(home)
    for folder in ('LatexPanel', 'MatrixPanel'):
        target = home / 'Library/TeXShop' / folder
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(root / 'Resources/TeXShop' / folder, target, dirs_exist_ok=True)
    (home / 'Library/Preferences').mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env['CFFIXED_USER_HOME'] = str(home)
    env['TS_IMAGE_ASSETS'] = str(root / 'Resources/Images.xcassets')
    env['TS_FACTORY_DEFAULTS'] = str(root / 'Resources/Defaults/FactoryDefaults.plist')
    return env
