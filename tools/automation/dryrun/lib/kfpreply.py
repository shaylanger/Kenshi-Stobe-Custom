"""kfpreply.py -- render KenshiFP replies in their REAL format (kfp_formats.json, made by gen_kfp_formats.py from the
KenshiFP source), so take scripts that grep a field see it where the game prints it. render(name, **values): every
field of the format in its real order; a field given in values replaces its whole value text (str() of it), the rest
get neutral defaults (0, 0.00, '-', ...) in the field's own printf shape (vectors keep their commas)."""
import json, os, re

_F = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kfp_formats.json')))
_SPEC = re.compile(r'%([-0-9]*)(?:\.(\d+))?(ll|l)?([a-zA-Z])')
_FIELD = re.compile(r'(\w+)=(\S*%\S*)')


def _default(m):
    prec, conv = m.group(2), m.group(4)
    if conv == 'f':
        return '%.*f' % (int(prec or 6), 0.0)
    if conv == 's':
        return '-'
    if conv == 'c':
        return 'R'
    if conv == 'p':
        return '0000000000000000'
    return '0'


def render(name, **v):
    def field(m):
        k = m.group(1)
        if k in v:
            return '%s=%s' % (k, v[k])
        return '%s=%s' % (k, _SPEC.sub(_default, m.group(2)))
    fmt = _F[name] + (_F['combat_shot'] if name == 'combat' else '')
    return _FIELD.sub(field, fmt).replace('%%', '%').strip()
