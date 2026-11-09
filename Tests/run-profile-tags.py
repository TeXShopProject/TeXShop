#!/usr/bin/env python3
"""Named profile menu tags retain the independent legacy resource mapping."""
from pathlib import Path
import subprocess
import tempfile

r = Path(__file__).resolve().parents[1]
names = ['FactoryDefaults', 'Defaults_upTeX_ptex2pdf', 'Defaults_upTeX_latexmk',
         'Defaults_upTeX_script', 'Defaults_pTeX_ptex2pdf', 'Defaults_pTeX_latexmk',
         'Defaults_pTeX_script', 'Defaults_pTeX_sjis', 'Defaults_pTeX_euc']
program = '''#import "TSPreferenceProfile.h"
int main(void){@autoreleasepool{
 NSArray *expected=@[NAMES];
 for(NSInteger tag=1;tag<=9;tag++)if(![TSPreferenceProfileNameForTag((TSPreferenceProfileTag)tag)isEqual:expected[tag-1]]){fprintf(stderr,"FAIL: profile tag mapping\n");return 1;}
 for(NSNumber *tag in @[@(-1),@0,@10,@999])if(TSPreferenceProfileNameForTag((TSPreferenceProfileTag)tag.integerValue)!=nil){fprintf(stderr,"FAIL: unknown profile tag\n");return 1;}
 puts("PASS: nine named tags and four invalid tags");return 0;
}}
'''.replace('mapping\n', 'mapping\\n').replace('tag\n', 'tag\\n').replace('NAMES', ','.join('@"'+name+'"' for name in names))
with tempfile.TemporaryDirectory(prefix='texshop-profile-tags-') as temp:
    t = Path(temp)
    (t/'probe.m').write_text(program)
    original = (r/'Sources/TSPreferenceProfile.h').read_text()
    def run(header):
        (t/'TSPreferenceProfile.h').write_text(header)
        subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror',
                        '-I',str(t),'-I',str(r/'Sources'),'-framework','Foundation',
                        str(t/'probe.m'),'-o',str(t/'probe')],check=True)
        return subprocess.run([str(t/'probe')],capture_output=True,text=True)
    result=run(original);assert result.returncode==0,result.stderr
    print(result.stdout,flush=True)
    for i,name in enumerate(names):
        old='@"'+name+'"';assert original.count(old)==1
        result=run(original.replace(old,'@"'+names[(i+1)%9]+'"'))
        assert result.returncode and 'FAIL: profile tag mapping' in result.stderr,(name,result.stderr)
        print('DETECTED tag',i+1,flush=True)
    result=run(original.replace('return names[@(tag)];','return names[@(tag)] ?: @"FactoryDefaults";'))
    assert result.returncode and 'FAIL: unknown profile tag' in result.stderr,result.stderr
    print('DETECTED invalid-tag fallback',flush=True)
    result=run(original);assert result.returncode==0,result.stderr
    print('NORMAL CONTROL',result.stdout)
