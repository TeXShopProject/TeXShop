#!/usr/bin/env python3
"""The sheet that applies an engine profile in Settings and the window of the second step of first launch, with the
list of what a profile sets (TSEngineProfileSheet and TSEngineProfileList in TSPreferences.m, EngineProfileList.m).

For every profile, both forms and every language, the list must name the settings with their short names, each on one
line, in Settings order, with the value the profile writes: the method by its name in Settings, commands in a
monospaced font, switches On or Off, and for the Japanese profiles the encoding, the UTF-8-MAC conversion and the
dictionary. In the sheet each value that differs from the settings in use has a small checkbox before its name, on at
first, and a dot before the value; the other rows are dimmed. A value turned off is gray and struck through, its dot
faint, and is left out of what OK writes; it stays off when latexmk is chosen the other way. With every value that
changes turned off, OK cannot be chosen, by Return either. On first launch nothing is marked. The latexmk choice, and
the profile menu on first launch, replace the list at once, and the window follows its height. OK is the default
button at the bottom right, Cancel beside it on Escape; names, dots and values line up, and no text is cut.

The expected values are those of the table in run-engine-profiles.py, read from its source. Each rule is then broken
in turn in the production source, and the probe must notice."""
from pathlib import Path
import ast, json, plistlib, subprocess, sys, tempfile
from source_tree import include_args, source_file

R = Path(__file__).resolve().parents[1]
INTERFACES = R / 'Resources/Interfaces'
FACTORY = plistlib.loads((R / 'Resources/Defaults/FactoryDefaults.plist').read_bytes())
PREFERENCES = source_file(R, 'TSPreferences.m')

# The table of the profiles, as run-engine-profiles.py writes it out independently of the source.
_table_source = {}
for node in ast.parse((R / 'Tests/run-engine-profiles.py').read_text()).body:
    if isinstance(node, ast.Assign) and node.targets[0].id in ('PDF', 'SIMP', 'PT', 'DVIPDF', 'TABLE', 'JAPANESE'):
        exec(compile(ast.Module([node], []), 'run-engine-profiles.py', 'exec'), _table_source)
TABLE, JAPANESE = _table_source['TABLE'], _table_source['JAPANESE']
MENU = [1, 2, 3, 4, 5, 6, 7, 8]
FIRST_LAUNCH = [1, 2, 3, 4, 5, 6, 7]
ROW_NAMES = ['Typesetting Method', 'plain TeX', 'LaTeX', 'BibTeX Engine', 'Index Program', 'MetaPost', 'Convert to \\UTF / \\CID',
             'New Document Encoding', 'UTF-8-MAC Conversion', 'Dictionary']
NAME_LIMIT = 200

LANGUAGES = sorted(p.stem for p in INTERFACES.glob('*.lproj') if p.stem != 'en' and ((p / 'Localizable.strings').exists() or p.stem == 'Base'))
STEP_LANGUAGES = ['Base', 'ja', 'de']


def strings(language, table):
    folder = 'en' if language == 'Base' and table != 'SettingsCategories' else language
    path = INTERFACES / f'{folder}.lproj/{table}.strings'
    if not path.exists():
        path = INTERFACES / f'Base.lproj/{table}.strings'
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


STRINGS = {}
def table(language, name):
    if (language, name) not in STRINGS:
        STRINGS[language, name] = strings(language, name)
    return STRINGS[language, name]


def profile_values(profile, latexmk):
    place, latex, tex, mk, bib, index, metapost = TABLE[profile]
    direct = place == 100
    values = {'DefaultScript': place, 'LatexCommand' if direct else 'LatexGSCommand': mk if latexmk else latex,
              'TexCommand' if direct else 'TexGSCommand': tex, 'BibTeXengine': bib, 'MakeIndexEngine': index,
              'MetaPostEngine': metapost, 'ptexUtfOutput': profile == 6}
    if profile in JAPANESE:
        values.update({'Encoding': 'UTF-8 Unicode', 'AutomaticUTF8MACtoUTF8Conversion': True, 'SpellingAutomaticDefault': True, 'SpellingLanguageDefault': ' '})
    return values


