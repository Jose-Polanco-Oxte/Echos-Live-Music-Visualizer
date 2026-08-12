#!/usr/bin/env python3
"""translint - catch broken translations before they ship.

Reads a base locale file plus one or more other locale files covering the
same keys and reports what's wrong: keys missing from a translation, keys
left over from a rename, placeholder tokens that don't match between the
base and the translation (the kind of bug that throws a runtime
KeyError/IndexError the first time that string actually renders), empty
values, and values that still look untranslated.

Supports JSON (nested or flat dot-namespaced keys), gettext .po, and Java
.properties files, auto-detected by extension. Standard library only. No
network, no dependencies, no eval/exec on file contents.

Usage:
  translint locales/                         # scan a directory, base=en
  translint locales/ --base fr                # use fr.json as the reference
  translint locales/en.json locales/de.json   # specific files
  translint locales/ --json                   # machine-readable
  translint locales/ --strict                 # also fail on extra/untranslated
  translint locales/ --allow-identical brand.name   # suppress one heuristic hit
  translint locales/ --fix                    # insert MISSING keys only, marked
  translint locales/ --fix --dry-run          # show what --fix would insert
  translint public/locales/ --recursive --locale-from dir   # en/common.json

Exit code is 0 when every locale is clean, 1 when translint found something
to fix, and 2 if a path couldn't be read or parsed at all - so a crash and
a lint finding never look the same to a script.

--fix never guesses at a translation. It only ever inserts a key that's
entirely missing from a locale file, tagged with an unmissable marker
([UNTRANSLATED], or .po's own fuzzy flag) that can't pass for a real
translation - see the "Fix mode" section below for the full scoping.
"""
import argparse
import glob
import json
import os
import re
import sys

__version__ = "0.5.0"

# check_locale()'s return dict is translint's only machine-readable contract.
# If you add, rename, or remove a top-level key, update this set and bump
# the version - anything parsing --json is relying on these names staying put.
# In --json output a .po key that carried a msgctxt is emitted as the string
# "msgctxt\x04msgid" (gettext's own EOT convention), so every key stays a
# string rather than a nested [ctxt, id] array - see _key_json.
JSON_SCHEMA_KEYS = {
    "locale", "path", "format", "missing_keys", "extra_keys",
    "placeholder_mismatches", "empty_values", "untranslated_values",
    "untranslated_markers", "ok",
}

SUPPORTED_FORMATS = ("json", "po", "properties")

EXT_TO_FORMAT = {
    ".json": "json",
    ".po": "po",
    ".pot": "po",
    ".properties": "properties",
}

# ---------------------------------------------------------------------------
# Placeholder detection
#
# Five interpolation styles. A value is scanned with every style; whichever
# styles have at least one match are the ones used, so a project that only
# ever uses `{name}` doesn't get phantom checks run against `%s` syntax it
# never uses. If a value matches more than one style (rare, but plain-text
# next to a templated one happens), tokens from every style that matches are
# unioned - better a token set that's a little too broad than one that
# silently drops a real placeholder.
#
# Two pairs overlap syntactically and need one pattern's matches excluded
# from the other so a single token isn't counted twice:
#   - {{name}} (doublebrace) contains a {name}-shaped substring, which
#     "brace" would otherwise also match on its own.
#   - ${name} (dollar's brace form) ALSO contains that same {name}-shaped
#     substring, for the same reason.
#   - %1$s / %2$d (printf, numbered form) contains a $s / $d substring,
#     which "dollar" would otherwise also match as a bare $name token.
# Each exclusion works the same way: find the wider pattern's spans first,
# then drop any narrower match that falls entirely inside one of them. This
# is why doublebrace/dollar run before brace, and printf runs before dollar.
# ---------------------------------------------------------------------------

_RX_DOUBLEBRACE = re.compile(r"\{\{\s*([\w.]+)\s*\}\}")
_RX_BRACE = re.compile(r"\{([A-Za-z_][\w.]*|\d*)\}")
# Python %(name)s mapping keys, with the full flag/width/precision grammar a
# real format string uses (%(price).2f, %(done)3d), so a conversion isn't
# required to sit right after the ')'. The space flag is safe here because
# the %(name) prefix already pins the match, unlike bare printf below.
_RX_PYNAMED = re.compile(r"%\((\w+)\)[-+0# ]*\d*(?:\.\d+)?[diouxXeEfFgGcrsa]")
# printf: optional %2$-style argument number, then the flag/width/precision
# forms (%-10s, %05d, %.2f), an optional length modifier (%lu, %zd, %ll d),
# then the conversion. The space flag is deliberately left out of the flag
# class: "% off" would otherwise read as a "% o" token, and a space-flagged
# placeholder in a locale string is far rarer than a percent sign followed
# by a word.
#
# The last branch is the bare form (%s, %d) and it's the only one that can
# collide with ordinary prose, so it's the only one guarded: a "%" sitting
# right after a digit and right before a letter, with no flag, width,
# precision or length modifier in between, is a percentage sign. "20%off"
# is a discount, not a "%o" octal conversion, and since placeholder
# mismatches are a hard failure with no allowlist, reading it as one fails
# CI on a perfectly good string. Anything that carries a flag, a width, a
# precision, a length modifier or an argument number still matches wherever
# it appears - "50%2$s" is a real placeholder no matter what precedes it.
_PRINTF_RE = (
    r"(?:"
    r"%(?:\d+\$[-+0#]*\d*(?:\.\d+)?|[-+0#]+\d*(?:\.\d+)?|\d+(?:\.\d+)?|\.\d+)"
    r"(?:hh|h|ll|l|q|j|z|t|L)?[sdiufgeExXoc]"
    r"|%(?:hh|h|ll|l|q|j|z|t|L)[sdiufgeExXoc]"
    r"|(?<![0-9])%[sdiufgeExXoc]"
    r")"
)
_RX_PRINTF = re.compile(_PRINTF_RE)
# Bare $name requires a letter/underscore start: "$5" is money, not a
# placeholder, and currency reordering ("5 $" in French typography) must
# not read as a placeholder mismatch.
_RX_DOLLAR = re.compile(r"\$\{(\w+)\}|\$([A-Za-z_]\w*)")


def _spans_contain(spans, m):
    return any(s <= m.start() and m.end() <= e for s, e in spans)


# ---------------------------------------------------------------------------
# ICU MessageFormat plural/select/selectordinal arguments
#
# `{count, plural, one {file} other {files}}` is a single placeholder whose
# argument is `count` - the branch bodies (file/files) are ordinary prose to
# be translated, not placeholders. The flat brace regex above would otherwise
# read every `{file}`/`{files}` branch as its own token, so a correct French
# translation ({fichier}/{fichiers}) looks like a placeholder mismatch, and
# the identical structural keywords make it look untranslated too. The
# scanner below pulls out just the argument name and hands the branch bodies
# back for recursion, so nested placeholders inside a branch still count.
# ---------------------------------------------------------------------------

_RX_ICU_HEAD = re.compile(r"^\s*([A-Za-z_]\w*)\s*,\s*(?:plural|selectordinal|select)\s*,")


def _match_brace(s, i):
    """Index of the '}' that closes the '{' at s[i], or -1 if unbalanced."""
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                return j
    return -1


def _icu_branch_bodies(style):
    """The submessage bodies from an ICU plural/select style part - the text
    inside each `key {body}` group, with the branch keys (one/other/=0)
    dropped since they're syntax keywords, not translatable content."""
    bodies = []
    i = 0
    while i < len(style):
        if style[i] == "{":
            j = _match_brace(style, i)
            if j == -1:
                break
            bodies.append(style[i + 1:j])
            i = j + 1
        else:
            i += 1
    return bodies


