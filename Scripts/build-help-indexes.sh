#!/bin/bash
# Rebuild the indexes of the TeXShop help books with hiutil.
#
# Each book Resources/Interfaces/<lang>.lproj/TeXShopHelp has two indexes: <name>.helpindex
# (hiutil -I lsm) and <name>.cshelpindex (hiutil -I corespotlight), both with anchors (-a).
# <name> is the name the book already uses (the German book has TexShopHelp), otherwise
# TeXShopHelp. Run it after changing pages of a book, for that book only.
#
#   Scripts/build-help-indexes.sh                 # all books
#   Scripts/build-help-indexes.sh ja ko           # these books
#   Scripts/build-help-indexes.sh --out DIR en    # write DIR/en/<name>.*index, leave the book as it is
#
# hiutil writes a slightly different file each time, so compare an index with the previous one
# by its terms (hiutil -I lsm -T -f <index>), its anchors (-A) and its size, not by its bytes.
#
# Flags per language (-l: locale of the index; -s: stopword list). hiutil has built-in stopword
# lists only for en, es, de, fr, sv, hu and it; -s ja and -s ko are kept as the earlier indexes
# were built, and change nothing. The flags are written out word by word: a variable "-s en"
# passed unsplit (as zsh does) makes hiutil drop the stopword list.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
INTERFACES="$ROOT/Resources/Interfaces"
ALL=(en ja de es ko fr it nl pt pt-PT ro zh_CN)

flags() {
    case "$1" in
        en)    FLAGS=(-l en -s en) ;;
        ja)    FLAGS=(-l ja -s ja) ;;
        de)    FLAGS=(-l de) ;;
        es)    FLAGS=(-l es) ;;
        ko)    FLAGS=(-l ko -s ko) ;;
        fr)    FLAGS=(-l fr -s fr) ;;
        it)    FLAGS=(-l it -s it) ;;
        nl)    FLAGS=(-l nl) ;;
        pt)    FLAGS=(-l pt) ;;
        pt-PT) FLAGS=(-l pt_PT) ;;
        ro)    FLAGS=(-l ro) ;;
        zh_CN) FLAGS=(-l zh_CN) ;;
        *)     echo "build-help-indexes: no hiutil flags for language '$1'" >&2; return 1 ;;
    esac
}

index_name() {
    local found
    found=$(cd "$1" && ls *.helpindex 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then echo "${found%.helpindex}"; else echo TeXShopHelp; fi
}

# Internal: build one index. --one LANG KIND OUTDIR
if [ "${1:-}" = "--one" ]; then
    lang=$2; kind=$3; outdir=$4
    flags "$lang"
    book="$INTERFACES/$lang.lproj/TeXShopHelp"
    name=$(index_name "$book")
    if [ "$kind" = lsm ]; then suffix=helpindex; else suffix=cshelpindex; fi
    work=$(mktemp -d "${TMPDIR:-/tmp}/build-help-indexes-XXXXXX")
    hiutil -I "$kind" -Ca "${FLAGS[@]}" -f "$work/$name.$suffix" "$book"
    mkdir -p "$outdir"
    old=$( [ -f "$outdir/$name.$suffix" ] && stat -f %z "$outdir/$name.$suffix" || echo - )
    mv -f "$work/$name.$suffix" "$outdir/$name.$suffix"
    rmdir "$work"
    printf '%-6s %-12s %8s -> %8s bytes  (%s)\n' "$lang" "$suffix" "$old" "$(stat -f %z "$outdir/$name.$suffix")" "hiutil -I $kind -Ca ${FLAGS[*]}"
    exit 0
fi

out=
langs=()
while [ $# -gt 0 ]; do
    case "$1" in
        --out) out=$2; shift 2 ;;
        -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "build-help-indexes: unknown option $1" >&2; exit 2 ;;
        *) langs+=("$1"); shift ;;
    esac
done
[ ${#langs[@]} -gt 0 ] || langs=("${ALL[@]}")

jobs=()
for lang in "${langs[@]}"; do
    flags "$lang"
    book="$INTERFACES/$lang.lproj/TeXShopHelp"
    if [ ! -f "$book/TeXShop Help.html" ]; then
        echo "build-help-indexes: $book has no TeXShop Help.html" >&2
        exit 1
    fi
    if [ -n "$out" ]; then
        mkdir -p "$out"
        dest="$(cd "$out" && pwd)/$lang"
    else
        dest="$book"
    fi
    jobs+=("$lang" lsm "$dest" "$lang" corespotlight "$dest")
done

# Every index on its own core: the English lsm index alone takes some minutes.
printf '%s\0' "${jobs[@]}" | xargs -0 -n 3 -P "$(sysctl -n hw.ncpu)" "$0" --one
