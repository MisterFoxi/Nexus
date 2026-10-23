#!/usr/bin/env python3
"""
compiler.py — Medical craft system (gor/medieval RP, Second Life/LSL)

Compiles readable sources (.src) into a flat, tokenized notecard, ready to
paste into a production bench. Runs on PC (dev/test).

Inputs:
  axes.src  vocabulary, BLOCK grammar:
              station <name>
              axis <l>.<a>              block: one piece of info per line
                  unit  <u>             optional (pH, C, %...); if absent: no unit
                  range <pmin> .. <pmax>   measured physical domain (required)
                  maps  <imin> .. <imax>   -> gameplay intensity; if absent: intensity IS the domain
                  band  <name> [<=|>= <v>]  band; no operator = neutral band (doc, rejected in when)
              <l>.<a> label
              <l>.<d> cat : v , v , ...
              <l>.<d> taxonomy
            The prefix (fab, act, org...) is only a READING group, not an
            engine-wired category: feel free to add more. The only rule: every
            axis used (tree.src / laws.src / a component NC) must be declared here.

  tree.src  taxonomy of CLASSES (not species), BLOCK grammar:
              class <node> [: <parent>]
                  aka  <alias> , ...    optional (the alias shares the canonical id)
                  axis <axis> = <delta> class trait (intensity), summed down the tree
              group <name>
                  member <class>        one member per line
            roots = no parent ; 3 levels max.
            A group is inherited by the descendants of its members.

  laws.src  laws + transformations (@station ; one law per line ; may gate on a node/group).
  ids.lock  frozen name->id registry (managed by this script, do not edit).

Output (notecard):
  tok:<name> = <id>             dimensions, cat values, nodes, groups, aliases (alias shares the id)
  tok:#<id> = <name>            INVERSE index (canonical name, aliases excluded) -> idToName on the LSL side in O(1)
  tax:<id>:toks  = id^id^..     tokens presented by a component pointing at this node (self+ancestors+groups)
  tax:<id>:trait = aid:val^..   accumulated class traits, to ADD to the component deltas at scan time
  law:<station>:<lid>:when      terms (tokenized)
  law:...:verdict               0=react 1=danger
  law:...:seq                   source rank (tie-break on equal elaboration: smallest seq wins)
  law:...:do / :cap             optional
  idx:<station>:lawprop:<tok>:<lid>   inverse index (key = presented token)

SPECIES never go through the compiler: a component is a runtime notecard
(free meta.name + meta.taxonomy=<node> + its prop: deltas).

Usage: python compiler.py axes.src tree.src laws.src > monde.nc
"""

import re, sys, os

VERDICTS = {"react": 0, "danger": 1}
MAX_DEPTH = 3

# --- axes.src : single-line ---
LABEL_RE = re.compile(r'^([a-z]+\.[a-z_]+)\s+label\s*$')
CAT_RE   = re.compile(r'^([a-z]+\.[a-z_]+)\s+cat\s*:\s*(.*\S)\s*$')
TAXD_RE  = re.compile(r'^([a-z]+\.[a-z_]+)\s+taxonomy\s*$')
STATION_RE = re.compile(r'^station\s+([a-z_]+)\s*$')
# --- axes.src : axis block ---
AXIS_OPEN_RE = re.compile(r'^axis\s+([a-z]+\.[a-z_]+)\s*$')
UNIT_RE      = re.compile(r'^unit\s+([A-Za-z%]+)\s*$')
RANGE_RE     = re.compile(r'^range\s+(-?\d+)\s*\.\.\s*(-?\d+)\s*$')
MAPS_RE      = re.compile(r'^maps\s+(-?\d+)\s*\.\.\s*(-?\d+)\s*$')
ZONE_RE      = re.compile(r'^range\s+([a-z_]+)\s+(-?\d+)\s*\.\.\s*(-?\d+)\s*$')   # named exclusive zone
# --- laws.src ---
HDR_RE   = re.compile(r'^@([a-z_]+)$')
LAWNAME_RE = re.compile(r'^law\s+([a-z0-9_]+)$')
COND_IS    = re.compile(r'^([a-z]+\.[a-z_]+)\s+is\s+([a-z_]+)$')     # num -> band ; cat/tax -> value
COND_CMP   = re.compile(r'^([a-z]+\.[a-z_]+)\s*(>=|<=)\s*(-?\d+)$')  # num threshold
COND_EQ    = re.compile(r'^([a-z]+\.[a-z_]+)\s*=\s*([a-z_]+)$')      # guided error: use 'is'
COND_PRES  = re.compile(r'^([a-z]+\.[a-z_]+)(?:\s+present)?$')
ACT_SET    = re.compile(r'^set\s+([a-z]+\.[a-z_]+)\s*=\s*([a-z_]+)$')
ACT_SCALE  = re.compile(r'^scale\s+(eff|qty|[a-z]+\.[a-z_]+)\s+x\s*([0-9.]+)$')
ACT_ADD    = re.compile(r'^add\s+([a-z]+\.[a-z_]+)$')
ACT_REM    = re.compile(r'^remove\s+([a-z]+\.[a-z_]+)$')
# --- tree.src : class / group block ---
CLASS_OPEN_RE = re.compile(r'^class\s+([a-z_]+)\s*(?::\s*([a-z_]+))?\s*$')
AKA_RE        = re.compile(r'^aka\s+(.*\S)\s*$')
CAXIS_RE      = re.compile(r'^axis\s+([a-z]+\.[a-z_]+)\s*=\s*(-?\d+)\s*$')
INERT_RE      = re.compile(r'^inert\s+([a-z]+\.[a-z_]+)\s*$')
NEED_RE       = re.compile(r'^need\s+([a-z_]+)(?:\s+(\d+))?\s*$')
GROUP_OPEN_RE = re.compile(r'^group\s+([a-z_]+)\s*$')
MEMBER_RE     = re.compile(r'^member\s+([a-z_]+)\s*$')