def _icu_scan(value):
    """Find top-level ICU plural/select/selectordinal arguments in value.
    Returns (tokens, spans, bodies): the `{argname}` token for each one, the
    full span of each argument block (so the flat regexes skip it), and every
    branch submessage string (so the caller can recurse for nested
    placeholders). Simple `{name}` arguments are left to the flat brace regex."""
    tokens, spans, bodies = [], [], []
    i = 0
    while i < len(value):
        if value[i] == "{":
            j = _match_brace(value, i)
            if j != -1:
                inner = value[i + 1:j]
                m = _RX_ICU_HEAD.match(inner)
                if m:
                    tokens.append(f"{{{m.group(1)}}}")
                    spans.append((i, j + 1))
                    bodies.extend(_icu_branch_bodies(inner[m.end():]))
                    i = j + 1
                    continue
        i += 1
    return tokens, spans, bodies


def _strip_icu_structure(value):
    """Rewrite value with ICU plural/select scaffolding removed but branch
    body prose kept, for the untranslated-value heuristic - a correctly
    translated branch then differs from the base, while an untranslated copy
    still matches."""
    out = []
    i = 0
    while i < len(value):
        if value[i] == "{":
            j = _match_brace(value, i)
            if j != -1:
                inner = value[i + 1:j]
                m = _RX_ICU_HEAD.match(inner)
                if m:
                    for body in _icu_branch_bodies(inner[m.end():]):
                        out.append(_strip_icu_structure(body))
                        out.append(" ")
                    i = j + 1
                    continue
        out.append(value[i])
        i += 1
    return "".join(out)


def extract_placeholders(value):
    """Return (style_name, multiset-as-sorted-tuple) for the interpolation
    style(s) found in value. A value can use more than one style at once
    (uncommon, but not invalid), in which case every token from every style
    that matched is included in one combined multiset and style_name is a
    "+"-joined label of every style that fired, so the caller has one
    consistent set to diff regardless of how many styles were in play.

    Returns ("none", ()) when no placeholder syntax is present at all -
    the overwhelmingly common case for short UI strings, and correctly not
    flagged as a mismatch against another value that also has none.
    """
    tokens = []
    styles_hit = []

    # ICU plural/select args first: take the argument name as the token,
    # exclude the whole block from the flat regexes below (so branch-body
    # braces aren't read as their own placeholders), and recurse into each
    # branch to pick up any nested placeholder.
    icu_tokens, icu_spans, icu_bodies = _icu_scan(value)
    if icu_tokens:
        tokens += icu_tokens
        styles_hit.append("icu")
        for body in icu_bodies:
            _, sub_tokens = extract_placeholders(body)
            tokens += list(sub_tokens)

    doublebrace_matches = [m for m in _RX_DOUBLEBRACE.finditer(value)
                            if not _spans_contain(icu_spans, m)]
    if doublebrace_matches:
        tokens += [f"{{{{{m.group(1)}}}}}" for m in doublebrace_matches]
        styles_hit.append("doublebrace")

    pynamed_matches = [m for m in _RX_PYNAMED.finditer(value)
                        if not _spans_contain(icu_spans, m)]
    if pynamed_matches:
        tokens += [m.group(0) for m in pynamed_matches]
        styles_hit.append("pynamed")

    printf_matches = [m for m in _RX_PRINTF.finditer(value)
                       if not _spans_contain(icu_spans, m)]
    if printf_matches:
        tokens += [m.group(0) for m in printf_matches]
        styles_hit.append("printf")
    printf_spans = [m.span() for m in printf_matches]

    dollar_matches = [m for m in _RX_DOLLAR.finditer(value)
                       if not _spans_contain(printf_spans, m)
                       and not _spans_contain(icu_spans, m)]
    if dollar_matches:
        tokens += [m.group(0) for m in dollar_matches]
        styles_hit.append("dollar")

    exclude_spans = ([m.span() for m in doublebrace_matches]
                     + [m.span() for m in dollar_matches] + icu_spans)
    brace_matches = [m for m in _RX_BRACE.finditer(value)
                      if not _spans_contain(exclude_spans, m)]
    if brace_matches:
        tokens += [f"{{{m.group(1)}}}" for m in brace_matches]
        styles_hit.append("brace")

    if not tokens:
        return "none", ()
    return "+".join(styles_hit), tuple(sorted(tokens))


_RX_PRINTF_ARGNUM = re.compile(r"^%\d+\$")


def _strip_printf_argnums(tokens):
    """Rewrite numbered printf tokens (%2$s) to their bare form (%s) and
    return the result sorted. gettext explicitly allows a translation to
    reorder a bare-form base's arguments by switching to the numbered form
    (msgfmt -c accepts it), so %s/%d against %2$d/%1$s is the same argument
    list spelled two ways. Comparing with the numbers stripped treats those
    as equal while a changed or missing conversion still shows up."""
    return sorted(_RX_PRINTF_ARGNUM.sub("%", t) for t in tokens)


def _bare_printf_conversions(value):
    """Ordered list of BARE (unnumbered) printf conversion characters in
    value, left to right - "%s got %d" -> ['s', 'd']. Numbered tokens
    (%1$s) are excluded: their position is pinned by the number rather
    than by where they sit in the string, so reordering those is safe (see
    _strip_printf_argnums) in a way reordering bare conversions is not -
    "%s %d" applied to a (name, age) tuple crashes if a translation flips
    it to "%d %s" without also flipping the values, even though {%s, %d}
    is the same multiset either way."""
    out = []
    for m in _RX_PRINTF.finditer(value):
        token = m.group(0)
        if not _RX_PRINTF_ARGNUM.match(token):
            out.append(token[-1])
    return out


def _placeholder_mismatch(base_val, base_tokens, loc_val, loc_tokens):
    """True if the translation's placeholders don't actually match the
    base's. Two distinct ways that happens:
      - a different token multiset (missing/extra/wrong-numbered
        placeholder), checked ignoring order and, for printf, ignoring
        %N$ argument numbers;
      - the SAME multiset of bare printf conversions in a different
        order (%s/%d swapped to %d/%s) - invisible to the multiset check
        above, but a real runtime crash once the translation is formatted
        against the base's argument tuple.
    """
    if sorted(base_tokens) != sorted(loc_tokens):
        return _strip_printf_argnums(base_tokens) != _strip_printf_argnums(loc_tokens)
    return _bare_printf_conversions(base_val) != _bare_printf_conversions(loc_val)


# ---------------------------------------------------------------------------
# Format parsers. Each returns a flat dict of {dotted.key: string value},
# already flattened for nested formats, plus the raw key order isn't
# preserved (dict order is, which is good enough - comparisons are by key,
# not position).
# ---------------------------------------------------------------------------


def flatten_json(obj, prefix=""):
    """Flatten a nested JSON object into dot-namespaced keys. A flat file
    that's already dot-namespaced round-trips unchanged. Lists are treated
    as leaf values (joined by index: key.0, key.1, ...) rather than
    unsupported, since locale files occasionally use arrays for things like
    ordinal-plural forms and dropping them silently would hide real content."""
    out = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            key = f"{prefix}.{k}" if prefix else str(k)
            out.update(flatten_json(v, key))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            key = f"{prefix}.{i}" if prefix else str(i)
            out.update(flatten_json(v, key))
    else:
        out[prefix] = "" if obj is None else str(obj)
    return out


def parse_json(text, path):
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path}: invalid JSON ({exc})")
    if not isinstance(data, dict):
        raise ValueError(f"{path}: top level must be a JSON object")
    return flatten_json(data)


def _properties_line_continues(line):
    """True when `line` ends in an odd number of backslashes: the last one
    is then unpaired, i.e. the java.util.Properties continuation marker.
    An even count is just escaped literal backslashes, no continuation."""
    trailing = len(line) - len(line.rstrip("\\"))
    return trailing % 2 == 1


_RX_PROPERTIES_ESCAPE = re.compile(r"\\(u[0-9a-fA-F]{4}|.)")
_PROPERTIES_CONTROL_ESCAPES = {"t": "\t", "n": "\n", "r": "\r", "f": "\f"}


