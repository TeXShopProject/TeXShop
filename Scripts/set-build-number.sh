#!/bin/sh
# The "Set Build Number" build phase. It sets CFBundleVersion of the built application
# to the number of commits in HEAD (git rev-list --count HEAD), so the same source always gets
# the same build number and every later commit a larger one. Resources/Info.plist is not changed.
# Outside a git checkout of this project (a source archive, no git, a shallow clone), the
# value of Resources/Info.plist is kept and the build goes on.
# Xcode signs the application after this phase.

plist="${TARGET_BUILD_DIR:?}/${INFOPLIST_PATH:?}"
source_root="${SRCROOT:?}"

keep() {
    echo "warning: Set Build Number: $1; CFBundleVersion stays as in Resources/Info.plist"
    exit 0
}

[ -f "$plist" ] || { echo "error: Set Build Number: no built Info.plist at $plist"; exit 1; }
command -v git >/dev/null 2>&1 || keep "git is not available"
top=$(git -C "$source_root" rev-parse --show-toplevel 2>/dev/null) || keep "the source is not a git checkout"
# A source archive unpacked inside some other repository must not take that repository's count.
[ "$(cd "$top" && pwd -P)" = "$(cd "$source_root" && pwd -P)" ] || keep "the source is not the top of its git checkout"
[ "$(git -C "$source_root" rev-parse --is-shallow-repository 2>/dev/null)" = false ] || keep "the git checkout is shallow"
count=$(git -C "$source_root" rev-list --count HEAD 2>/dev/null) || keep "the commits cannot be counted"
case "$count" in
    ''|*[!0-9]*) keep "the commit count is not a number" ;;
esac

current=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null)
if [ "$current" != "$count" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $count" "$plist" || exit 1
fi
echo "Set Build Number: CFBundleVersion $count"