errors = []
warnings = []
def err(ln, msg): errors.append("[line %d] %s" % (ln, msg))
def strip(line):  return line.split('#', 1)[0].rstrip()

# ---------- persistent id registry ----------
class IdRegistry:
    def __init__(s, path):
        s.path, s.map, s._next = path, {}, 0
        if os.path.exists(path):
            for line in open(path, encoding="utf-8"):
                line = line.split('#', 1)[0].strip()
                if not line or '=' not in line: continue
                n, i = [x.strip() for x in line.split('=', 1)]
                try: s.map[n] = int(i)
                except ValueError: pass
            if s.map: s._next = max(s.map.values()) + 1
    def id(s, name):
        if name not in s.map: s.map[name] = s._next; s._next += 1
        return s.map[name]
    def save(s):
        out = ["# id registry — managed by compiler.py, DO NOT edit by hand"]
        out += ["%s = %d" % (n, i) for n, i in sorted(s.map.items(), key=lambda kv: kv[1])]
        open(s.path, "w", encoding="utf-8").write("\n".join(out) + "\n")

# ---------- vocabulary (axes.src) ----------
class Axis:
    kind = "num"
    def __init__(s, name, id_, pmin, pmax, unit, imin, imax):
        s.name, s.id, s.pmin, s.pmax, s.unit, s.imin, s.imax = name, id_, pmin, pmax, unit, imin, imax
        s.zones = {}       # name -> (phys_lo, phys_hi)
        s.zone_int = {}    # name -> (int_lo, int_hi), exclusive
    def to_int(s, phys): return round(s.imin + (phys - s.pmin) / (s.pmax - s.pmin) * (s.imax - s.imin))
class Label:
    kind = "label"
    def __init__(s, name, id_): s.name, s.id = name, id_
class Cat:
    kind = "cat"
    def __init__(s, name, id_): s.name, s.id, s.vals = name, id_, {}
class TaxDim:
    kind = "tax"
    def __init__(s, name, id_): s.name, s.id, s.vals = name, id_, {}   # vals filled by tree.src (nodes + groups + aliases)

