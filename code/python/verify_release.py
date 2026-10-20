"""Verify shipped files and, optionally, extracted raw records. Standard library only.
Run from repository root: python code/python/verify_release.py [--raw data/raw]
No simulation is run; checksum agreement is not scientific validation.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path

def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw', type=Path, help='Folder containing extracted *_data.mat files')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    errors = []
    manifest = json.loads((root/'audit/repository_sha256.json').read_text())
    for name, expected in manifest.items():
        p = root/name
        if not p.is_file():
            errors.append('MISSING repository file: '+name)
        elif sha256(p) != expected:
            errors.append('CHANGED repository file: '+name)
    with (root/'docs/CASE_INDEX.csv').open(encoding='utf-8-sig', newline='') as f:
        cases = list(csv.DictReader(f))
    audited = json.loads((root/'audit/raw_sha256.json').read_text())
    if len(cases) != 37 or len({row['Case'] for row in cases}) != 37:
        errors.append('Expected 37 unique case records')
    for name, expected in audited.items():
        rows = [row for row in cases if row['RawFile'] == name]
        if len(rows) != 1 or rows[0]['SHA256'] != expected:
            errors.append('Audit/index mismatch: '+name)
    if args.raw is not None:
        for row in cases:
            p = args.raw/row['RawFile']
            if not p.is_file():
                errors.append('MISSING raw record: '+row['RawFile'])
            elif sha256(p) != row['SHA256']:
                errors.append('RAW CHECKSUM MISMATCH: '+row['RawFile'])
    if errors:
        print('\n'.join(errors))
        raise SystemExit(1)
    print(f'PASS: {len(manifest)} repository files; 37 case records; 13 audited hashes consistent.')
    if args.raw is not None:
        print('PASS: all 37 extracted raw records match the collection checksums.')
    else:
        print('Raw data not checked in this invocation. Use --raw PATH to check them.')
    print('This check does not run MATLAB or validate new simulation results.')

if __name__ == '__main__':
    main()