# The settings in use the sheet compares with: the factory settings; upLaTeX + dvipdfmx without latexmk, applied;
# and settings changed by hand, stored as strings where the defaults may hold them so, with blanks around commands.
SCENARIOS = {
    'factory': {},
    'upLaTeX applied': profile_values(7, False),
    'by hand': {'DefaultScript': '101', 'BibTeXengine': ' biber ', 'ptexUtfOutput': 'YES', 'SpellingAutomaticDefault': False,
                'Encoding': 'ShiftJIS', 'AutomaticUTF8MACtoUTF8Conversion': 'NO', 'MakeIndexEngine': 'makeindex ',
                'LatexGSCommand': '  ' + TABLE[4][1] + ' ', 'TexCommand': 'pdftex'},
}
SCENARIO_LANGUAGES = {'factory': LANGUAGES, 'upLaTeX applied': ['Base', 'ja'], 'by hand': ['Base', 'ja', 'de']}


def truthy(value):
    return value is True or (isinstance(value, (int, float)) and not isinstance(value, bool) and value != 0) or \
        (isinstance(value, str) and value.strip()[:1].upper() in ('Y', 'T', '1', '2', '3', '4', '5', '6', '7', '8', '9'))


def differs(current, key, value):
    stored = current.get(key, FACTORY.get(key))
    if isinstance(value, bool):
        return truthy(stored) != value
    if isinstance(value, int):
        try:
            return int(str(stored).strip()) != value
        except (TypeError, ValueError):
            return True
    return not isinstance(stored, str) or stored.strip() != value.strip()


def expected_rows(language, profile, latexmk, current):
    """(name, value, monospaced, marked, keys) for each row; marked is None where nothing is compared."""
    names, words, encodings, settings = (table(language, 'Localizable'), table(language, 'Localizable'),
                                         table(language, 'Encodings'), table(language, 'SettingsCategories'))
    name = lambda i: names['Engine profile row: ' + ROW_NAMES[i]]
    v = profile_values(profile, latexmk)
    direct = v['DefaultScript'] == 100
    tex, latex = ('TexCommand', 'LatexCommand') if direct else ('TexGSCommand', 'LatexGSCommand')
    mark = (lambda key: differs(current, key, v[key])) if current is not None else (lambda key: None)
    rows = [(name(0), settings['group.typesetting.4.title' if direct else 'group.typesetting.5.title'], False, mark('DefaultScript'), ['DefaultScript']),
            (name(1), v[tex], True, mark(tex), [tex]),
            (name(2), v[latex], True, mark(latex), [latex]),
            (name(3), v['BibTeXengine'], True, mark('BibTeXengine'), ['BibTeXengine']),
            (name(4), v['MakeIndexEngine'], True, mark('MakeIndexEngine'), ['MakeIndexEngine']),
            (name(5), v['MetaPostEngine'], True, mark('MetaPostEngine'), ['MetaPostEngine']),
            (name(6), words['On' if v['ptexUtfOutput'] else 'Off'], False, mark('ptexUtfOutput'), ['ptexUtfOutput'])]
    if profile in JAPANESE:
        automatic = None if current is None else not truthy(current.get('SpellingAutomaticDefault', FACTORY.get('SpellingAutomaticDefault')))
        rows += [(name(7), encodings['UTF-8 Unicode'], False, mark('Encoding'), ['Encoding']),
                 (name(8), words['On'], False, mark('AutomaticUTF8MACtoUTF8Conversion'), ['AutomaticUTF8MACtoUTF8Conversion']),
                 (name(9), words['Automatic Language'], False, automatic, ['SpellingAutomaticDefault', 'SpellingLanguageDefault'])]
    return rows


def compile_probe(tmp, preferences_source):
    text = preferences_source
    (tmp / 'ProductionList.inc').write_text(text[text.index('// BEGIN engine profile list'):text.index('// END engine profile list')])
    binary = tmp / 'EngineProfileList'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(tmp), '-I', str(R / 'Tests'), *include_args(R),
                    str(R / 'Tests/EngineProfileList.m'), str(source_file(R, 'TSPreferenceProfile.m')), str(source_file(R, 'globals.m')),
                    '-o', str(binary)], check=True, capture_output=True)
    return binary


