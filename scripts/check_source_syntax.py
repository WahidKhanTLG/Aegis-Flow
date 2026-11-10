"""Check project-owned JSON, Python, shell, and standalone Node source without executing it."""

import ast
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
ROOT_FILES = ('package.json', 'package-lock.json', 'sfdx-project.json', 'jest.config.js', 'eslint.config.cjs')
SOURCE_DIRECTORIES = ('scripts', 'integrations', 'force-app/test', 'packaging', 'tools/lint')


def main():
    files = {ROOT / name for name in ROOT_FILES}
    for name in SOURCE_DIRECTORIES:
        files.update(path for path in (ROOT / name).rglob('*') if path.is_file() and 'node_modules' not in path.parts)
    files.update((ROOT / 'force-app').rglob('*.json'))
    counts = {'json': 0, 'python': 0, 'shell': 0, 'node': 0}
    errors = []
    for path in sorted(files):
        relative = str(path.relative_to(ROOT))
        try:
            if path.suffix == '.json':
                json.loads(path.read_text())
                counts['json'] += 1
            elif path.suffix == '.py':
                ast.parse(path.read_text(), filename=relative)
                counts['python'] += 1
            elif path.suffix in ('.sh', '.js', '.cjs', '.mjs'):
                shell = path.suffix == '.sh'
                command = ['bash', '-n', str(path)] if shell else ['node', '--check', str(path)]
                result = subprocess.run(command, capture_output=True, text=True, check=False)
                counts['shell' if shell else 'node'] += 1
                if result.returncode:
                    errors.append({'file': relative, 'message': result.stderr.strip()})
        except (OSError, SyntaxError, ValueError) as error:
            errors.append({'file': relative, 'message': str(error)})
    print(json.dumps({'filesChecked': counts, 'errors': errors}, indent=2))
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