def _properties_unescape(s):
    """Decode java.util.Properties escapes the way Properties.load does:
    \\uXXXX becomes its character (the native2ascii convention older Java
    bundles still ship with - without this, é reads back as the literal
    string u00e9), \\t/\\n/\\r/\\f become the control character, and any
    other \\x becomes a literal x - which doubles as the quiet fallback
    for a malformed \\u escape."""
    def repl(m):
        esc = m.group(1)
        if len(esc) == 5 and esc[0] == "u":
            return chr(int(esc[1:], 16))
        return _PROPERTIES_CONTROL_ESCAPES.get(esc, esc)
    return _RX_PROPERTIES_ESCAPE.sub(repl, s)


def parse_properties(text, path):
    """Java .properties: key=value, key:value, or key value (bare
    whitespace, no punctuation at all - java.util.Properties.load()
    accepts this too), one per logical line. A trailing unescaped
    backslash continues the value onto the next line (the standard
    .properties continuation rule). '#' and '!' start a comment when
    they're the first non-whitespace character on a line. Leading
    whitespace on a continuation line is stripped, matching how
    java.util.Properties reads it."""
    out = {}
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.lstrip()
        if not stripped or stripped[0] in "#!":
            i += 1
            continue
        # Gather continuation lines first, since the split point between
        # key and value must not be searched for inside an escaped
        # separator (\\= or \\:), and continuations can carry those too.
        full = line
        while _properties_line_continues(full):
            i += 1
            if i >= len(lines):
                break
            full = full[:-1] + lines[i].lstrip()
        # separator is =/: (optionally whitespace-padded) if one is present,
        # else a bare run of whitespace - "key value" is as valid as
        # "key=value". Try the =/: form first so a value that itself starts
        # with a word character right after whitespace-padded punctuation
        # (e.g. "key = value") isn't mis-split on the whitespace alone.
        m = re.match(r"\s*((?:[^\\=: \t]|\\.)+)(?:\s*[=:]\s*|[ \t]+)(.*)$", full)
        if m:
            key = _properties_unescape(m.group(1).strip())
            value = _properties_unescape(m.group(2))
        else:
            # A bare key with no separator and no value ("flag.beta" on its
            # own line) is valid java.util.Properties syntax for a key with
            # an empty value - record it as such so it lands in empty_values,
            # not dropped and then mis-reported as a missing key.
            bare = re.match(r"\s*((?:[^\\=: \t]|\\.)+)\s*$", full)
            if not bare:
                i += 1
                continue
            key = _properties_unescape(bare.group(1).strip())
            value = ""
        out[key] = value
        i += 1
    return out


def parse_po(text, path):
    """gettext .po: msgid/msgstr pairs. Multi-line strings (adjacent quoted
    literals) are concatenated. Plural forms (msgid_plural/msgstr[n]) use
    msgstr[0] as the value to check, since that's the form that corresponds
    to msgid the same way a singular translation would - msgstr[1..] are
    the plural variants and aren't compared against msgid directly. Entries
    with an empty msgid (the .po header block) are skipped. Fuzzy (#, fuzzy)
    and obsolete (#~) entries are skipped since they aren't live
    translations - msgfmt doesn't compile either.

    An entry carrying msgctxt is keyed by (msgctxt, msgid) instead of the
    bare msgid, so two context-disambiguated entries sharing one msgid
    (a "Close" verb vs a "Close" adjective) don't collide - without this,
    the second parsed entry silently overwrites the first."""
    out = {}

    def is_fuzzy_flag(line):
        # "#," starts gettext's flag comment; fuzzy has to be one of the
        # comma-separated flags there. The word "fuzzy" inside a translator
        # comment (plain "#") or a flag like "c-format" must not match.
        return line.startswith("#,") and "fuzzy" in [f.strip() for f in line[2:].split(",")]

    def unquote(raw):
        # .po string literals use C-style escapes inside double quotes;
        # json.loads handles that escaping correctly without reimplementing
        # it, since .po's rules are the same subset json uses.
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return raw

    def starts_new_entry(line):
        # A fresh msgctxt/msgid (not msgid_plural, which belongs to the same
        # entry) marks a new entry; so does the comment block gettext writes
        # ahead of one. Both only count once the current entry already has a
        # msgstr - that's what tells them apart from the same entry's own
        # header lines.
        if line.startswith("msgctxt"):
            return True
        if line.startswith("msgid") and not line.startswith("msgid_plural"):
            return True
        return line.startswith("#")

    entry_lines = []
    entries = []
    has_msgstr = False
    for raw_line in text.splitlines() + [""]:
        line = raw_line.strip()
        if line == "":
            if entry_lines:
                entries.append(entry_lines)
                entry_lines = []
                has_msgstr = False
            continue
        # gettext also delimits entries structurally, not only with blank
        # lines: a new msgctxt/msgid (or the comment block before it) after
        # this entry's msgstr starts the next one, so a file whose entries
        # aren't blank-separated (msgfmt still accepts it) doesn't merge into
        # one garbage key.
        if entry_lines and has_msgstr and starts_new_entry(line):
            entries.append(entry_lines)
            entry_lines = []
            has_msgstr = False
        entry_lines.append(line)
        if line.startswith("msgstr"):
            has_msgstr = True
    if entry_lines:
        entries.append(entry_lines)

    for entry in entries:
        if any(line.startswith("#~") for line in entry):
            continue
        if any(is_fuzzy_flag(line) for line in entry):
            continue
        msgid_parts, msgstr_parts, msgctxt_parts = [], [], []
        target = None
        for line in entry:
            if line.startswith("#"):
                continue
            if line.startswith("msgid_plural"):
                target = None
                continue
            if line.startswith("msgctxt "):
                target = msgctxt_parts
                msgctxt_parts.append(line[len("msgctxt "):].strip())
                continue
            if line.startswith("msgctxt"):
                target = msgctxt_parts
                continue
            if line.startswith("msgid "):
                target = msgid_parts
                msgid_parts.append(line[len("msgid "):].strip())
                continue
            if line.startswith("msgid"):
                target = msgid_parts
                continue
            if re.match(r'^msgstr\[0\]', line):
                target = msgstr_parts
                rest = re.sub(r'^msgstr\[0\]\s*', '', line)
                msgstr_parts.append(rest)
                continue
            if re.match(r'^msgstr\[\d+\]', line):
                target = None  # msgstr[1..]: plural variants, not compared
                continue
            if line.startswith("msgstr "):
                target = msgstr_parts
                msgstr_parts.append(line[len("msgstr "):].strip())
                continue
            if line.startswith("msgstr"):
                target = msgstr_parts
                continue
            if line.startswith('"') and target is not None:
                target.append(line)
        msgid = "".join(unquote(p) for p in msgid_parts)
        msgstr = "".join(unquote(p) for p in msgstr_parts)
        msgctxt = "".join(unquote(p) for p in msgctxt_parts)
        if msgid == "":
            continue  # header block
        key = (msgctxt, msgid) if msgctxt else msgid
        out[key] = msgstr
    return out


PARSERS = {"json": parse_json, "po": parse_po, "properties": parse_properties}


def detect_format(path):
    ext = os.path.splitext(path)[1].lower()
    return EXT_TO_FORMAT.get(ext)


# java.util.Properties.load(InputStream) is ISO-8859-1 by specification, and
# pre-Java-9 resource bundles written that way are still in service. Reading
# one as UTF-8 turns every accented byte into U+FFFD, which makes two
# genuinely different words compare equal and reports a correct translation
# as "possibly untranslated" - on top of printing an unreadable report.
PROPERTIES_LEGACY_ENCODING = "iso-8859-1"


def _warn(message):
    print(message, file=sys.stderr)


