#!/usr/bin/env python3
"""Manually verify curated source citations; never invoked by the MCP server."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', action='append', default=[], metavar='ALIAS=ROOT',
                        help='Explicit authorized checkout root; required for every cited repository.')
    args = parser.parse_args()
    roots = {}
    for item in args.repository:
        alias, separator, root = item.partition('=')
        if not separator or alias not in {'aegis-flow', 'abc', 'socal'} or not root:
            parser.error('Use an explicit aegis-flow, abc or socal repository alias and root.')
        if alias in roots:
            parser.error('A repository alias may be supplied only once.')
        roots[alias] = Path(root).resolve(strict=True)
        if not roots[alias].is_dir():
            parser.error('Each repository root must be a directory.')

    directory = Path(__file__).resolve().parent
    catalog = json.loads((directory / 'catalog.json').read_text())
    checked = {}
    references = 0
    failures = []
    for filename in catalog['files']:
        if not re.fullmatch(r'[a-z0-9][a-z0-9-]*\.json', filename):
            raise ValueError('Catalog entries must be JSON basenames.')
        document_path = (directory / filename).resolve(strict=True)
        if document_path.parent != directory:
            raise ValueError('Catalog document escaped the knowledge directory.')
        document = json.loads(document_path.read_text())
        for source in document['sources']:
            references += 1
            repo = source['repository']
            relative = source['path']
            path = PurePosixPath(relative)
            if path.is_absolute() or '..' in path.parts or '\\' in relative:
                raise ValueError('Source citations must be repository-relative paths without traversal.')
            if repo not in roots:
                raise ValueError('Missing explicit repository root: ' + repo)
            resolved = (roots[repo] / relative).resolve(strict=True)
            if not resolved.is_relative_to(roots[repo]) or not resolved.is_file():
                raise ValueError('A cited file escaped its explicitly authorized repository root.')
            key = (repo, relative)
            if key not in checked:
                data = resolved.read_bytes()
                checked[key] = (hashlib.sha256(data).hexdigest(), len(data.decode('utf-8').splitlines()))
            digest, line_count = checked[key]
            span = source['lines']
            if digest != source['sha256']:
                failures.append(filename + ':' + source['id'] + ' source hash mismatch')
            if not (isinstance(span['start'], int) and isinstance(span['end'], int)
                    and 1 <= span['start'] <= span['end'] <= line_count):
                failures.append(filename + ':' + source['id'] + ' invalid line range')
    for failure in failures:
        print('FAIL: ' + failure)
    if failures:
        return 1
    print('PASS: ' + str(references) + ' citations; ' + str(len(checked))
          + ' unique local source hashes and line ranges match. Org state not checked.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
