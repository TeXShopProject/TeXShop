#!/usr/bin/env python3
"""Exercise extraction verification independently of the methods under test."""
import contextlib
import io
from production_fragments import method, verify_embedded

source = '''- (void)example {
    NSString *s = @"escaped \\\" } literal";
    // } ignored
    /* { ignored */
    if (YES) { work(); }
}
- (void)other { other(); }
'''
fragment = method(source, '- (void)example')
assert fragment.endswith('work(); }\n}')
with contextlib.redirect_stdout(io.StringIO()):
    verify_embedded(fragment, [('complete method:example', source, fragment)])

def rejects(name, callback, expected):
    try:
        callback()
    except AssertionError as error:
        assert expected in str(error), (name, str(error))
    else:
        raise AssertionError('Verification accepted '+name)
    print('DETECTED extraction fault:', name)

rejects('changed production body', lambda: verify_embedded(fragment, [('body', source.replace('work()', 'changed()'), fragment)]), 'differs from current production')
rejects('changed harness body', lambda: verify_embedded(fragment.replace('work()', 'changed()'), [('body', source, fragment)]), 'harness differs')
rejects('omitted fragment', lambda: verify_embedded('', [('body', source, fragment)]), 'harness differs')
rejects('truncated method', lambda: verify_embedded(fragment[:-1], [('complete method:example', source, fragment[:-1])]), 'Unclosed production method')
rejects('ambiguous marker', lambda: method(source+source, '- (void)example'), 'must be unique')
rejects('missing marker', lambda: method(source, '- (void)absent'), 'must be unique')
rejects('unclosed literal', lambda: method('- (void)broken { @"}', '- (void)broken'), 'Unclosed production literal')
verify_embedded(fragment, [('complete method:example', source, fragment)])
print('NORMAL CONTROL: comments, escaped literals, nesting and exact source/harness equality')
