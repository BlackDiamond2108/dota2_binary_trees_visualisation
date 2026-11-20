#!/usr/bin/env python3
"""Transport fallback for Dota builds returning nil from the HTTP API.
Reads only tagged commands from console.log; forwards to the C++ localhost API.
Writes data-only Valve KeyValues atomically. Never executes received text.
"""
from pathlib import Path
import re
import os
import time
import urllib.request
import urllib.error
DOTA = Path(os.environ.get('DOTA_GAME_DIR', str(Path.home() / '.local/share/Steam/steamapps/common/dota 2 beta/game')))
LOG = DOTA / 'dota/console.log'
OUT = DOTA / 'dota_addons/tree_visualizer/scripts/npc/tree_response.txt'
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
PATTERN = re.compile(r'\[BST_REQUEST\] ([0-9_]+) (state|demo|clear|(?:insert|delete|find|big_demo)/-?\d+)\s*$')
def respond(request_id, endpoint, keys=None):
    try:
        request = urllib.request.Request('http://127.0.0.1:8765/' + endpoint,
            data=(' '.join(keys).encode('ascii') if keys is not None else None),
            headers={'Content-Type': 'text/plain'})
        with OPENER.open(request, timeout=10) as response:
            lines = response.read().decode('ascii').splitlines()
        magic, count, status = lines[0].split()
        if magic != 'BST1' or not count.isdigit() or not re.fullmatch(r'\w+', status):
            raise ValueError('Invalid backend reply')
        rows = []
        for i, row in enumerate(lines[1:]):
            if not re.fullmatch(r'-?\d+ (?:none|-?\d+) \d+ \d+ [01]', row):
                raise ValueError('Invalid backend node')
            rows.append(f'"{i}" "{row}"')
        result = f'"BSTResponse" {{ "id" "{request_id}" "count" "{count}" "status" "{status}" "rows" {{ '+ ' '.join(rows) + ' } }\n'
    except Exception as error:
        print('Bridge request failed:', error, flush=True)
        result = f'"BSTResponse" {{ "id" "{request_id}" "error" "backend_unavailable_or_invalid_request" }}\n'
    tmp = OUT.with_suffix('.tmp'); tmp.write_text(result); tmp.replace(OUT)
    print(endpoint, '->', request_id, flush=True)
def main():
    while not LOG.exists(): time.sleep(.2)
    with LOG.open(errors='replace') as stream:
        stream.seek(0, 2)
        print('Watching Dota console for BST commands', flush=True)
        batches = {}
        while True:
            line = stream.readline()
            if not line:
                if LOG.stat().st_size < stream.tell(): stream.seek(0)
                time.sleep(.05); continue
            match = PATTERN.search(line)
            if match:
                respond(*match.groups()); continue
            begin = re.search(r'\[BST_BATCH_BEGIN\] ([0-9_]+) (\d+)\s*$', line)
            part = re.search(r'\[BST_BATCH_PART\] ([0-9_]+) (-?\d+(?:,-?\d+)*)\s*$', line)
            end = re.search(r'\[BST_BATCH_END\] ([0-9_]+)\s*$', line)
            if begin:
                # Lua allows only one in-flight request; discard any abandoned batch.
                batches = {begin[1]: (int(begin[2]), [])}
            elif part and part[1] in batches:
                batches[part[1]][1].extend(part[2].split(','))
            elif end and end[1] in batches:
                expected, keys = batches.pop(end[1])
                if len(keys) == expected:
                    respond(end[1], 'delete_many', keys)
                else:
                    print('Incomplete batch:', end[1], flush=True)
                    OUT.write_text(f'"BSTResponse" {{ "id" "{end[1]}" "error" "incomplete_batch" }}')
if __name__ == '__main__': main()