def decode_locale_bytes(raw, path, fmt, encoding=None, warn=_warn):
    """Decode a locale file's bytes to text, saying out loud when the
    decode wasn't clean. A silent U+FFFD substitution reads downstream as
    real content, so every degraded path here prints what it did and why.

    With no --encoding: UTF-8 (BOM tolerated), then for .properties a
    fall back to ISO-8859-1, which is what the format actually specifies."""
    if encoding:
        try:
            return raw.decode(encoding), encoding
        except LookupError:
            raise ValueError(f"{path}: unknown encoding '{encoding}'")
        except UnicodeDecodeError:
            warn(f"translint: {path}: not valid {encoding}, unreadable bytes "
                 f"replaced with U+FFFD - findings on this file may be wrong")
            return raw.decode(encoding, errors="replace"), encoding
    try:
        return raw.decode("utf-8-sig"), "utf-8"
    except UnicodeDecodeError:
        pass
    if fmt == "properties":
        warn(f"translint: {path}: not valid UTF-8, read as {PROPERTIES_LEGACY_ENCODING} "
             f"(java.util.Properties' own encoding) - pass --encoding to override")
        return raw.decode(PROPERTIES_LEGACY_ENCODING), PROPERTIES_LEGACY_ENCODING
    warn(f"translint: {path}: not valid UTF-8, unreadable bytes replaced with U+FFFD "
         f"- findings on this file may be wrong, pass --encoding to name its encoding")
    return raw.decode("utf-8-sig", errors="replace"), "utf-8"


def load_locale(path, fmt=None, encoding=None):
    """Read and parse a locale file. fmt overrides extension-based
    detection, encoding overrides the decode. Raises ValueError with a
    plain message (no traceback) on an unrecognized extension, an unknown
    encoding, or a parse failure, so main() can report it and exit 2
    instead of crashing."""
    fmt = fmt or detect_format(path)
    if fmt not in PARSERS:
        raise ValueError(
            f"{path}: can't detect format from extension, pass --format "
            f"({'/'.join(SUPPORTED_FORMATS)})"
        )
    with open(path, "rb") as fh:
        raw = fh.read()
    text, _enc = decode_locale_bytes(raw, path, fmt, encoding=encoding)
    return PARSERS[fmt](text, path), fmt


# ---------------------------------------------------------------------------
# The untranslated-value heuristic
# ---------------------------------------------------------------------------

# Stripped out of both the base and translation values before the
# "identical to base" untranslated check runs, so a value that legitimately
# still contains a placeholder, a number, or ordinary punctuation doesn't
# make an otherwise-translated string register as a false match, and so a
# short value that's ALL punctuation/placeholder (and therefore has no real
# prose to translate in the first place) doesn't get flagged at all - see
# the ">= 3 letters of remaining content" guard in find_untranslated below.
# The printf alternative is _PRINTF_RE itself, not a second copy of it: when
# the two drifted apart, a string the placeholder engine read one way got
# stripped the other way here, and the untranslated heuristic disagreed with
# the placeholder check on the same value.
_STRIP_PLACEHOLDER_RX = re.compile(
    r"\{\{[\w.]+\}\}|\{[\w.]*\}|%\(\w+\)[-+0# ]*\d*(?:\.\d+)?[diouxXeEfFgGcrsa]|"
    + _PRINTF_RE + r"|"
    r"\$\{[\w]+\}|\$[A-Za-z_]\w*"
)
_STRIP_PUNCT_RX = re.compile(r"[0-9%.,()/\-+×~\"'`:;!?\s]")


def _strip_for_untranslated_check(value, do_not_translate):
    out = value
    for tok in do_not_translate:
        out = out.replace(tok, "")
    out = _strip_icu_structure(out)
    out = _STRIP_PLACEHOLDER_RX.sub("", out)
    out = _STRIP_PUNCT_RX.sub("", out)
    return out


def _letter_count(s):
    return sum(1 for ch in s if ch.isalpha())


# ---------------------------------------------------------------------------
# Core check
# ---------------------------------------------------------------------------


def _key_sort(key):
    """Sort key for a locale dict key, which is a bare msgid string for
    every format except .po entries that used msgctxt, where parse_po
    keys by a (msgctxt, msgid) tuple instead (see parse_po). A single .po
    file commonly has both shapes at once - msgctxt only on the handful of
    entries that need disambiguating - and Python refuses to compare a
    str to a tuple directly, so plain keys are wrapped to a 1-tuple here."""
    return key if isinstance(key, tuple) else (key,)


def check_locale(base, locale_dict, locale_name, path, fmt,
                  do_not_translate=None, allow_identical=None):
    """Compare one locale's flat {key: value} dict against the base's.
    Returns a result dict matching JSON_SCHEMA_KEYS. Pure function - no I/O,
    so it's the same entry point the CLI and any importer (agent skill,
    another script) both call.

    do_not_translate: substrings stripped before the untranslated-value
    heuristic runs (brand names, program names, unit symbols - the same
    idea as liftmath's DO_NOT_TRANSLATE list).
    allow_identical: key names exempt from the untranslated-value heuristic
    entirely (liftmath's IDENTICAL_BY_DESIGN) - for values that legitimately
    render the same in every language (a brand name split across markup,
    a cross-language cognate, a deliberate loanword).
    """
    do_not_translate = do_not_translate or []
    allow_identical = set(allow_identical or [])

    base_keys = set(base.keys())
    locale_keys = set(locale_dict.keys())

    missing_keys = sorted(base_keys - locale_keys, key=_key_sort)
    extra_keys = sorted(locale_keys - base_keys, key=_key_sort)

    placeholder_mismatches = []
    empty_values = []
    untranslated_values = []
    untranslated_markers = []

    for key in sorted(base_keys & locale_keys, key=_key_sort):
        base_val = base[key]
        loc_val = locale_dict[key]

        if loc_val.strip().startswith(UNTRANSLATED_MARKER):
            # A key --fix inserted and nobody has translated yet. It exists in
            # the file, so it isn't "missing," but the marker means it's not a
            # real translation either - report it as its own hard finding so a
            # --fix run followed by a plain run doesn't read as clean, exactly
            # as the README's Fix mode section promises. (.po uses the fuzzy
            # flag instead, which the parser already drops, so those show up
            # as missing rather than here.)
            untranslated_markers.append(key)
            continue

        if base_val.strip() and not loc_val.strip():
            # Report this as "empty," not also as a placeholder mismatch -
            # an empty value trivially has no tokens, so it would always
            # register as a mismatch too, and that's a less useful, more
            # confusing way to say the same single thing: translate it.
            empty_values.append(key)
            continue

        _, base_tokens = extract_placeholders(base_val)
        _, loc_tokens = extract_placeholders(loc_val)
        if _placeholder_mismatch(base_val, base_tokens, loc_val, loc_tokens):
            placeholder_mismatches.append({
                "key": key,
                "base": sorted(base_tokens),
                "locale": sorted(loc_tokens),
            })

        if key in allow_identical:
            continue
        base_stripped = _strip_for_untranslated_check(base_val, do_not_translate)
        loc_stripped = _strip_for_untranslated_check(loc_val, do_not_translate)
        if _letter_count(base_stripped) >= 3 and base_stripped == loc_stripped:
            untranslated_values.append(key)

    ok = not (missing_keys or placeholder_mismatches or empty_values
              or untranslated_markers)

    return {
        "locale": locale_name,
        "path": path,
        "format": fmt,
        "missing_keys": missing_keys,
        "extra_keys": extra_keys,
        "placeholder_mismatches": placeholder_mismatches,
        "empty_values": empty_values,
        "untranslated_values": untranslated_values,
        "untranslated_markers": untranslated_markers,
        "ok": ok,
    }