def load_vocab(path, reg):
    dims, stations, taxdim = {}, [], None
    cur = None   # axis block in progress: {name, line, unit, pmin, pmax, imin, imax, bands}

    def finish_axis(c):
        if c is None: return
        if c['name'] in dims: err(c['line'], "redefined: %s" % c['name']); return
        if c['pmin'] is None:
            err(c['line'], "axis %s: missing 'range'" % c['name']); return
        pmin, pmax = c['pmin'], c['pmax']
        if c['imin'] is None:
            imin, imax = pmin, pmax          # no 'maps' => the domain IS the intensity
        else:
            imin, imax = c['imin'], c['imax']
        ax = Axis(c['name'], reg.id(c['name']), pmin, pmax, c['unit'], imin, imax)
        if ax.pmin == ax.pmax: err(c['line'], "%s: flat domain" % c['name'])
        ax.zones = c['zones']
        # zones -> intensity, sorted, clamped so neighbours stay mutually EXCLUSIVE
        zl = [[zn, ax.to_int(lo), ax.to_int(hi)] for zn, (lo, hi) in c['zones'].items()]
        zl.sort(key=lambda z: (z[1], z[2]))
        for k in range(len(zl) - 1):
            if zl[k][2] >= zl[k + 1][1]: zl[k][2] = zl[k + 1][1] - 1      # clamp silently (adjacent zones are fine)
        for zn, ilo, ihi in zl:
            if ihi < ilo:                                                # swallowed entirely -> unreachable
                warnings.append("axis %s: zone '%s' is unreachable (too narrow / overlaps a neighbour once mapped to intensity)" % (c['name'], zn))
            ax.zone_int[zn] = (ilo, ihi)
        dims[c['name']] = ax

    for i, raw in enumerate(open(path, encoding="utf-8"), 1):
        t = strip(raw).strip()
        if not t: continue
        first = t.split(None, 1)[0].lower()

        if first == "axis":
            finish_axis(cur); cur = None
            m = AXIS_OPEN_RE.match(t)
            if not m: err(i, "malformed axis header: %r" % t); continue
            cur = {'name': m.group(1), 'line': i, 'unit': None,
                   'pmin': None, 'pmax': None, 'imin': None, 'imax': None, 'zones': {}}
            continue

        if first in ("unit", "range", "maps"):
            if cur is None: err(i, "clause '%s' outside an axis block" % first); continue
            if first == "unit":
                m = UNIT_RE.match(t)
                if m: cur['unit'] = m.group(1)
                else: err(i, "malformed unit: %r" % t)
            elif first == "maps":
                m = MAPS_RE.match(t)
                if m: cur['imin'], cur['imax'] = int(m.group(1)), int(m.group(2))
                else: err(i, "malformed maps: %r" % t)
            else:  # 'range' = domain (range lo .. hi)  OR  named zone (range name lo .. hi)
                m = RANGE_RE.match(t)
                if m: cur['pmin'], cur['pmax'] = int(m.group(1)), int(m.group(2))
                else:
                    z = ZONE_RE.match(t)
                    if z:
                        if z.group(1) in cur['zones']: err(i, "zone redefined: %s" % z.group(1))
                        cur['zones'][z.group(1)] = (int(z.group(2)), int(z.group(3)))
                    else: err(i, "malformed range/zone: %r" % t)
            continue

        # anything else: closes the current axis block, then single-line dispatch
        finish_axis(cur); cur = None
        m = STATION_RE.match(t)
        if m: stations.append(m.group(1)); continue
        m = TAXD_RE.match(t)
        if m:
            name = m.group(1)
            if name in dims: err(i, "redefined: %s" % name)
            taxdim = TaxDim(name, reg.id(name)); dims[name] = taxdim; continue
        m = LABEL_RE.match(t)
        if m:
            name = m.group(1)
            if name in dims: err(i, "redefined: %s" % name)
            dims[name] = Label(name, reg.id(name)); continue
        m = CAT_RE.match(t)
        if m:
            name, body = m.group(1), m.group(2)
            if name in dims: err(i, "redefined: %s" % name)
            c = Cat(name, reg.id(name))
            for vn in [v.strip() for v in body.split(',')]:
                if re.match(r'^[a-z_]+$', vn): c.vals[vn] = reg.id(vn)
                else: err(i, "malformed value: %r" % vn)
            dims[name] = c; continue
        err(i, "malformed vocabulary line: %r" % t)
    finish_axis(cur)
    return dims, stations, taxdim

# ---------- taxonomy (tree.src) ----------
class Node:
    def __init__(s, name, parent): s.name, s.parent, s.deltas = name, parent, {}   # deltas: axis_name -> val

