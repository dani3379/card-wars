"""
Reverses CP1251-roundtrip mojibake in GDScript source files.

The corruption pattern: UTF-8 bytes were once read by a tool that
interpreted them as Windows-1251 (Cyrillic), then re-saved them as UTF-8
of the resulting Cyrillic characters. So an arrow "←" (UTF-8: E2 86 90)
turned into "в†ђ" (UTF-8: D0 B2 E2 80 A0 D0 92).

To reverse: take each non-ASCII cluster, encode it as CP1251 (recovering
the misread byte values), then decode those bytes as UTF-8 (recovering
the original character). If the result is a sensible character in a known
"safe" range (box drawing, arrows, common symbols), accept the fix;
otherwise leave the cluster alone (it's probably real Cyrillic text or a
correctly-encoded em-dash that just happens to be non-ASCII).
"""
import re
import sys


def is_safe_char(c):
    cp = ord(c)
    # Arrows, math, misc tech
    if 0x2190 <= cp <= 0x23FF:
        return True
    # Box drawing & block elements
    if 0x2500 <= cp <= 0x259F:
        return True
    # Misc symbols (⚔ etc)
    if 0x2600 <= cp <= 0x26FF:
        return True
    # General punctuation (em-dash, ellipsis, etc — but these usually
    # don't NEED fixing because they were already encoded correctly;
    # included here so any round-trip that lands on one is accepted)
    if 0x2010 <= cp <= 0x205F:
        return True
    # Latin-1 supplement (×, °, ·, ±, ü, etc)
    if 0x00A0 <= cp <= 0x00FF:
        return True
    return False


def unmojibake_cluster(s):
    """Returns the un-corrupted string, or None if the round-trip fails
    or produces something that doesn't look like a sensible char."""
    try:
        recovered = s.encode('cp1251').decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError):
        return None
    if not all(is_safe_char(c) for c in recovered):
        return None
    return recovered


def fix_file(path):
    with open(path, 'rb') as f:
        text = f.read().decode('utf-8')

    changes = []

    def replace(match):
        cluster = match.group()
        fix = unmojibake_cluster(cluster)
        if fix is not None and fix != cluster:
            changes.append((cluster, fix))
            return fix
        return cluster

    fixed = re.sub(r'[^\x00-\x7f]+', replace, text)

    if changes:
        with open(path, 'wb') as f:
            f.write(fixed.encode('utf-8'))
        return changes
    return []


if __name__ == '__main__':
    for path in sys.argv[1:]:
        changes = fix_file(path)
        if changes:
            print(f'[{path}] {len(changes)} replacements')
            # show unique substitutions
            seen = set()
            for src, dst in changes:
                if (src, dst) not in seen:
                    seen.add((src, dst))
                    # repr the strings so they survive stdout encoding
                    print(f'  {repr(src)[:60]} -> {repr(dst)}')
        else:
            print(f'[{path}] no changes')