def is_failing(result, strict=False):
    """Whether a single locale's result should make the run exit non-zero.
    Missing keys, placeholder mismatches, empty values, and leftover
    [UNTRANSLATED] markers always fail. Extra keys and untranslated values
    (a heuristic) only fail under --strict, since they're much more likely to
    have a legitimate reason behind them (a value someone intentionally left
    alone, a key mid-removal)."""
    hard = bool(result["missing_keys"] or result["placeholder_mismatches"]
                or result["empty_values"] or result["untranslated_markers"])
    if not strict:
        return hard
    return hard or bool(result["extra_keys"] or result["untranslated_values"])


# ---------------------------------------------------------------------------
# Discovery + reporting
# ---------------------------------------------------------------------------


def discover_locale_files(paths, recursive=False, forced_fmt=None):
    """Given a list of files and/or directories, return a sorted list of
    (path, root) pairs - the locale file, and the directory argument it was
    found under. The root is what --locale-from dir measures a path against,
    and it's the file's own directory for a file passed explicitly.

    A directory expands to every file in it with a recognized extension.
    That's non-recursive by default: locale directories are conventionally
    flat, and recursing by default risks pulling in unrelated JSON. Pass
    recursive=True for the locales/<lang>/<namespace>.json layout, where the
    files are one level down.

    forced_fmt is --format. Extension-based filtering is the only reason a
    directory scan would skip a real locale file, so forcing a format drops
    the filter and takes every regular file instead - otherwise --format,
    documented as the escape hatch for a non-standard extension, worked for
    explicitly listed files and silently found nothing for a directory.

    A file passed explicitly (not discovered via a directory) is always
    included as given, even if its name would otherwise be excluded below -
    only directory-scan discovery applies the dotfile filter. Dotfiles
    (.translintrc.json and friends) are skipped during discovery so a config
    file sitting next to the locale files it configures doesn't get treated
    as a locale itself just because it shares the extension."""
    out = []
    for p in paths:
        if os.path.isdir(p):
            # normpath so a directory argument given with forward slashes
            # (common even on Windows, and the norm in cross-platform docs)
            # doesn't produce a display path that mixes separators once
            # joined with a filename below.
            base_dir = os.path.normpath(p)
            for dirpath, dirnames, filenames in os.walk(base_dir):
                dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
                for name in sorted(filenames):
                    if name.startswith("."):
                        continue
                    full = os.path.join(dirpath, name)
                    if not os.path.isfile(full):
                        continue
                    if forced_fmt or detect_format(full):
                        out.append((full, base_dir))
                if not recursive:
                    dirnames[:] = []
        else:
            out.append((p, os.path.dirname(p) or "."))
    return out


def locale_name_from_path(path):
    return os.path.splitext(os.path.basename(path))[0]


def locale_and_namespace(path, root, locale_from="stem"):
    """Split a discovered file into (locale, namespace).

    With locale_from="stem" the locale is the filename stem, the way
    en.json / de.json directories work, and every file is in one unnamed
    namespace so they all get compared against one base.

    With locale_from="dir" the locale is the first directory below the
    scanned root - the next-i18next / i18next-fs-backend layout,
    public/locales/en/common.json - and the namespace is the rest of the
    path with the extension dropped. Grouping by that namespace is what
    keeps en/common.json compared against de/common.json and never against
    de/footer.json."""
    if locale_from != "dir":
        return locale_name_from_path(path), ""
    rel = os.path.relpath(path, root)
    parts = rel.split(os.sep)
    if len(parts) < 2:
        # an explicitly listed file: its own parent directory names the
        # locale, so translint pub/en/common.json pub/de/common.json works
        # the same way the directory scan does
        return os.path.basename(os.path.dirname(os.path.abspath(path))), \
            locale_name_from_path(path)
    namespace = "/".join(parts[1:])
    return parts[0], os.path.splitext(namespace)[0]


def report(results):
    lines = []
    any_issues = False
    for r in results:
        issues = (bool(r["missing_keys"]) + bool(r["extra_keys"])
                  + bool(r["placeholder_mismatches"]) + bool(r["empty_values"])
                  + bool(r["untranslated_values"]) + bool(r["untranslated_markers"]))
        if issues == 0:
            lines.append(f"{r['locale']} ({r['path']}): clean")
            continue
        any_issues = True
        lines.append(f"{r['locale']} ({r['path']}):")
        if r["missing_keys"]:
            lines.append(f"  missing keys ({len(r['missing_keys'])}):")
            for k in r["missing_keys"]:
                lines.append(f"    - {_key_display(k)}")
        if r["extra_keys"]:
            lines.append(f"  extra keys ({len(r['extra_keys'])}):")
            for k in r["extra_keys"]:
                lines.append(f"    - {_key_display(k)}")
        if r["placeholder_mismatches"]:
            lines.append(f"  placeholder mismatches ({len(r['placeholder_mismatches'])}):")
            for m in r["placeholder_mismatches"]:
                lines.append(f"    - {_key_display(m['key'])}: base has {m['base']}, "
                              f"locale has {m['locale']}")
        if r["empty_values"]:
            lines.append(f"  empty values ({len(r['empty_values'])}):")
            for k in r["empty_values"]:
                lines.append(f"    - {_key_display(k)}")
        if r["untranslated_markers"]:
            lines.append(f"  untranslated markers ({len(r['untranslated_markers'])}):")
            for k in r["untranslated_markers"]:
                lines.append(f"    - {_key_display(k)}")
        if r["untranslated_values"]:
            lines.append(f"  possibly untranslated ({len(r['untranslated_values'])}, heuristic):")
            for k in r["untranslated_values"]:
                lines.append(f"    - {_key_display(k)}")
        lines.append("")
    if not any_issues:
        lines.append("")
        lines.append("All locales clean.")
    return "\n".join(lines).rstrip("\n") + "\n"


# ---------------------------------------------------------------------------
# --fix: insert missing keys, and only missing keys
#
# The whole safety model in one sentence: --fix only ever ADDS a key that's
# entirely absent from a locale file, and it marks what it adds so loudly
# that it can never pass for a finished translation. It never touches a key
# that already exists - not to "fix" a placeholder mismatch, not to fill in
# an empty value, and never the identical-to-base heuristic, which stays
# report-only, permanently (see check_locale's docstring). Silently writing
# the base-language string in as if it were translated would make the exact
# problem translint exists to catch invisible instead of caught, which is
# why there's no code path here that ever does that.
#
# JSON/.properties get an explicit [UNTRANSLATED] text marker. .po gets the
# format's own fuzzy flag instead of a text marker, since parse_po already
# treats a fuzzy entry as not a live translation (its own docstring says
# msgfmt doesn't compile them either) - a freshly-inserted fuzzy entry
# reads back as still-missing on the next run, the same outcome the bracket
# marker produces for the other two formats, without inventing a second,
# redundant tag.
#
# Every inserter below only ever appends new text - never rewrites, moves,
# or reformats an existing line - so the round-trip diff is exactly the new
# key(s) and nothing else, regardless of how the rest of the file is styled.
# ---------------------------------------------------------------------------

UNTRANSLATED_MARKER = "[UNTRANSLATED]"


def _untranslated_value(base_value):
    """The value --fix writes for a newly-inserted key: the marker, plus
    the base string itself so a translator has the exact source text and
    placeholders to start from without reopening the base file. Never just
    the base string alone - that's the silent-fake-translation failure
    mode this whole feature exists to avoid."""
    if not base_value:
        return UNTRANSLATED_MARKER
    return f"{UNTRANSLATED_MARKER} {base_value}"


def _json_detect_indent(text):
    """Sniff the indent unit from this file's own first indented key line
    rather than assuming one - reformatting every existing line to a
    guessed width is exactly the "bad fix" the whole feature has to avoid.
    Falls back to two spaces (what every fixture and example in this repo
    already uses) for a single-line file with no indented line to sniff."""
    for line in text.splitlines()[1:]:
        stripped = line.lstrip(" \t")
        if stripped.startswith('"'):
            return line[:len(line) - len(stripped)]
    return "  "