def load_tree(path, reg, dims, taxdim, auto_tax=None):
    if taxdim is None:
        err(0, "no 'taxonomy' dimension declared in axes.src"); return {}, {}
    nodes, groups = {}, {}   # name->Node ; group_name->(members, line)
    cur = None   # ('class', Node) | ('group', gname, members_list, line)

    def finish(c):
        if c is None: return
        if c[0] == 'class':
            nd = c[1]
            nodes[nd.name] = nd
            reg.id(nd.name)                                # canonical node id
            for al in getattr(nd, 'aliases', []):
                taxdim.vals.setdefault(al, None)           # marker, resolved to canonical id below
        else:  # group
            _, gname, members, gln = c
            groups[gname] = (members, gln)

    for i, raw in enumerate(open(path, encoding="utf-8"), 1):
        t = strip(raw).strip()
        if not t: continue
        first = t.split(None, 1)[0].lower()

        if first == 'class':
            finish(cur); cur = None
            m = CLASS_OPEN_RE.match(t)
            if not m: err(i, "malformed class header: %r" % t); continue
            name, parent = m.group(1), m.group(2)
            if name in nodes: err(i, "node redefined: %s" % name)
            if name in groups: err(i, "name collides with a group: %s" % name)
            cur = ('class', Node(name, parent))
            continue

        if first == 'group':
            finish(cur); cur = None
            m = GROUP_OPEN_RE.match(t)
            if not m: err(i, "malformed group header: %r" % t); continue
            gname = m.group(1)
            if gname in groups or gname in nodes: err(i, "group name collision: %s" % gname)
            cur = ('group', gname, [], i)
            continue

        if first == 'aka':
            if cur is None or cur[0] != 'class': err(i, "'aka' outside a class block"); continue
            m = AKA_RE.match(t)
            if not m: err(i, "malformed aka: %r" % t); continue
            nd = cur[1]
            for al in [a.strip() for a in m.group(1).split(',')]:
                if not re.match(r'^[a-z_]+$', al): err(i, "malformed alias: %r" % al); continue
                nd_aliases = getattr(nd, 'aliases', []); nd_aliases.append(al); nd.aliases = nd_aliases
            continue

        if first == 'axis':
            if cur is None or cur[0] != 'class': err(i, "'axis' outside a class block"); continue
            m = CAXIS_RE.match(t)
            if not m: err(i, "malformed trait: %r" % t); continue
            an, dv = m.group(1), int(m.group(2))
            ax = dims.get(an)
            if not ax or ax.kind != "num": err(i, "delta on unknown axis: %s" % an); continue
            if not (ax.imin <= dv <= ax.imax): err(i, "%s: delta %d out of target [%d..%d]" % (an, dv, ax.imin, ax.imax))
            cur[1].deltas[an] = dv
            continue

        if first == 'inert':
            if cur is None or cur[0] != 'class': err(i, "'inert' outside a class block"); continue
            m = INERT_RE.match(t)
            if not m: err(i, "malformed inert: %r" % t); continue
            an = m.group(1)
            ax = dims.get(an)
            if not ax or ax.kind != "num": err(i, "inert on unknown axis: %s" % an); continue
            nd = cur[1]
            nd_inert = getattr(nd, 'inert', [])
            if an not in nd_inert: nd_inert.append(an)
            nd.inert = nd_inert
            continue

        if first == 'need':
            if cur is None or cur[0] != 'class': err(i, "'need' outside a class block"); continue
            m = NEED_RE.match(t)
            if not m: err(i, "malformed need: %r" % t); continue
            nm2, q = m.group(1), m.group(2)
            nd = cur[1]
            nd_needs = getattr(nd, 'needs', [])
            nd_needs.append((nm2, int(q) if q else 1))
            nd.needs = nd_needs
            continue

        if first == 'member':
            if cur is None or cur[0] != 'group': err(i, "'member' outside a group block"); continue
            m = MEMBER_RE.match(t)
            if not m: err(i, "malformed member: %r" % t); continue
            cur[2].append(m.group(1))
            continue

        err(i, "malformed tree line: %r" % t)
    finish(cur)

    # auto-declare FLAT classes for taxonomy targets of 'set' that weren't defined explicitly
    auto_created = []
    if auto_tax:
        for nm2 in sorted(auto_tax):
            if nm2 in nodes or nm2 in groups or nm2 in taxdim.vals: continue
            nodes[nm2] = Node(nm2, None)
            reg.id(nm2)
            auto_created.append(nm2)

    # groups -> id
    for gname in groups: reg.id(gname)
    # validate parents / cycles / depth, compute ancestry
    def ancestry(name, seen=None):
        seen = seen or []
        if name in seen: err(0, "cycle in the tree: %s" % name); return [name]
        nd = nodes.get(name)
        if not nd: return [name]
        if nd.parent is None: return [name]
        if nd.parent not in nodes: err(nd and 0 or 0, "unknown parent: %s -> %s" % (name, nd.parent)); return [name]
        return [name] + ancestry(nd.parent, seen + [name])
    anc = {}
    for name, nd in nodes.items():
        a = ancestry(name)
        if len(a) > MAX_DEPTH: err(0, "depth > %d: %s" % (MAX_DEPTH, " -> ".join(a)))
        anc[name] = a
    # group membership: a node belongs to G if it or an ancestor is listed in G
    for gname, (members, gln) in groups.items():
        for mb in members:
            if mb not in nodes: err(gln, "group %s: unknown member '%s'" % (gname, mb))
    node_groups = {}
    for name in nodes:
        gs = []
        for gname, (members, _gln) in groups.items():
            if any(a in members for a in anc[name]): gs.append(gname)
        node_groups[name] = gs
    # register taxonomy values (nodes + groups + aliases -> id), alias shares the canonical id
    for name in nodes: taxdim.vals[name] = reg.id(name)
    for gname in groups: taxdim.vals[gname] = reg.id(gname)
    for name, nd in nodes.items():
        for al in getattr(nd, 'aliases', []):
            if al in taxdim.vals and taxdim.vals[al] is not None and taxdim.vals[al] != reg.map.get(name):
                err(0, "alias collision: %s" % al)
            taxdim.vals[al] = reg.id(name)             # alias -> canonical id (no new id)
    # accumulated traits (sum of deltas along the ancestry)
    acc = {}
    for name in nodes:
        tr = {}
        for a in anc[name]:
            for an, dv in nodes[a].deltas.items():
                tr[an] = tr.get(an, 0) + dv
        acc[name] = tr
    # inert axes: a node is inert to an axis if it or an ancestor declares it inert
    inert_acc = {}
    for name in nodes:
        iset = set()
        for a in anc[name]:
            for an in getattr(nodes[a], 'inert', []):
                iset.add(an)
        inert_acc[name] = iset
    # needs: tokens that must be present for a reaction (inherited; child overrides parent qty)
    need_acc = {}
    for name in nodes:
        merged = {}
        for a in reversed(anc[name]):                 # root first, self last -> self overrides
            for (nm2, q) in getattr(nodes[a], 'needs', []):
                merged[nm2] = q
        need_acc[name] = merged
    for name, merged in need_acc.items():
        for nm2 in merged:
            if nm2 not in taxdim.vals or taxdim.vals[nm2] is None:
                err(0, "need on unknown class/group: %s" % nm2)
    return nodes, {"anc": anc, "groups": groups, "node_groups": node_groups, "acc": acc, "inert": inert_acc, "need": need_acc, "auto": auto_created}

