"""Verify verbatim production code embedded in an isolated harness before compiling it.

Complete methods use a comment/string-aware brace scanner. Statement spans must
be unique in the current source and remain byte-for-byte present in the harness.
Explicit mutation runners verify the normal harness first, then mutate that copy.
This proves extraction fidelity, not integration with the full document object.
"""
import hashlib

def closing_brace(source, opening):
    assert source[opening]=='{', 'Fragment opening brace missing'
    i=opening;depth=0
    while i<len(source):
        if source.startswith('//',i):
            i=source.find('\n',i)
            if i<0:break
            continue
        if source.startswith('/*',i):
            end=source.find('*/',i+2);assert end>=0,'Unclosed production comment';i=end+2;continue
        c=source[i]
        if c in ('"',"'"):
            quote=c;i+=1
            while i<len(source) and source[i]!=quote:i+=2 if source[i]=='\\' else 1
            assert i<len(source),'Unclosed production literal'
        elif c=='{':depth+=1
        elif c=='}':
            depth-=1
            if depth==0:return i+1
        i+=1
    raise AssertionError('Unclosed production method')

def method(source,signature):
    assert source.count(signature)==1, 'Production method marker must be unique: '+signature
    start=source.index(signature);end=closing_brace(source,source.index('{',start))
    return source[start:end]

def verify_embedded(program,fragments):
    for label,source,fragment in fragments:
        assert fragment and source.count(fragment)==1, 'Fragment differs from current production source: '+label
        assert fragment in program, 'Generated harness differs from production fragment: '+label
        if label.startswith('complete method:'):
            start=fragment.index('{');assert closing_brace(fragment,start)==len(fragment.rstrip()),'Truncated production method: '+label
        print('PRODUCTION FRAGMENT',label,hashlib.sha256(fragment.encode()).hexdigest(),flush=True)

def objc_class(source,name):
    """A class declared and implemented in one production file: its @interface through the @end of its @implementation."""
    start_marker='@interface '+name+' : ';impl_marker='\n@implementation '+name+'\n'
    assert source.count(start_marker)==1 and source.count(impl_marker)==1, 'Production class marker must be unique: '+name
    start=source.index(start_marker);impl=source.index(impl_marker,start)
    end=source.index('\n@end\n',impl)+len('\n@end\n')
    return source[start:end]