def run_probe(binary, tmp, languages, step_languages=STEP_LANGUAGES):
    settings = tmp / 'settings.json'
    settings.write_text(json.dumps({'factory': FACTORY, 'scenarios': SCENARIOS, 'scenarioLanguages': SCENARIO_LANGUAGES,
                                    'stepLanguages': step_languages, 'choiceOrder': [5, 1, 7, 2, 6, 3, 4]}, default=str))
    out = subprocess.run([str(binary), str(INTERFACES), str(settings), *languages], capture_output=True, text=True, timeout=3600)
    if out.returncode:
        return None, out.stderr[-2000:]
    return [json.loads(line) for line in out.stdout.splitlines() if line.strip()], ''


def top(frame):
    return frame[1] + frame[3]


def check_state(problems, where, language, state, profile, latexmk, current, kept=frozenset()):
    want = expected_rows(language, profile, latexmk, current)
    marks = current is not None
    rows = state['rows']
    if len(rows) != len(want):
        problems.append(f'{where}: {len(rows)} rows, expected {len(want)}')
        return
    columns = {'value': set(), 'name': set(), 'dot': set(), 'check': set()}
    names_end = 0
    for i, (cells, (name, value, mono, marked, keys)) in enumerate(zip(rows, want)):
        if len(cells) != (4 if marks else 2):
            problems.append(f'{where} row {i + 1}: {len(cells)} columns, expected {4 if marks else 2}')
            continue
        check, name_field, dot, value_field = cells if marks else (None, cells[0], None, cells[1])
        is_set = not (set(keys) & kept)
        if name_field.get('text') != name or value_field.get('text') != value:
            problems.append(f'{where} row {i + 1}: "{name_field.get("text")}: {value_field.get("text")}", expected "{name}: {value}"')
            continue
        if value_field['mono'] != mono or name_field['mono']:
            problems.append(f'{where} row {i + 1}: {"a command is not" if mono else "a name or a choice is"} monospaced')
        if name_field['wraps'] or name_field['frame'][3] > 18 or name_field['frame'][2] > NAME_LIMIT + 0.5:
            problems.append(f'{where} row {i + 1}: the name "{name}" does not stand on one line within {NAME_LIMIT} points: {name_field["frame"]}')
        color = 'label' if not marks or (marked and is_set) else 'secondary'
        if name_field['color'] != color or value_field['drawnColor'] != color:
            problems.append(f'{where} row {i + 1} ({name}): colors {name_field["color"]}/{value_field["drawnColor"]}, expected {color}')
        if value_field['struck'] != bool(marks and marked and not is_set):
            problems.append(f'{where} row {i + 1} ({name}): {"struck through" if value_field["struck"] else "not struck through"}')
        for field in (name_field, value_field):
            if field['cut'] or field['hidden']:
                problems.append(f'{where} row {i + 1}: "{field["text"]}" is cut or hidden')
        if marks:
            if (check['kind'] == 'check') != bool(marked):
                problems.append(f'{where} row {i + 1} ({name}): {"a checkbox" if check["kind"] == "check" else "no checkbox"}, the value {"changes" if marked else "stays"}')
            elif marked:
                if check['check'] != is_set or not check['small'] or check['frame'][3] > 14.5 or check['title'] or check['name'] != name or not check['targetIsList']:
                    problems.append(f'{where} row {i + 1} ({name}): checkbox {check}, expected small, untitled, named, {"on" if is_set else "off"}')
                # The checkbox stands at the middle of the name.
                middle = name_field['frame'][1] + name_field['frame'][3] / 2
                if abs(check['frame'][1] + check['frame'][3] / 2 - middle) > 2:
                    problems.append(f'{where} row {i + 1}: the checkbox is not at the middle of the name')
                columns['check'].add(round(check['frame'][0], 1))
            if dot.get('text') != ('\u25CF' if marked else ''):
                problems.append(f'{where} row {i + 1} ({name}): dot "{dot.get("text")}", expected {"a dot" if marked else "none"}')
            elif marked:
                if dot['drawnColor'] != 'accent' or (dot['alpha'] < 0.99) != (not is_set):
                    problems.append(f'{where} row {i + 1} ({name}): dot {dot["drawnColor"]} at {dot["alpha"]:.2f}, expected {"faint" if not is_set else "full"}')
            columns['dot'].add(round(dot['frame'][0], 1))
            if dot['frame'][0] + dot['frame'][2] > value_field['frame'][0] + 0.5:
                problems.append(f'{where} row {i + 1}: the dot is not before the value')
        names_end = max(names_end, name_field['frame'][0] + name_field['frame'][2])
        columns['value'].add(round(value_field['frame'][0], 1)); columns['name'].add(round(name_field['frame'][0], 1))
    for role, xs in columns.items():
        if len(xs) > 1:
            problems.append(f'{where}: the {role}s do not line up: {sorted(xs)}')
    if marks and columns['dot'] and min(columns['dot']) < names_end + 8:
        problems.append(f'{where}: the dots stand in the names (at {sorted(columns["dot"])}, names to {names_end:.1f})')
    if not marks and columns['value'] and min(columns['value']) < names_end + 8:
        problems.append(f'{where}: the names run into the values')
    # The window: question, latexmk choice, heading, the box of the list, and OK at the bottom right, as tall as its views.
    missing = [k for k in ('questionFrame', 'headingFrame', 'latexmk', 'latexmkLabel', 'box', 'list', 'grid', 'ok', 'cancel') if not state[k]]
    if missing:
        problems.append(f'{where}: {missing} not in the window')
        return False
    content, box, lst, grid, ok, cancel = state['content'], state['box'], state['list'], state['grid'], state['ok'], state['cancel']
    width = content[0]
    if box != lst or abs(grid[0] - lst[0] - 12) > 0.5 or abs(top(lst) - top(grid) - 12) > 0.5 or abs(grid[1] - lst[1] - 12) > 0.5:
        problems.append(f'{where}: the list {lst} does not fill its box {box} with its rows {grid} inside')
    if abs(ok[0] + ok[2] - (width - 20)) > 0.5 or abs(ok[1] - 20) > 0.5 or abs(cancel[0] + cancel[2] + 12 - ok[0]) > 0.5 or abs(cancel[1] - ok[1]) > 0.5:
        problems.append(f'{where}: OK {ok} and Cancel {cancel} are not at the bottom right of {content}')
    if abs(box[1] - top(ok) - 20) > 0.5:
        problems.append(f'{where}: the window does not follow the list: box {box}, OK {ok}')
    if not (top(state['questionFrame']) <= content[1] - 19.5 and state['latexmk'][1] > top(state['headingFrame']) and state['headingFrame'][1] > top(box)
            and state['questionFrame'][1] > top(state['latexmk']) and state['latexmkLabel'][0] + state['latexmkLabel'][2] <= state['latexmk'][0]):
        problems.append(f'{where}: the question, latexmk choice, heading and list are not in order from the top')
    if width > 540:
        problems.append(f'{where}: the window is {width:.0f} points wide')
    words = table(language, 'Localizable')
    if (state['okTitle'], state['cancelTitle'], state['okKey'], state['cancelKey'], state['default']) != (words['OK'], words['Cancel'], '\r', '\x1b', True):
        problems.append(f'{where}: OK and Cancel are not the default button on Return and Cancel on Escape')
    if (state['heading'], state['latexmkLabelText'], state['latexmkLabels']) != (words['Values to Set'], words['Run LaTeX:'], [words['Without latexmk'], words['With latexmk']]):
        problems.append(f'{where}: heading {state["heading"]!r}, latexmk {state["latexmkLabelText"]!r} {state["latexmkLabels"]}')
    if state['latexmkSegment'] != (1 if latexmk else 0) or state['latexmkTarget'] != state['listIdentity']:
        problems.append(f'{where}: the latexmk choice shows {state["latexmkSegment"]} or is not the list\'s')
    applies = {k: v for k, v in profile_values(profile, latexmk).items() if k not in kept}
    if state['toApply'] != applies:
        problems.append(f'{where}: OK writes {sorted(state["toApply"])}, expected {sorted(applies)}')
    changing = [set(keys) for (_, _, _, marked, keys) in want if marked]
    if state['keeps'] != any(keys & kept for keys in changing):
        problems.append(f'{where}: the sheet {"keeps" if state["keeps"] else "does not keep"} a value that changes, with {sorted(kept)} turned off')
    enabled = not changing or any(not (keys & kept) for keys in changing)
    if state['okEnabled'] != enabled:
        problems.append(f'{where}: OK is {"enabled" if state["okEnabled"] else "disabled"} with {sorted(kept)} turned off')
    return enabled