# ---------- laws (laws.src) ----------
class Law:
    def __init__(s, ws, lid): s.ws, s.id, s.when, s.when_raw, s.verdict, s.do, s.cap, s.actions_raw = ws, lid, [], [], None, None, None, []

def resolve_cond(dims, cond, ln):
    cond = cond.strip()
    m = COND_IS.match(cond)                                  # <dim> is <band|value>
    if m:
        name, val = m.group(1), m.group(2)
        d = dims.get(name)
        if not d: err(ln, "unknown dimension: %s" % name); return None
        if d.kind == "num":                                  # axis -> zone (emit range term aid~lo~hi)
            if val not in d.zone_int: err(ln, "%s: unknown zone '%s'" % (name, val)); return None
            ilo, ihi = d.zone_int[val]
            return ("%d~%d~%d" % (d.id, ilo, ihi), d.id)
        if d.kind in ("cat", "tax"):                         # cat/taxonomy -> value (token)
            if val not in d.vals or d.vals[val] is None: err(ln, "%s: unknown value '%s'" % (name, val)); return None
            return ("%d=%d" % (d.id, d.vals[val]), d.vals[val])
        err(ln, "%s: 'is' not applicable to this dimension" % name); return None
    m = COND_CMP.match(cond)                                 # <axis> >= <n> | <= <n>
    if m:
        name, op, val = m.group(1), m.group(2), m.group(3)
        d = dims.get(name)
        if not d: err(ln, "unknown dimension: %s" % name); return None
        if d.kind != "num": err(ln, "%s: threshold not allowed (not an axis)" % name); return None
        iv = int(val)
        if not (d.imin <= iv <= d.imax): err(ln, "%s: threshold %d out of target" % (name, iv))
        return ("%d%s%d" % (d.id, op, iv), d.id)
    if COND_EQ.match(cond):                                  # '=' interdit en when -> erreur guidee
        err(ln, "in a 'when', use 'is' not '=' : %r" % cond); return None
    m = COND_PRES.match(cond)                                # <axis> (presence)
    if m:
        name = m.group(1)
        d = dims.get(name)
        if not d: err(ln, "unknown dimension: %s" % name); return None
        return ("%d" % d.id, d.id)
    err(ln, "malformed condition: %r" % cond); return None

