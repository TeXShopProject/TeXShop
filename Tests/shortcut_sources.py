"""Use the production shortcut units for temporary mutation-test compilations."""
from pathlib import Path
from source_tree import source_file

NAMES = (
    "TSShortcutUtilities.m", "TSShortcutModels.m", "TSShortcutStore.m",
    "TSShortcutSearch.m", "TSShortcutAlerts.m", "TSKeyboardShortcuts.m",
    "TSShortcutPaneController.m",
)

def production_source(root: Path) -> str:
    return "\n".join((source_file(root, name)).read_text() for name in NAMES)

# Production companion units required by the pane included in the shortcut set.
def companion_sources(root: Path) -> list[str]:
    return [str(source_file(root, "TSPrefPaneLayout.m"))]