def check(results):
    problems = []
    for result in results:
        language = result['language']
        seen = set()
        for sheet in result['sheets']:
            profile, latexmk, scenario = sheet['profile'], sheet['latexmk'], sheet['scenario']
            seen.add((scenario, profile, latexmk))
            current = SCENARIOS[scenario]
            states = sheet['states']
            name = f'{language} sheet {profile}{" latexmk" if latexmk else ""} [{scenario}]'
            for turn, state in enumerate(states):
                check_state(problems, f'{name} after {turn} choices', language, state, profile, latexmk != (turn == 1), current)
            if any(s['listIdentity'] != states[0]['listIdentity'] for s in states):
                problems.append(f'{name}: the list was replaced')
            title = TITLES.get(profile) or table(language, 'Localizable')['LuaLaTeX (Japanese)']
            if states[0]['question'] != table(language, 'Localizable')['Apply the “%@” profile?'].replace('%@', title):
                problems.append(f'{name}: the question is {states[0]["question"]!r}')
            if sheet['keys'] != {'return': True, 'escape': True}:
                problems.append(f'{name}: Return and Escape choose {sheet["keys"]}')
            heights = {round(s['content'][1], 1) for s in states}
            grids = {round(s['grid'][3], 1) for s in states}
            if len(heights) != len(grids):
                problems.append(f'{name}: the window does not follow the height of the list ({heights}, {grids})')
            kept, on = set(), latexmk
            for number, step in enumerate(sheet['steps']):
                state = step['state']
                if not step['clicked'] and number in (1, 2):
                    on = not on
                rows = expected_rows(language, profile, on, current)
                for r in step['clicked']:
                    keys = set(rows[r][4])
                    kept = (kept - keys) if keys & kept else (kept | keys)
                enabled = check_state(problems, f'{name} step {number + 1}', language, state, profile, on, current, frozenset(kept))
                if step['keys'] != {'return': bool(enabled), 'escape': True}:
                    problems.append(f'{name} step {number + 1}: Return and Escape choose {step["keys"]}, OK {"enabled" if enabled else "disabled"}')
            if language in STEP_LANGUAGES and not sheet['steps']:
                problems.append(f'{name}: no steps')
        want = {(s, p, mk) for s in SCENARIOS if language in SCENARIO_LANGUAGES[s] for p in MENU for mk in (False, True)}
        if seen != want:
            problems.append(f'{language}: sheets {sorted(want - seen)} missing')
        if result['answers'] != {'ok': 1, 'cancel': 0, 'count': 2}:
            problems.append(f'{language}: OK and Cancel end the sheet with {result["answers"]}')
        if result['menu'] != FIRST_LAUNCH:
            problems.append(f'{language}: first launch offers {result["menu"]}')
        choices = result['choices']
        check_state(problems, f'{language} first launch as it opens', language, choices[0]['states'][0], 7, False, None)
        if choices[0]['keys'] != {'return': True, 'escape': True}:
            problems.append(f'{language} first launch: Return and Escape choose {choices[0]["keys"]}')
        if choices[0]['states'][0]['question'] != table(language, 'Localizable')['Choose an Engine Profile']:
            problems.append(f'{language} first launch: the question is {choices[0]["states"][0]["question"]!r}')
        heights = {}
        for choice in choices[1:]:
            profile = choice['profile']
            if choice['selected'] != profile:
                problems.append(f'{language} first launch {profile}: the menu shows {choice["selected"]}')
            for turn, state in enumerate(choice['states']):
                where = f'{language} first launch {profile}{" latexmk" if turn == 1 else ""}'
                check_state(problems, where, language, state, profile, turn == 1, None)
                if not (state['popup'] and state['popup'][1] > top(state['latexmk']) and top(state['popup']) < state['questionFrame'][1]):
                    problems.append(f'{where}: the profile menu is not between the question and latexmk')
            heights[profile] = choice['states'][0]['content'][1]
        # Each profile takes the height of its own list: the Japanese profiles have three rows more.
        if not min(heights[p] for p in (5, 6, 7)) > max(heights[p] for p in (1, 2, 3)):
            problems.append(f'{language} first launch: the window does not follow the profile chosen: {heights}')
    return problems


