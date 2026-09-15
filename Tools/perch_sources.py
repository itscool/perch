"""Where Perch's sources live, by name.

Every check tool compiles a hand-picked subset of files. They ask for files by
basename here, so moving a file between directories never breaks a tool, and
the build scripts walk the same roots recursively. Names are globally unique.
"""
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ROOTS = [REPO / 'Sources', REPO / 'Tests']

_index = None

def index():
    global _index
    if _index is None:
        _index = {}
        for root in ROOTS:
            for path in sorted(root.rglob('*')):
                if path.is_file() and path.suffix in ('.swift', '.c', '.h', '.m'):
                    if path.name in _index:
                        raise SystemExit(f'Duplicate source name: {path} and {_index[path.name]}')
                    _index[path.name] = path
    return _index

def source(name):
    """Absolute path of a source file given its basename."""
    try:
        return index()[str(name)]
    except KeyError:
        raise SystemExit(f'Unknown source file: {name}')

def sources(names):
    return [source(n) for n in names]

def all_swift(include_tests=True):
    return sorted(p for p in index().values() if p.suffix == '.swift' and (include_tests or not p.name.endswith('Tests.swift')))
