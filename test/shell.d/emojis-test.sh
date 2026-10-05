#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const emojis = requireFromRoot('shell/plugins/emojis/EmojiSearch.js')

const raw = fs.readFileSync(path.join(root, 'shell/plugins/emojis/emojis.json'), 'utf8')
const data = emojis.parseEmojis(raw)

assert(data.length > 1000, 'emoji dataset parses')
assertDeepEqual(emojis.parseEmojis('{'), [], 'invalid emoji JSON parses as empty list')
assertDeepEqual(emojis.parseEmojis('{"e":"nope"}'), [], 'non-array emoji JSON parses as empty list')

const fixture = [
  { e: 'a', k: 'grinning face smile happy' },
  { e: 'b', k: 'face with tears of joy joy tears' },
  { e: 'c', k: 'flag: united states us america' }
]

assertDeepEqual(
  emojis.filterEmojis(fixture, '  JOY  ').map(item => item.e),
  ['b'],
  'emoji filtering trims and lowercases query'
)

assertDeepEqual(
  emojis.filterEmojis(fixture, '', 2).map(item => item.e),
  ['a', 'b'],
  'emoji filtering honors result limit'
)

assertDeepEqual(
  emojis.filterEmojis(fixture, '', 0),
  [],
  'emoji filtering supports zero result limit'
)

assertEqual(
  emojis.filterEmojis(data, 'face with tears')[0].e,
  '\u{1F602}',
  'emoji filtering finds face with tears of joy'
)

assertDeepEqual(emojis.parseFavorites('["a","b"]'), ['a', 'b'], 'emoji favorites parse in file order')
assertDeepEqual(emojis.parseFavorites('{'), [], 'invalid emoji favorites parse as empty')
assertDeepEqual(emojis.parseFavorites('{"a":1}'), [], 'non-array emoji favorites parse as empty')
assertDeepEqual(
  emojis.parseFavorites('["a","a"," b ",7,null]'),
  ['a', 'b'],
  'emoji favorites drop duplicates, blanks and non-strings'
)

assertDeepEqual(emojis.toggleFavorite(['a'], 'b'), ['a', 'b'], 'favoriting appends so pinned cells stay put')
assertDeepEqual(emojis.toggleFavorite(['a', 'b'], 'a'), ['b'], 'unfavoriting removes the emoji')
assertDeepEqual(emojis.toggleFavorite(null, 'a'), ['a'], 'favoriting tolerates a missing list')
assertDeepEqual(emojis.toggleFavorite(['a'], ''), ['a'], 'favoriting ignores an empty emoji')

assertDeepEqual(emojis.moveFavorite(['a', 'b', 'c'], 'a', 'c'), ['b', 'c', 'a'], 'dragging a favorite forward drops it on the target cell')
assertDeepEqual(emojis.moveFavorite(['a', 'b', 'c'], 'c', 'a'), ['c', 'a', 'b'], 'dragging a favorite back drops it on the target cell')
assertDeepEqual(emojis.moveFavorite(['a', 'b'], 'a', 'a'), ['a', 'b'], 'dropping a favorite on itself changes nothing')
assertDeepEqual(emojis.moveFavorite(['a', 'b'], 'a', 'typo'), ['a', 'b'], 'dropping a favorite outside the list changes nothing')

assertDeepEqual(
  emojis.favoriteEmojis(fixture, ['c', 'a']),
  ['c', 'a'],
  'favorite emojis keep the file order rather than the catalog order'
)

assertDeepEqual(
  emojis.favoriteEmojis(fixture, ['typo', 'b']),
  ['b'],
  'favorite emojis ignore entries outside the catalog'
)

assertDeepEqual(
  emojis.favoriteEmojis(fixture, ['b']),
  ['b'],
  'a short favorite list is not padded out with emojis nobody chose'
)

// Grid layout: [Favorites heading ×8][pins][pad to row end][All heading ×8][matches]
const cells = emojis.buildCells(fixture, ['c', 'a', 'b'], '', 1000, 8)