TITLES = {1: 'pdfLaTeX', 2: 'XeLaTeX', 3: 'LuaLaTeX', 4: 'LaTeX + dvipdfmx', 6: 'pLaTeX + dvipdfmx', 7: 'upLaTeX + dvipdfmx', 8: 'LaTeX + dvips + Ghostscript'}

# Each production rule broken in turn; the probe must notice.
MUTATIONS = {
    'latexmk does not replace the list': ('    _latexmk = sender.selectedSegment == 1;\n    [self showRows];', '    _latexmk = sender.selectedSegment == 1;'),
    'latexmk read the other way': ('    _latexmk = sender.selectedSegment == 1;', '    _latexmk = sender.selectedSegment != 1;'),
    'the choice shows the other form': ('_latexmkChoice.selectedSegment = latexmk ? 1 : 0;', '_latexmkChoice.selectedSegment = latexmk ? 0 : 1;'),
    'no MetaPost row': ('    add(NSLocalizedString(@"Engine profile row: MetaPost", @"Engine profile list: the MetaPost command"), values[MetaPostEngineKey], YES, MetaPostEngineKey);\n', ''),
    'no dictionary row': ('    if (values[spellingAutomaticDefaultKey] != nil) {\n', '    if (NO) {\n'),
    'every row marked': ('@(settings != nil && !TSEngineProfileSame([settings objectForKey:key], values[key]))', '@(settings != nil)'),
    'marks against the factory settings': ('@(settings != nil && !TSEngineProfileSame([settings objectForKey:key], values[key]))',
                                           '@(settings != nil && !TSEngineProfileSame([[[NSUserDefaults alloc] initWithSuiteName:@"none"] objectForKey:key], values[key]))'),
    'dictionary marked by the stored language': ('@(settings != nil && ![settings boolForKey:spellingAutomaticDefaultKey])',
                                                 '@(settings != nil && ![[settings objectForKey:spellingLanguageDefaultKey] isEqual:@" "])'),
    'unchanged rows not dimmed': ('NSColor *color = !marks || (changes && set) ? NSColor.labelColor : NSColor.secondaryLabelColor;', 'NSColor *color = !marks || set ? NSColor.labelColor : NSColor.secondaryLabelColor;'),
    'marks on first launch': ('profile:profile latexmk:NO settings:nil menu:YES];', 'profile:profile latexmk:NO settings:[TSMemoryDefaults new] menu:YES];'),
    'the profile menu does not replace the list': ('    _profile = sender.selectedTag;\n    [self showRows];', '    _profile = sender.selectedTag;'),
    'commands in the system font': ('TSEngineProfileListField(value, command ? mono : font, valueWidth)', 'TSEngineProfileListField(value, font, valueWidth)'),
    'choices in the monospaced font': ('TSEngineProfileListField(value, command ? mono : font, valueWidth)', 'TSEngineProfileListField(value, mono, valueWidth)'),
    'switches shown by their stored value': ('return [values[key] boolValue] ? NSLocalizedString(@"On", @"Engine profile list: a setting turned on") : NSLocalizedString(@"Off", @"Engine profile list: a setting turned off");',
                                             'return [values[key] description];'),
    'the method of the other place': ('name(direct ? @"group.typesetting.4.title" : @"group.typesetting.5.title")', 'name(direct ? @"group.typesetting.5.title" : @"group.typesetting.4.title")'),
    'names from Settings': ('add(NSLocalizedString(@"Engine profile row: New Document Encoding", @"Engine profile list: the encoding for new documents of Settings > Documents"),',
                            'add(name(@"catalog.documents.0.0.title"),'),
    'names wrap': ('        NSTextField *nameField = [NSTextField labelWithString:row[0]];', '        NSTextField *nameField = TSEngineProfileListField(row[0], font, 60);'),
    'the window does not follow the list': ('    _list.heightChanged = ^{ [weakSelf layOut]; };\n', ''),
    'no spacing after the names': ('    [grid columnAtIndex:nameColumn].trailingPadding = spacing;\n', ''),
    'the checkbox off the middle of its name': ('nameField.firstBaselineAnchor constant:-middle]];', 'nameField.firstBaselineAnchor constant:-middle + 4]];'),
    'checkboxes of the regular size': ('                check.controlSize = NSControlSizeSmall;\n', ''),
    'the dot before the name': ('        [cells addObject:nameField];\n        if (marks) [cells addObject:dot];', '        if (marks) [cells addObject:dot];\n        [cells addObject:nameField];'),
    'the dot not faint when off': ('NSColor *dotColor = set ? NSColor.controlAccentColor : [NSColor.controlAccentColor colorWithAlphaComponent:0.35];', 'NSColor *dotColor = NSColor.controlAccentColor;'),
    'not struck through': ('    if (changes && !set) attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);\n', ''),
    'values turned off still written': ('    [values removeObjectsForKeys:_kept.allObjects];\n', ''),
    'values turned off forgotten with latexmk': ('    _latexmk = sender.selectedSegment == 1;', '    _latexmk = sender.selectedSegment == 1; [_kept removeAllObjects];'),
    'checkboxes always on': ('check.state = [_kept intersectsSet:[NSSet setWithArray:row[4]]] ? NSControlStateValueOff : NSControlStateValueOn;', 'check.state = NSControlStateValueOn;'),
    'turning a value off not told': ('        if ([_rows[i][3] boolValue] && ![self rowIsSet:i]) return YES;\n', ''),
    'OK always enabled': ('    self.applyButton.enabled = set || !changes;', '    self.applyButton.enabled = YES;'),
    'OK not on Return': ('    _window.defaultButtonCell = _okButton.cell;\n', '    _window.defaultButtonCell = nil; _okButton.keyEquivalent = @"";\n'),
    'Cancel not on Escape': ('    _cancelButton.keyEquivalent = @"\\e";\n', ''),
    'OK at the left': ('    [_cancelButton setFrameOrigin:NSMakePoint(NSMinX(_okButton.frame) - 12 - NSWidth(_cancelButton.frame), y)];',
                       '    [_cancelButton setFrameOrigin:NSMakePoint(NSMinX(_okButton.frame) - 12 - NSWidth(_cancelButton.frame), y)]; { NSPoint o = _okButton.frame.origin; [_okButton setFrameOrigin:_cancelButton.frame.origin]; [_cancelButton setFrameOrigin:NSMakePoint(width - margin - NSWidth(_cancelButton.frame), o.y)]; }'),
    'OK answers Cancel': ('NSModalResponse response = sender == _okButton ? NSModalResponseOK : NSModalResponseCancel;', 'NSModalResponse response = NSModalResponseCancel;'),
    'no heading': ('    [content addSubview:_heading];\n', ''),
}


