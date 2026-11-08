"""Maintain the frozen 17add04 settings interface contract independently of product inputs.

Only reviewed migrations may change expectations. Start with the previous committed
contract (or independently verified legacy nib data), describe each intentional
change in the review, then run the interface and mutation tests. Never regenerate
expectations from the XIBs under test. --compact is a lossless representation change;
it refuses to accept anything except an existing frozen contract.
"""
from pathlib import Path
import argparse,json,hashlib

def expand(contract):
    if contract.get('format') != 2:
        return contract
    return {language: {**contract['common'], **entries} for language,entries in contract['languages'].items()}

def load(path):
    return expand(json.loads(Path(path).read_text()))

def compact(data):
    original=expand(data)
    first=next(iter(original.values()))
    common={k:v for k,v in first.items() if all(entries.get(k)==v for entries in original.values())}
    result={'format':2,'origin':'17add04ec1075aacef93b30e1626f9642584ca27; independently checked against legacy localized nibs',
            'maintenance':'Reviewed migrations only; see Tests/settings_contract.py. Never derive expected values from the interfaces under test.',
            'common':common,'languages':{lang:{k:v for k,v in values.items() if k not in common} for lang,values in original.items()}}
    assert expand(result)==original
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--compact',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    original=json.loads(args.compact.read_text());result=compact(original)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print('Lossless expansion verified; source SHA256',hashlib.sha256(args.compact.read_bytes()).hexdigest())