def resolve_action(dims, act, ln):
    act = act.strip()
    if act in ("keep", "pass"): return ""                     # readable no-op: reaction without transformation
    if act == "give": return "give"                          # gives the incoming Mesh object
    m = ACT_SET.match(act)                                   # set <dim> = <val>
    if m:
        nm, vn = m.group(1), m.group(2); d = dims.get(nm)
        if not d or d.kind not in ("cat", "tax"): err(ln, "set: unknown categorical dim '%s'" % nm); return None
        if vn not in d.vals or d.vals[vn] is None: err(ln, "set: unknown value '%s' for %s" % (vn, nm)); return None
        return "%d=%d" % (d.id, d.vals[vn])
    m = ACT_SCALE.match(act)                                 # scale <axis>|eff|qty x<f>
    if m:
        tgt, f = m.group(1), m.group(2)
        if tgt == "eff": return "eff*" + f
        if tgt == "qty": return "qty*" + f
        d = dims.get(tgt)
        if not d or d.kind != "num": err(ln, "scale: unknown axis '%s'" % tgt); return None
        return "%d*%s" % (d.id, f)
    m = ACT_ADD.match(act)                                   # add <label>
    if m:
        d = dims.get(m.group(1))
        if not d or d.kind != "label": err(ln, "add: unknown label '%s'" % m.group(1)); return None
        return "+%d" % d.id
    m = ACT_REM.match(act)                                   # remove <label>
    if m:
        d = dims.get(m.group(1))
        if not d or d.kind != "label": err(ln, "remove: unknown label '%s'" % m.group(1)); return None
        return "-%d" % d.id
    err(ln, "unknown action: %r" % act); return None

def load_laws(path, dims, stations):
    laws, ws, cur, do_list, i = [], None, None, [], 0
    def finalize(law, dl, ln):
        if law is None: return
        if law.verdict is None: err(ln, "law %s: no verdict (react/danger)" % law.id)
        law.do = "^".join(dl) if dl else None
        laws.append(law)
    for i, raw in enumerate(open(path, encoding="utf-8"), 1):
        t = strip(raw).strip()
        if not t: continue
        h = HDR_RE.match(t)
        if h:
            finalize(cur, do_list, i); cur = None; do_list = []
            ws = h.group(1)
            if ws not in stations: err(i, "unknown station: @%s" % ws)
            continue
        lm = LAWNAME_RE.match(t)
        if lm:
            finalize(cur, do_list, i); do_list = []
            if ws is None: err(i, "law without @station")
            cur = Law(ws, lm.group(1))
            continue
        if cur is None:
            err(i, "clause outside a law: %r" % t); continue
        parts = t.split(None, 1)
        kw = parts[0].lower()
        rest = parts[1].strip() if len(parts) > 1 else ""
        if kw in ("react", "danger") and rest == "":
            cur.verdict = kw
        elif kw == "when":
            cur.when_raw.append(rest)
            r = resolve_cond(dims, rest, i)
            if r: cur.when.append(r)
        elif kw == "cap":
            try: cur.cap = int(rest)
            except ValueError: err(i, "non-integer cap")
        else:
            cur.actions_raw.append(t)
            a = resolve_action(dims, t, i)
            if a: do_list.append(a)
    finalize(cur, do_list, i)
    return laws

# ---------- emission ----------
def emit(dims, taxdim, nodes, tx, laws, out):
    rows = []
    for d in dims.values():
        rows.append((d.id, d.name))
        if d.kind == "cat":
            for vn, vid in d.vals.items(): rows.append((vid, vn))
    if taxdim:
        for vn, vid in taxdim.vals.items():
            if vid is not None: rows.append((vid, vn))
    seen_id = set()
    for _id, name in sorted(rows):
        if (_id, name) in seen_id: continue
        seen_id.add((_id, name)); out.append("tok:%s = %d" % (name, _id))
    out.append("")
    # INVERSE index id->canonical name (aliases excluded): idToName on the LSL side = O(1) read "tok:#<id>"
    rev = {}
    for d in dims.values():
        rev[d.id] = d.name
        if d.kind == "cat":
            for vn, vid in d.vals.items(): rev[vid] = vn
    if taxdim:
        for nm in nodes: rev[taxdim.vals[nm]] = nm
        for gname in tx["groups"]: rev[taxdim.vals[gname]] = gname
    for _id in sorted(rev):
        out.append("tok:#%d = %s" % (_id, rev[_id]))
    out.append("")
    # taxonomy tables INDEXED BY ID (alias-proof)
    for name in sorted(nodes, key=lambda n: taxdim.vals[n]):
        nid = taxdim.vals[name]
        toks = [nid] + [taxdim.vals[a] for a in tx["anc"][name][1:]] + [taxdim.vals[g] for g in tx["node_groups"][name]]
        out.append("tax:%d:toks = %s" % (nid, "^".join(str(x) for x in toks)))
        tr = tx["acc"][name]
        if tr:
            pairs = "^".join("%d:%d" % (dims[a].id, v) for a, v in sorted(tr.items(), key=lambda kv: dims[kv[0]].id))
            out.append("tax:%d:trait = %s" % (nid, pairs))
        inr = tx["inert"].get(name)
        if inr:
            out.append("tax:%d:inert = %s" % (nid, "^".join("%d" % dims[a].id for a in sorted(inr, key=lambda x: dims[x].id))))
        nd_need = tx["need"].get(name)
        if nd_need:
            pairs = "^".join("%d:%d" % (taxdim.vals[k], v) for k, v in sorted(nd_need.items(), key=lambda kv: taxdim.vals[kv[0]]))
            out.append("tax:%d:need = %s" % (nid, pairs))
    out.append("")
    for seq, law in enumerate(laws):
        k = "law:%s:%s" % (law.ws, law.id)
        out.append("%s:when = %s" % (k, "^".join(c for c, _ in law.when)))
        out.append("%s:verdict = %d" % (k, VERDICTS[law.verdict]))
        out.append("%s:seq = %d" % (k, seq))
        if law.do: out.append("%s:do = %s" % (k, law.do))
        if law.cap is not None: out.append("%s:cap = %d" % (k, law.cap))
    out.append("")
    for law in laws:
        seen = set()
        for _c, tok in law.when:
            if tok in seen: continue
            seen.add(tok); out.append("idx:%s:lawprop:%d:%s =" % (law.ws, tok, law.id))