def main():
    original = PREFERENCES.read_text()
    with tempfile.TemporaryDirectory(prefix='texshop-engine-profile-list-') as tmp:
        tmp = Path(tmp)
        for key in ['On', 'Off', 'Run LaTeX:', 'Without latexmk', 'With latexmk', 'Values to Set'] + ['Engine profile row: ' + n for n in ROW_NAMES]:
            for language in LANGUAGES:
                text = table(language, 'Localizable').get(key)
                if not text:
                    print(f'FAIL: "{key}" has no text in {language}')
                    return 1
        results, error = run_probe(compile_probe(tmp, original), tmp, LANGUAGES)
        if results is None:
            print('FAIL: the probe stopped:', error)
            return 1
        problems = check(results)
        if problems:
            print('\n'.join(problems[:40]))
            print(f'FAIL: {len(problems)} problems')
            return 1
        sheets = sum(len(r['sheets']) for r in results)
        print(f'PASS: the sheet in {sheets} cases and the first-launch window in {len(results)} languages: short names on one line, '
              'the values of the profile and its latexmk form, checkboxes and dots on what changes from the settings in use, '
              'values turned off kept and left out and told, OK disabled with none on, the window following the list, OK and Cancel at the '
              'bottom right on Return and Escape, nothing cut')
        missed = []
        for name, (old, new) in MUTATIONS.items():
            if original.count(old) != 1:
                print(f'FAIL: mutation "{name}" does not apply')
                return 1
            try:
                binary = compile_probe(tmp, original.replace(old, new))
            except subprocess.CalledProcessError:
                print(f'FAIL: mutation "{name}" does not compile')
                return 1
            mutated, _ = run_probe(binary, tmp, ['ja'], ['ja'])
            if mutated is not None and not check(mutated):
                missed.append(name)
        if missed:
            print('FAIL: mutations not detected:', ', '.join(missed))
            return 1
        print(f'PASS: {len(MUTATIONS)} mutations detected')
    return 0


if __name__ == '__main__':
    sys.exit(main())
