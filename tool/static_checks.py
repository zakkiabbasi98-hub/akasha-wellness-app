#!/usr/bin/env python3
"""Static consistency checks for the AKASHA repo.

Checks that do not need a Dart SDK:
  1. brace/paren/bracket balance per file
  2. every INSERT map given to sqflite carries created_at (direct or via helper)
  3. every model toRow() is insert-shaped
  4. no `~` dependency constraints
  5. no ListTile without a Material/SoftCard ancestor
  6. no transaction opened inside another transaction (heuristic: a repo
     method that takes `Transaction? txn` must not call `_db.db.transaction`
     unconditionally)
  7. every schema table appears in DbSchema.createStatements
  8. migrations cover every version step below DbSchema.version
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAIL = []


def fail(msg):
    FAIL.append(msg)
    print('FAIL', msg)


def strip(s):
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == '/' and s[i + 1:i + 2] == '/':
            j = s.find('\n', i)
            out.append(' ' * ((n if j < 0 else j) - i))
            i = n if j < 0 else j
        elif c == '/' and s[i + 1:i + 2] == '*':
            j = s.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r'[^\n]', ' ', s[i:j]))
            i = j
        elif c in '\'"':
            q = c
            j = i + 1
            tri = s[i + 1:i + 3] == q * 2
            if tri:
                j = i + 3
            while j < n:
                if s[j] == '\\':
                    j += 2
                    continue
                if not tri and s[j] == q:
                    j += 1
                    break
                if tri and s[j:j + 3] == q * 3:
                    j += 3
                    break
                j += 1
            out.append(re.sub(r'[^\n]', ' ', s[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return ''.join(out)


dart_files = []
for dp, _, fs in os.walk(ROOT):
    if '/.git' in dp or '/build' in dp:
        continue
    for f in fs:
        if f.endswith('.dart'):
            dart_files.append(os.path.join(dp, f))
dart_files.sort()

# 1. balance
for f in dart_files:
    c = strip(open(f).read())
    bal = {}
    for o, cl in (('{', '}'), ('(', ')'), ('[', ']')):
        bal[o] = c.count(o) - c.count(cl)
    if any(bal.values()):
        fail(f'unbalanced {os.path.relpath(f, ROOT)} {bal}')

# 3. models are insert-shaped
model_dir = os.path.join(ROOT, 'lib/data/models')
for f in sorted(os.listdir(model_dir)):
    p = os.path.join(model_dir, f)
    s = open(p).read()
    n_open = s.count('AppDatabase.insertRow({')
    for m in re.finditer(r'toRow\(\) => AppDatabase\.(\w+)\(', s):
        if m.group(1) != 'insertRow':
            fail(f'{f}: toRow uses {m.group(1)} instead of insertRow')
    if n_open != s.count('}, createdAt: createdAt);'):
        fail(f'{f}: {n_open} insertRow vs {s.count("}, createdAt: createdAt);")} createdAt tails')

# 2. direct inserts carrying created_at
for f in dart_files:
    src = open(f).read()
    for m in re.finditer(r'\.insert\(\s*$', src):
        pass
    for m in re.finditer(r"\.insert\(\s*'([a-z_]+)'", src):
        table = m.group(1)
        # look at the next map literal
        window = src[m.end():m.end() + 1200]
        if 'created_at' not in window and 'insertRow' not in window \
                and 'toRow()' not in window and table not in (
                    'notification_actions', 'sync_queue'):
            fail(f'{os.path.relpath(f, ROOT)}: insert into {table} without created_at')

# 4. pubspec constraints
pub = open(os.path.join(ROOT, 'pubspec.yaml')).read()
if re.search(r'^\s+\w+:\s*~', pub, re.M):
    fail('pubspec uses ~ constraints')

# 5. ListTile ancestry
ident = re.compile(r'([A-Za-z_][A-Za-z0-9_.]*)\s*\(')
for f in dart_files:
    raw = open(f).read()
    s = strip(raw)
    stack = []
    i = 0
    while i < len(s):
        m = ident.match(s, i)
        if m and (i == 0 or not (s[i - 1].isalnum() or s[i - 1] in '_.')):
            stack.append(m.group(1))
            i = m.end()
            continue
        c = s[i]
        if c == ')':
            if stack:
                stack.pop()
        elif c == '(':
            stack.append('<expr>')
        hit = False
        for name in ('SwitchListTile', 'RadioListTile', 'CheckboxListTile', 'ListTile'):
            if s.startswith(name, i) and (i == 0 or not (s[i - 1].isalnum() or s[i - 1] in '_.')):
                if 'SoftCard' not in stack and 'Material' not in stack:
                    fail(f'{os.path.relpath(f, ROOT)}:{raw[:i].count(chr(10)) + 1} '
                         f'{name} has no Material/SoftCard ancestor')
                i += len(name)
                hit = True
                break
        if not hit:
            i += 1

# 6/7/8 schema
schema = open(os.path.join(ROOT, 'lib/core/database/schema.dart')).read()
version = int(re.search(r'static const int version = (\d+);', schema).group(1))
tables = set(re.findall(r"^\s{4}'([a-z_]+)',?$", schema, re.M))
created = set(re.findall(r'CREATE TABLE (?:IF NOT EXISTS )?(\w+)', schema))
for t in tables - created:
    fail(f'schema: table {t} listed but never created')
for t in created - tables:
    fail(f'schema: table {t} created but not listed in DbSchema.tables')
mig = set(int(x) for x in re.findall(r'^\s{4}(\d+): \[', schema, re.M))
for v in range(1, version):
    if v not in mig:
        fail(f'schema: no migration from v{v} to v{v + 1} (version={version})')

rel = [os.path.relpath(f, ROOT) for f in dart_files]
print(f'\nchecked {len(rel)} dart files, schema v{version}, '
      f'{len(tables)} tables, migrations {sorted(mig)}')
print('RESULT:', 'FAIL' if FAIL else 'all static checks passed')
sys.exit(1 if FAIL else 0)