# two laws can both match the same input? (stages disjoint, or incompatible axis range => NO)
_STAGE_RE = re.compile(r'^meta\.stage\s+is\s+([a-z_]+)$')
_NUM_TERM = re.compile(r'^(\d+)(>=|<=)(-?\d+)$')
def _stages_req(law):
    s = set()
    for w in law.when_raw:
        m = _STAGE_RE.match(w)
        if m: s.add(m.group(1))
    return s
def _num_cons(law):
    cons = {}
    for ts, _tok in law.when:
        m = _NUM_TERM.match(ts)
        if m: cons.setdefault(m.group(1), []).append((m.group(2), int(m.group(3))))
        elif '~' in ts:                                         # zone range aid~lo~hi
            p = ts.split('~')
            cons.setdefault(p[0], []).append(('>=', int(p[1])))
            cons.setdefault(p[0], []).append(('<=', int(p[2])))
    return cons
def _co_satisfiable(a, b):
    sa, sb = _stages_req(a), _stages_req(b)
    if sa and sb and sa.isdisjoint(sb): return False            # different required stages
    ca, cb = _num_cons(a), _num_cons(b)
    for aid in set(ca) & set(cb):
        allc = ca[aid] + cb[aid]
        los = [n for op, n in allc if op == '>=']
        his = [n for op, n in allc if op == '<=']
        if los and his and max(los) > min(his): return False    # empty axis range
    return True
def _cdims(law):                                                # single-valued dims a law constrains
    s = set()
    for w in law.when_raw:
        if _STAGE_RE.match(w): s.add("stage")
    for ts, _tok in law.when:
        m = _NUM_TERM.match(ts)
        if m: s.add("ax:" + m.group(1))
        elif '~' in ts: s.add("ax:" + ts.split('~')[0])
    return s
def _contend(a, b):                                             # same input possible AND dispute a shared axis/stage
    return bool(_cdims(a) & _cdims(b)) and _co_satisfiable(a, b)

# human-readable report: laws per station in resolution order (most when-terms win; seq breaks ties)
def write_law_order(path, laws):
    byst = {}; order = []
    for seq, law in enumerate(laws):
        if law.ws not in byst: byst[law.ws] = []; order.append(law.ws)
        byst[law.ws].append((seq, law))
    lines = ["# Laws in RESOLUTION order — most 'when' terms win; ties broken by source order (seq).",
             "# '<- overlaps X' = same term count, can both match, and dispute a shared axis/stage => seq decides.",
             "# Generated by compiler.py — do not edit.", ""]
    for st in order:
        items = sorted(byst[st], key=lambda it: (-len(it[1].when_raw), it[0]))
        lines.append("@%s" % st)
        for seq, law in items:
            n = len(law.when_raw)
            rivals = [o.id for (sq, o) in items if o is not law and len(o.when_raw) == n and _contend(law, o)]
            mark = "   <- overlaps %s" % ", ".join(rivals) if rivals else ""
            conds = " & ".join(law.when_raw) if law.when_raw else "(always)"
            lines.append("  [%d] %-14s %-6s : %s%s" % (n, law.id, law.verdict, conds, mark))
        lines.append("")
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")

