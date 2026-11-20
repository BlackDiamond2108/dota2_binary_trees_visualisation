#!/usr/bin/env python3
"""Install source addon files without modifying Dota's original resources."""
import argparse
import os
from pathlib import Path
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('--dota', type=Path, default=Path(os.environ.get('DOTA_GAME_DIR', str(Path.home() / '.local/share/Steam/steamapps/common/dota 2 beta/game'))), help='Dota game directory (contains dota/ and dota_addons/)')
args = parser.parse_args()
if not (args.dota / 'dota').is_dir():
    parser.error('Dota game directory not found; specify --dota /path/to/dota\\ 2\\ beta/game')
source = Path(__file__).resolve().parent / 'addon'
target = args.dota / 'dota_addons/tree_visualizer'
shutil.copytree(source, target, dirs_exist_ok=True, ignore=shutil.ignore_patterns('tree_response.txt', 'tree_response.tmp'))
print('Installed addon:', target)
print('Dota console: dota_launch_custom_game tree_visualizer test_basic')