def _json_object_extents(text):
    """Map each JSON object in `text` to the (open, close) index of its own
    braces, keyed by the tuple of member names that reaches it - () for the
    root object. Lets --fix splice a new member into one exact spot without
    reserializing (and therefore reformatting) anything else.

    Only objects reached through objects get a path; anything inside an
    array is tracked for brace balance and then dropped, since a key path
    never descends into one. `text` is assumed to be JSON that already
    parsed - parse_json ran on this same file during the check pass."""
    extents = {}
    stack = []          # (parent_path, open_idx, is_object, own_path)
    cur_path = ()
    pending_key = None
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    break
                j += 1
            k = j + 1
            while k < n and text[k] in " \t\r\n":
                k += 1
            if k < n and text[k] == ":":
                try:
                    pending_key = json.loads(text[i:j + 1])
                except ValueError:
                    pending_key = None
            i = j + 1
            continue
        if ch in "{[":
            if not stack:
                own = ()
            elif stack[-1][2] and cur_path is not None and pending_key is not None:
                own = cur_path + (pending_key,)
            else:
                own = None
            stack.append((cur_path, i, ch == "{", own))
            cur_path = own
            pending_key = None
        elif ch in "}]" and stack:
            parent, open_idx, is_object, own = stack.pop()
            if is_object and own is not None:
                extents[own] = (open_idx, i)
            cur_path = parent
            pending_key = None
        i += 1
    return extents


def _json_member_indent(text, open_idx, close_idx, fallback):
    """The indent of the given object's own member lines, sniffed from the
    file rather than assumed, so an inserted member lines up with the ones
    already there whatever the file's style is."""
    for line in text[open_idx:close_idx].split("\n")[1:]:
        stripped = line.lstrip(" \t")
        if stripped.startswith('"'):
            return line[:len(line) - len(stripped)]
    return fallback


def _json_layout(data, base_nested):
    """Whether this file writes its keys nested ({"nav": {"home": ...}}) or
    flat ("nav.home"). The file's own shape decides when it has one. An
    empty file, or one whose keys are all single-segment, has no shape to
    read, so the base file's shape decides instead - that's the shape the
    app resolves keys against."""
    if any(isinstance(v, (dict, list)) for v in data.values()):
        return "nested"
    if any("." in k for k in data):
        return "flat"
    return "nested" if base_nested else "flat"


def _json_insert_block(tree, indent_unit, member_indent):
    """Serialize a subtree of new members as JSON text indented to sit
    inside an existing object, without its enclosing braces."""
    dumped = json.dumps(tree, ensure_ascii=False, indent=indent_unit)
    body = dumped.split("\n")[1:-1]
    return "\n".join(member_indent + line[len(indent_unit):] for line in body)


def _json_splice(text, close_idx, block):
    """Put `block` in as the last member(s) of the object closing at
    close_idx. Every other character in the file is left exactly as it
    was, apart from the comma valid JSON requires on what used to be the
    final member."""
    line_start = text.rfind("\n", 0, close_idx) + 1
    close_indent = text[line_start:close_idx]
    if close_indent.strip():
        close_indent = ""
    before = text[:close_idx].rstrip()
    sep = "" if before.endswith("{") else ","
    return f"{before}{sep}\n{block}\n{close_indent}{text[close_idx:]}"


def fix_missing_keys_json(text, missing_keys, base, base_nested=None):
    """Insert every key in missing_keys into the file, matching the shape
    the file already uses.

    In a nested file the key goes into the object its path names, creating
    intermediate objects as needed, because that is the only form an i18n
    runtime can resolve: i18next, vue-i18n and friends walk into the nested
    object for t("nav.settings"), so a literal top-level "nav.settings"
    member is invisible to them at runtime even though flatten_json() reads
    it as the same key. Writing the flat form turned a correctly-reported
    missing key into a permanently-missing string that translint then
    called clean.

    In a flat, dot-namespaced file the key is still written flat. Either
    way only the few characters around one closing brace move: no existing
    line is reformatted, and the diff is the new key(s) and the one comma
    JSON requires on the member that used to be last."""
    close_idx = text.rfind("}")
    open_idx = text.find("{")
    if close_idx == -1 or open_idx == -1 or open_idx > close_idx:
        raise ValueError("not a JSON object - can't insert a fixed key")

    indent = _json_detect_indent(text)

    try:
        data = json.loads(text)
    except ValueError:
        data = {}
    if not isinstance(data, dict):
        data = {}

    if _json_layout(data, base_nested) == "flat":
        new_lines = [
            f"{indent}{json.dumps(key, ensure_ascii=False)}: "
            f"{json.dumps(_untranslated_value(base[key]), ensure_ascii=False)}"
            for key in missing_keys
        ]
        return _json_splice(text, close_idx, ",\n".join(new_lines))

    extents = _json_object_extents(text)

    # Group by the deepest object that already exists on each key's path,
    # so two keys under the same new parent share one new object instead of
    # writing it twice.
    groups = {}
    for key in missing_keys:
        segments = key.split(".")
        node, prefix = data, ()
        for seg in segments[:-1]:
            nxt = node.get(seg) if isinstance(node, dict) else None
            if not isinstance(nxt, dict) or (prefix + (seg,)) not in extents:
                break
            node, prefix = nxt, prefix + (seg,)
        groups.setdefault(prefix, []).append((segments[len(prefix):], key))

    # Deepest object first (its closing brace has the lowest index), so an
    # insertion never shifts a target that hasn't been spliced yet.
    for prefix in sorted(groups, key=lambda p: extents[p][1], reverse=True):
        tree = {}
        for rest, key in groups[prefix]:
            node = tree
            for seg in rest[:-1]:
                node = node.setdefault(seg, {})
            node[rest[-1]] = _untranslated_value(base[key])
        obj_open, obj_close = extents[prefix]
        member_indent = _json_member_indent(
            text, obj_open, obj_close, indent * (len(prefix) + 1)
        )
        text = _json_splice(text, obj_close, _json_insert_block(tree, indent, member_indent))
    return text


_PROPERTIES_KEY_ESCAPE_RX = re.compile(r"[\\=: \t]")
_PROPERTIES_VALUE_ESCAPES = {"\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t"}


def _properties_escape_key(key):
    """Escape the handful of characters parse_properties' own key-splitting
    regex reads as the key/value separator, so a key that happens to
    contain one (unusual for a dotted key, but not impossible) still reads
    back as one key instead of splitting early."""
    return _PROPERTIES_KEY_ESCAPE_RX.sub(lambda m: "\\" + m.group(0), key)


def _properties_escape_value(value):
    """Escape backslashes and control characters _properties_unescape would
    otherwise decode back out of a freshly-written value - the write-side
    mirror of that function. Left plain otherwise: non-ASCII characters are
    written raw, matching how this repo's own ja.properties fixture already
    stores them, not re-encoded to \\uXXXX native2ascii form."""
    return "".join(_PROPERTIES_VALUE_ESCAPES.get(ch, ch) for ch in value)


def fix_missing_keys_properties(text, missing_keys, base):
    """Append every key in missing_keys as a new line at the end of the
    file. .properties has no nesting and no required key order, so unlike
    JSON there's no single "right" place to insert one - appending is both
    the simplest option and the one guaranteed not to touch an existing
    line."""
    lines = [
        f"{_properties_escape_key(key)}="
        f"{_properties_escape_value(_untranslated_value(base[key]))}"
        for key in missing_keys
    ]
    return text.rstrip("\n") + "\n" + "\n".join(lines) + "\n"