# human-readable report: A) taxonomy tree  B) stage/craft flow from laws
IN_RE  = re.compile(r'^(meta\.stage|meta\.taxonomy)\s+is\s+([a-z_]+)$')
SETO_RE = re.compile(r'^set\s+(meta\.stage|meta\.taxonomy)\s*=\s*([a-z_]+)$')
def write_craft_map(path, nodes, tx, dims, laws):
    L = ["# Craft map — generated by compiler.py on each compile. Do not edit.",
         "#   A) taxonomy (class hierarchy)      B) stage/craft flow (from laws)", "",
         "=== A. TAXONOMY ==="]
    children = {}; roots = []
    for nm, nd in nodes.items():
        if nd.parent is None: roots.append(nm)
        else: children.setdefault(nd.parent, []).append(nm)
    def walk(nm, depth):
        al = getattr(nodes[nm], 'aliases', [])
        L.append("%s%s%s" % ("    " * depth, nm, (" (%s)" % ", ".join(al)) if al else ""))
        for c in sorted(children.get(nm, [])): walk(c, depth + 1)
    for r in sorted(roots): walk(r, 0)
    if tx["groups"]:
        L.append(""); L.append("groups:")
        for g, (members, _ln) in tx["groups"].items():
            L.append("    %s : %s" % (g, ", ".join(members)))
    for d in dims.values():
        if d.kind == "cat":
            L.append(""); L.append("%s values: %s" % (d.name, ", ".join(d.vals.keys())))
    L += ["", "=== B. CRAFT FLOW (stage/taxonomy transitions, by station) ==="]
    byst = {}; order = []
    for law in laws:
        if law.ws not in byst: byst[law.ws] = []; order.append(law.ws)
        byst[law.ws].append(law)
    for st in order:
        L += ["", "@%s" % st]
        for law in byst[st]:
            ins = []; guards = []
            for w in law.when_raw:
                m = IN_RE.match(w)
                if m: ins.append("%s=%s" % (m.group(1).split('.')[1], m.group(2)))
                else: guards.append(w)
            outs = []; give = False
            for a in law.actions_raw:
                m = SETO_RE.match(a)
                if m: outs.append("%s=%s" % (m.group(1).split('.')[1], m.group(2)))
                elif a.strip() == "give": give = True
            inpart = ", ".join(ins) or "(any)"
            outpart = "GIVE (hands object)" if give else (", ".join(outs) if outs else "(in place)")
            g = "   [if %s]" % " & ".join(guards) if guards else ""
            L.append("  %-13s %-32s -> %s%s" % (law.id, inpart, outpart, g))
    open(path, "w", encoding="utf-8").write("\n".join(L) + "\n")

# pre-scan laws.src for 'set <dim> = <val>' targets (products the laws CREATE)
def scan_set_targets(path):
    targets = {}
    for raw in open(path, encoding="utf-8"):
        t = strip(raw).strip()
        m = ACT_SET.match(t)
        if m: targets.setdefault(m.group(1), set()).add(m.group(2))
    return targets

def main():
    ap = sys.argv[1] if len(sys.argv) > 1 else "axes.src"
    tp = sys.argv[2] if len(sys.argv) > 2 else "tree.src"
    lp = sys.argv[3] if len(sys.argv) > 3 else "laws.src"
    lock = os.path.join(os.path.dirname(os.path.abspath(ap)) or ".", "ids.lock")
    reg = IdRegistry(lock)
    set_targets = scan_set_targets(lp)
    dims, stations, taxdim = load_vocab(ap, reg)
    # auto-declare missing cat values that are 'set' targets (e.g. new meta.stage values)
    auto = []
    for dimname, vals in set_targets.items():
        d = dims.get(dimname)
        if d is not None and d.kind == "cat":
            for v in sorted(vals):
                if v not in d.vals: d.vals[v] = reg.id(v); auto.append(dimname + " = " + v)
    auto_tax = set(set_targets.get(taxdim.name, set())) if taxdim is not None else set()
    nodes, tx = load_tree(tp, reg, dims, taxdim, auto_tax)
    auto += [taxdim.name + " = " + n for n in tx.get("auto", [])]
    laws = load_laws(lp, dims, stations)
    if auto:
        sys.stderr.write("NOTE - auto-declared from 'set' targets: %s\n" % ", ".join(sorted(auto)))
    if warnings:
        sys.stderr.write("WARNING:\n  %s\n" % "\n  ".join(warnings))
    if errors:
        sys.stderr.write("REFUSED - %d error(s):\n  %s\n" % (len(errors), "\n  ".join(errors))); sys.exit(1)
    reg.save()
    d_ = os.path.dirname(os.path.abspath(lp)) or "."
    write_law_order(os.path.join(d_, "laws_order.txt"), laws)
    write_craft_map(os.path.join(d_, "craft_map.txt"), nodes, tx, dims, laws)
    out = []
    emit(dims, taxdim, nodes, tx, laws, out)
    sys.stdout.write("\n".join(out) + "\n")

if __name__ == "__main__":
    main()