assertEqual(cells.length, 27, 'grid layout pads a short pinned row to the row end')
assertEqual(cells[0].heading, 'Favorites', 'pinned section is headed')
assertEqual(cells[1].heading, '', 'only the first cell of a heading row carries the text')
assertDeepEqual(cells.slice(8, 11).map(cell => cell.emoji), ['c', 'a', 'b'], 'pinned cells follow in file order')
assertDeepEqual(cells.slice(11, 16).map(cell => cell.emoji), ['', '', '', '', ''], 'row end after the pins is padding, not emojis')
assertEqual(cells[16].heading, 'All', 'the rest of the picker is headed All')
assertDeepEqual(cells.slice(24, 27).map(cell => cell.emoji), ['a', 'b', 'c'], 'catalog cells follow the headings')
assertEqual(emojis.isEmojiCell(cells, 0), false, 'a heading cell cannot hold the cursor')
assertEqual(emojis.isEmojiCell(cells, 8), true, 'a pinned cell holds the cursor')

const bare = emojis.buildCells(fixture, [], '', 1000, 8)
assertEqual(bare[0].emoji, 'a', 'a picker with nothing pinned has no headings at all')
assertEqual(bare.some(cell => cell.heading !== ''), false, 'no headings without pins')

const searching = emojis.buildCells(fixture, ['c'], 'joy', 1000, 8)
assertEqual(searching[0].emoji, 'b', 'searching drops the pinned row for the matches')
assertEqual(searching.some(cell => cell.heading !== ''), false, 'searching shows no headings')

assertEqual(emojis.stepTarget(cells, 0, 1), 8, 'stepping right off a heading lands on the first pinned emoji')
assertEqual(emojis.stepTarget(cells, 11, 1), 24, 'stepping right past a padded row end crosses into the catalog')
assertEqual(emojis.stepTarget(cells, 16, -1), 10, 'stepping left off the All heading lands on the last pinned emoji')
assertEqual(emojis.stepTarget(cells, 0, -1), -1, 'stepping left off the grid reports -1 so the caller can wrap')

assertEqual(emojis.rowTarget(cells, 8, 8, 1), 24, 'down from a pinned cell lands on the catalog below it')
assertEqual(emojis.rowTarget(cells, 8, 25, -1), 9, 'up from a catalog cell lands on the pin in its own column')
assertEqual(emojis.rowTarget(cells, 8, 8, -1), -1, 'up from the top row stays put')
assertEqual(emojis.rowTarget(cells, 8, 24, 2), -1, 'a page past the end of the grid stays put')

// A full catalog band, so an "up" from a column past the pins has somewhere to land.
const wide = fixture.concat([{ e: 'd', k: 'x' }, { e: 'e', k: 'x' }, { e: 'f', k: 'x' }, { e: 'g', k: 'x' }, { e: 'h', k: 'x' }])
const wideCells = emojis.buildCells(wide, ['c', 'a', 'b'], '', 1000, 8)

assertEqual(wideCells.length, 32, 'a full catalog band follows the headings')
assertEqual(emojis.rowTarget(wideCells, 8, 26, -1), 10, 'up from a catalog column past the pins lands on the nearest pin, not sideways')
assertEqual(emojis.rowTarget(wideCells, 8, 27, -1), 10, 'and the same for the column beyond it')
assertEqual(emojis.rowTarget(wideCells, 8, 24, -1), 8, 'up from catalog column 0 lands on the pin in that column')
assertEqual(emojis.rowTarget(wideCells, 8, 31, -1), 10, 'up from the far edge of the catalog band still lands on a pin')
JS

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/wl-copy" <<'SH'
#!/bin/bash
args="$*"
target="$WL_COPY_OUT"
if [[ $args == "--type text/plain --sensitive --foreground" ]]; then
  target="$WL_COPY_EMOJI_OUT"
fi

printf '%s\n' "$args" >"$target.args"
cat >"$target"
SH

cat >"$TMPDIR/bin/wtype" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$WTYPE_OUT"
SH

cat >"$TMPDIR/bin/sleep" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$TMPDIR/bin/wl-copy" "$TMPDIR/bin/wtype" "$TMPDIR/bin/sleep"

WL_COPY_OUT="$TMPDIR/copy" WL_COPY_EMOJI_OUT="$TMPDIR/emoji" WTYPE_OUT="$TMPDIR/wtype" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀"

[[ $(<"$TMPDIR/emoji") == "😀" ]] || fail "emoji insert helper copies emoji transiently"
pass "emoji insert helper copies emoji transiently"

[[ $(<"$TMPDIR/emoji.args") == "--type text/plain --sensitive --foreground" ]] || fail "emoji insert helper serves sensitive transient clipboard in foreground"
pass "emoji insert helper serves transient clipboard in foreground"

[[ $(<"$TMPDIR/wtype") == "-M shift -k Insert -m shift" ]] || fail "emoji insert helper pastes with shift insert"
pass "emoji insert helper pastes with shift insert"