def fix_missing_keys_po(text, missing_keys, base):
    """Append every key in missing_keys as a new "#, fuzzy" msgid/msgstr
    block at the end of the file, separated from the last entry by a blank
    line (matching the blank-line-separated entries already in every .po
    fixture in this repo). msgstr carries the base value verbatim, not the
    [UNTRANSLATED] text marker - the fuzzy flag IS the marker here, since
    parse_po already skips fuzzy entries outright (see its docstring), so
    the fixed key still reads back as missing on the next run rather than
    as a finished translation."""
    blocks = []
    for key in missing_keys:
        msgctxt, msgid = key if isinstance(key, tuple) else (None, key)
        lines = ["#, fuzzy"]
        if msgctxt is not None:
            lines.append(f"msgctxt {json.dumps(msgctxt, ensure_ascii=False)}")
        lines.append(f"msgid {json.dumps(msgid, ensure_ascii=False)}")
        lines.append(f"msgstr {json.dumps(base[key], ensure_ascii=False)}")
        blocks.append("\n".join(lines))
    return text.rstrip("\n") + "\n\n" + "\n\n".join(blocks) + "\n"


FIX_INSERTERS = {"json": fix_missing_keys_json, "po": fix_missing_keys_po,
                  "properties": fix_missing_keys_properties}


def _key_display(key):
    """Human-readable form of a check_locale key for reports - a plain string
    for every format except .po's (msgctxt, msgid) tuples."""
    if isinstance(key, tuple):
        msgctxt, msgid = key
        return f"{msgid} (msgctxt={msgctxt})"
    return key


# gettext's own on-disk convention for a context-qualified key: msgctxt, an
# EOT byte (U+0004), then msgid. Used so every key in --json output is a
# string - a .po msgctxt key otherwise serialized as a [ctxt, id] array while
# every other key was a bare string, which is awkward for anything consuming
# the JSON.
_PO_KEY_EOT = "\x04"


def _key_json(key):
    if isinstance(key, tuple):
        msgctxt, msgid = key
        return f"{msgctxt}{_PO_KEY_EOT}{msgid}"
    return key


def _results_for_json(results):
    """A copy of the results with .po msgctxt tuple keys flattened to the
    gettext 'msgctxt\\x04msgid' string form, so --json keys are always
    strings. Everything else passes through unchanged."""
    out = []
    for r in results:
        r = dict(r)
        for field in ("missing_keys", "extra_keys", "empty_values",
                      "untranslated_values", "untranslated_markers"):
            r[field] = [_key_json(k) for k in r[field]]
        r["placeholder_mismatches"] = [
            {**m, "key": _key_json(m["key"])} for m in r["placeholder_mismatches"]
        ]
        out.append(r)
    return out


def _json_file_is_nested(path):
    """Whether the base file nests its keys. Used only as the tiebreak for
    a --fix target that has no shape of its own (an empty locale file, or
    one with only single-segment keys). None for a non-JSON or unreadable
    base, which _json_layout treats as flat."""
    if detect_format(path) != "json":
        return None
    try:
        with open(path, "r", encoding="utf-8-sig", errors="replace") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    return any(isinstance(v, (dict, list)) for v in data.values())


class NotUTF8Error(Exception):
    """A --fix target doesn't decode. --fix rewrites the whole file, so it
    refuses rather than replace the bytes it can't decode with U+FFFD and
    silently corrupt real translated text."""
    def __init__(self, path, encoding="utf-8"):
        super().__init__(path)
        self.path = path
        self.encoding = encoding


class FixEncodeError(Exception):
    """The value --fix wants to insert has characters the file's own
    encoding can't represent. Raised before anything is written."""
    def __init__(self, path, encoding):
        super().__init__(path)
        self.path = path
        self.encoding = encoding


_UTF8_BOM = b"\xef\xbb\xbf"


def _read_for_fix(path, fmt=None, encoding=None):
    """Read a file --fix is about to rewrite. Returns (text, had_bom,
    encoding) so both a UTF-8 BOM and the file's encoding survive the
    round-trip.

    Decodes strictly: a lint-only read tolerates junk, but a rewrite must
    not, so a file that isn't valid UTF-8 raises NotUTF8Error rather than
    getting its unreadable bytes replaced and written back. The two ways
    out of that are --encoding, and .properties, which is ISO-8859-1 by
    specification and so is read and written back as ISO-8859-1."""
    with open(path, "rb") as fh:
        raw = fh.read()
    had_bom = raw.startswith(_UTF8_BOM)
    body = raw[len(_UTF8_BOM):] if had_bom else raw
    if encoding:
        try:
            return body.decode(encoding), had_bom, encoding
        except LookupError:
            raise ValueError(f"{path}: unknown encoding '{encoding}'")
        except UnicodeDecodeError:
            raise NotUTF8Error(path, encoding)
    try:
        return body.decode("utf-8"), had_bom, "utf-8"
    except UnicodeDecodeError:
        if fmt == "properties":
            _warn(f"translint: {path}: not valid UTF-8, read and rewritten as "
                  f"{PROPERTIES_LEGACY_ENCODING} (java.util.Properties' own encoding)")
            return (body.decode(PROPERTIES_LEGACY_ENCODING), had_bom,
                    PROPERTIES_LEGACY_ENCODING)
        raise NotUTF8Error(path, "utf-8")


