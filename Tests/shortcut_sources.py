"""Use the production shortcut units for temporary mutation-test compilations."""
from pathlib import Path

NAMES = (
    "TSShortcutUtilities.m", "TSShortcutModels.m", "TSShortcutStore.m",
    "TSShortcutSearch.m", "TSShortcutAlerts.m", "TSKeyboardShortcuts.m",
    "TSShortcutPaneController.m",
)

def production_source(root: Path) -> str:
    return "\n".join((root / "Sources" / name).read_text() for name in NAMES)