def apply_fix(results, base, dry_run=False, base_nested=None, encoding=None):
    """Insert missing keys for every locale result that has any, using the
    format-appropriate inserter above. Reads and (unless dry_run) rewrites
    each affected file directly - the one place in translint that writes
    anything besides stdout, and only ever this: new keys inserted, nothing
    existing rewritten. Returns a human-readable summary string (None if
    there was nothing to insert) - the caller prints it to stderr, never
    stdout, so --json/--quiet output stays exactly the machine-readable
    contract JSON_SCHEMA_KEYS promises, --fix or not.

    Reads, rewrites and re-encodes every target up front, so a file that
    won't decode (NotUTF8Error) or whose encoding can't hold the inserted
    value (FixEncodeError) stops the run before anything has been written
    rather than after some files were - all or nothing."""
    pending = []
    for r in results:
        if not r["missing_keys"]:
            continue
        text, had_bom, enc = _read_for_fix(r["path"], fmt=r["format"], encoding=encoding)
        # Only the JSON inserter has a shape to match, so only it takes the
        # base file's nesting as a tiebreak.
        extra = {"base_nested": base_nested} if r["format"] == "json" else {}
        new_text = FIX_INSERTERS[r["format"]](text, r["missing_keys"], base, **extra)
        try:
            body = new_text.encode(enc)
        except UnicodeEncodeError:
            raise FixEncodeError(r["path"], enc)
        pending.append((r, (_UTF8_BOM if had_bom else b"") + body))

    lines = []
    for r, out in pending:
        if not dry_run:
            with open(r["path"], "wb") as fh:
                fh.write(out)
        keys_display = ", ".join(_key_display(k) for k in r["missing_keys"])
        lines.append(f"  {r['locale']} ({r['path']}): "
                      f"{len(r['missing_keys'])} key(s) - {keys_display}")
    if not lines:
        return None
    verb = "would insert" if dry_run else "inserted"
    header = f"translint --fix: {verb} missing keys" + (" (dry run, nothing written)"
                                                          if dry_run else "")
    return "\n".join([header] + lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv=None):
    # Locale files are full of text a legacy Windows code page can't encode -
    # the report quotes their keys and values, so a ja/ar/th run on a cp1252
    # console would otherwise die in UnicodeEncodeError mid-print. Emit UTF-8
    # and degrade to replacement characters rather than crash.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    ap = argparse.ArgumentParser(
        prog="translint",
        description="Check locale files for missing keys, placeholder mismatches, "
                     "empty values, and untranslated strings.",
    )
    ap.add_argument("paths", nargs="*", default=["."], metavar="path",
                    help="a directory of locale files, or specific files (default: .)")
    ap.add_argument("--base", default="en", metavar="LOCALE",
                    help="locale name (filename stem) to treat as the reference (default: en)")
    ap.add_argument("--format", choices=SUPPORTED_FORMATS, default=None,
                    help="force a format instead of detecting from extension (a directory "
                         "scan then takes every file in the directory, not just the ones "
                         "with a recognized extension)")
    ap.add_argument("--encoding", metavar="ENC", default=None,
                    help="decode locale files with this encoding instead of UTF-8 "
                         "(a .properties file that isn't valid UTF-8 already falls back "
                         "to ISO-8859-1, the encoding the format specifies)")
    ap.add_argument("--recursive", action="store_true",
                    help="scan subdirectories too (default: only the files directly "
                         "inside the directory you point at)")
    ap.add_argument("--locale-from", choices=("stem", "dir"), default="stem",
                    help="where the locale name comes from: the filename stem (en.json, "
                         "the default) or the directory holding the file (en/common.json, "
                         "the next-i18next layout - use with --recursive)")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--strict", action="store_true",
                    help="also fail on extra keys and untranslated-value hits (default: only "
                         "missing keys, placeholder mismatches, and empty values fail)")
    ap.add_argument("--allow-identical", action="append", default=[], metavar="KEY",
                    help="key exempt from the untranslated-value heuristic (repeatable)")
    ap.add_argument("--do-not-translate", action="append", default=[], metavar="TOKEN",
                    help="substring stripped before the untranslated-value heuristic runs, "
                         "e.g. a brand name (repeatable)")
    ap.add_argument("--config", metavar="PATH",
                    help="path to a .translintrc.json with allow_identical/do_not_translate "
                         "lists (default: .translintrc.json in the scanned directory, if present)")
    ap.add_argument("--quiet", action="store_true", help="summary line only")
    ap.add_argument("--fix", action="store_true",
                    help="insert MISSING keys only, each tagged with an unmissable "
                         "[UNTRANSLATED] marker (.po gets its own fuzzy flag instead) - "
                         "never touches an existing key, never invents a translation "
                         "(see README 'Fix mode')")
    ap.add_argument("--dry-run", action="store_true",
                    help="with --fix, show exactly what would be inserted without "
                         "writing any file")
    ap.add_argument("--version", action="version", version=f"translint {__version__}")
    args = ap.parse_args(argv)

    if args.dry_run and not args.fix:
        print("translint: --dry-run only makes sense with --fix", file=sys.stderr)
        return 2

    allow_identical = list(args.allow_identical)
    do_not_translate = list(args.do_not_translate)

    config_path = args.config
    if config_path is None:
        for p in args.paths:
            candidate = os.path.join(p, ".translintrc.json") if os.path.isdir(p) else None
            if candidate and os.path.isfile(candidate):
                config_path = candidate
                break
    if config_path:
        try:
            with open(config_path, "r", encoding="utf-8-sig") as fh:
                cfg = json.load(fh)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"translint: {config_path}: {exc}", file=sys.stderr)
            return 2
        if not isinstance(cfg, dict):
            print(f"translint: {config_path}: top level must be a JSON object", file=sys.stderr)
            return 2
        allow_identical += list(cfg.get("allow_identical", []))
        do_not_translate += list(cfg.get("do_not_translate", []))

    # Expand glob arguments ourselves - PowerShell and cmd.exe don't expand
    # wildcards before argv reaches us, unlike POSIX shells.
    expanded = []
    for p in args.paths:
        # Only treat an argument as a glob when it doesn't already name a real
        # path - a directory literally called "loc[1]" exists on disk and must
        # win over reading "[1]" as a character class that matches nothing.
        if any(ch in p for ch in "*?[") and not os.path.exists(p):
            matches = sorted(glob.glob(p))
            if not matches:
                print(f"translint: {p}: no files match", file=sys.stderr)
                return 2
            expanded.extend(matches)
        else:
            expanded.append(p)

    entries = discover_locale_files(expanded, recursive=args.recursive,
                                    forced_fmt=args.format)
    if not entries:
        print(f"translint: no locale files found in {' '.join(args.paths)}", file=sys.stderr)
        return 2

    # One namespace per set of files that belong together. With the default
    # --locale-from stem there's exactly one, holding everything discovered;
    # with dir there's one per namespace file (common, footer, ...), each
    # with its own base, so en/common.json is only ever diffed against
    # de/common.json.
    by_namespace = {}
    for path, root in entries:
        locale, namespace = locale_and_namespace(path, root, args.locale_from)
        by_namespace.setdefault(namespace, []).append((locale, path))

    groups = []
    for namespace, members in by_namespace.items():
        base_path = next((p for loc, p in members if loc == args.base), None)
        if base_path is None:
            names = ", ".join(loc for loc, _ in members)
            where = f" for namespace '{namespace}'" if namespace else ""
            print(f"translint: no file named '{args.base}' found{where} among: {names}",
                  file=sys.stderr)
            return 2
        try:
            base_dict, _base_fmt = load_locale(base_path, fmt=args.format,
                                               encoding=args.encoding)
        except (ValueError, OSError) as exc:
            print(f"translint: {exc}", file=sys.stderr)
            return 2
        groups.append({"base_path": base_path, "base": base_dict, "members": members})

    # A plain function, not a loop inlined twice: --fix needs this exact same
    # check re-run against the files it just rewrote, so the report and exit
    # code reflect what's actually on disk afterward, not a stale pre-fix
    # snapshot. Returns None (having already printed the error) on a parse
    # failure, same as the rest of main()'s error handling. Each result is
    # paired with the group it was checked against, so --fix knows which base
    # to take an inserted value from.
    def check_all_locales():
        out = []
        for group in groups:
            for locale, f in group["members"]:
                if f == group["base_path"]:
                    continue
                try:
                    locale_dict, fmt = load_locale(f, fmt=args.format,
                                                   encoding=args.encoding)
                except (ValueError, OSError) as exc:
                    print(f"translint: {exc}", file=sys.stderr)
                    return None
                out.append((group, check_locale(
                    group["base"], locale_dict, locale, f, fmt,
                    do_not_translate=do_not_translate, allow_identical=allow_identical,
                )))
        return out

    checked = check_all_locales()
    if checked is None:
        return 2

    if not checked:
        print(f"translint: only the base locale ('{args.base}') was found, nothing to check",
              file=sys.stderr)
        return 2
    results = [r for _, r in checked]

    if args.fix:
        # Always printed to stderr, never stdout - --json/--quiet output on
        # stdout must stay exactly the machine-readable contract regardless
        # of whether --fix had anything to insert.
        summaries = []
        try:
            for group in groups:
                summary = apply_fix(
                    [r for g, r in checked if g is group], group["base"],
                    dry_run=args.dry_run,
                    base_nested=_json_file_is_nested(group["base_path"]),
                    encoding=args.encoding,
                )
                if summary:
                    summaries.append(summary)
        except NotUTF8Error as exc:
            print(f"translint: {exc.path}: not valid {exc.encoding}, refusing to "
                  f"rewrite (--fix) - pass --encoding to name the file's encoding",
                  file=sys.stderr)
            return 2
        except FixEncodeError as exc:
            print(f"translint: {exc.path}: the base value for a missing key has "
                  f"characters {exc.encoding} can't hold, refusing to rewrite (--fix) "
                  f"- convert the file to UTF-8 first", file=sys.stderr)
            return 2
        except ValueError as exc:
            print(f"translint: {exc}", file=sys.stderr)
            return 2
        summary = "\n".join(summaries)
        if summary:
            print(summary, file=sys.stderr)
            if not args.dry_run:
                checked = check_all_locales()
                if checked is None:
                    return 2
                results = [r for _, r in checked]

    if args.json:
        print(json.dumps(_results_for_json(results), indent=2))
    elif args.quiet:
        failing = [r["locale"] for r in results if is_failing(r, strict=args.strict)]
        if failing:
            print(f"translint: issues in {', '.join(failing)}")
        else:
            print("translint: all locales clean")
    else:
        sys.stdout.write(report(results))

    return 1 if any(is_failing(r, strict=args.strict) for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())