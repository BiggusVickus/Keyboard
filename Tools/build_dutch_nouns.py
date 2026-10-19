#!/usr/bin/env python3
"""Builds the offline de/het word list (KeyboardCore/Resources/DutchNouns.txt) from Wiktionary.

Data: Wiktionary (https://nl.wiktionary.org and https://en.wiktionary.org), licensed CC BY-SA 4.0,
as machine-readable JSON from kaikki.org / wiktextract (Tatu Ylonen, LREC 2022).

Download (about 130 MB + 250 MB):
    curl -LO https://kaikki.org/dictionary/downloads/nl/nl-extract.jsonl.gz
    curl -LO https://kaikki.org/dictionary/Dutch/kaikki.org-dictionary-Dutch.jsonl
Run:
    python3 Tools/build_dutch_nouns.py nl-extract.jsonl.gz kaikki.org-dictionary-Dutch.jsonl

Output (about 460,000 words, 7 MB): one line per word, "word<TAB>code", sorted by UTF-8 bytes so the keyboard can binary-search
the file without loading it into memory. Codes:
    d  de-word            h  het-word
    p  plural (always de) b  both de and het (e.g. idee, bal): never flagged
    x  also another kind of word (weg = away, rook = smelled, licht = light): never flagged
    a  inflected adjective; a third column holds the form without -e ("grote<TAB>a<TAB>groot")

Adverbs, prepositions, pronouns and plain adjectives are listed as x as well, so the keyboard's
fallback rules never treat them as nouns (zometeen is not a compound of teen).

A noun is marked x when it is also an adjective, adverb, pronoun, preposition, numeral, verb
infinitive or a verb form that can follow "het" as a subject (het rook, het lucht op, het werkt).
That keeps the checker from flagging correct sentences such as "Ik gooi het weg".
"""

import gzip
import json
import re
import sys
from collections import defaultdict

WORD = re.compile(r"^[a-zà-öø-ÿ][a-zà-öø-ÿ'-]*$")
OTHER_POS = {"adj", "adv", "prep", "pron", "det", "num", "conj", "intj", "article",
             "particle", "postp", "circumpos", "contraction", "prep_phrase"}
# Verb forms that never come right after an article: "ik werk", "werk!", "werk jij".
HARMLESS_VERB_FORMS = ("eerste persoon enkelvoud tegenwoordige tijd", "gebiedende wijs")
# English-edition conjugation tags of forms that can follow "het" as a subject.
RISKY_VERB_TAGS = {"past", "participle", "third-person", "subjunctive", "infinitive"}
# Function words, in case a dictionary also lists them as (rare) nouns.
NEVER = set("""de het een die dat deze dit en of maar want dan als zo er hier daar niet geen
    wel ook nog al te om op in aan uit bij met van voor na naar tot door over onder ik jij je u
    hij zij ze wij we jullie men mijn jouw zijn haar ons onze hun wie wat waar welk welke""".split())
# Time words used without an article: "Ik doe het zondag", "We gaan het januari doen".
NEVER |= set("""maandag dinsdag woensdag donderdag vrijdag zaterdag zondag januari februari maart
    april mei juni juli augustus september oktober november december""".split())

GENDER_TAGS = {"masculine": "d", "feminine": "d", "common": "d", "neuter": "h"}


def open_jsonl(path):
    return gzip.open(path, "rt", encoding="utf-8") if path.endswith(".gz") else open(path, encoding="utf-8")


def clean(form):
    form = form.strip()
    return form if WORD.match(form) else None


def is_form_of(entry, kind):
    return any("form-of" in (s.get("tags") or []) and kind in (s.get("tags") or [])
               for s in entry.get("senses", []))


INFLECTED_GLOSS = re.compile(r"^verbogen vorm van de (stellende|vergrotende) trap van (\S+?)[.;,]?$")


def main(nl_path, en_path=None):
    genders = defaultdict(set)    # word -> {"d", "h"}
    plurals = set()
    excluded = set()
    other_words = set()           # not nouns at all: adverbs, prepositions, plain adjectives…
    inflected = {}                # grote -> groot, grotere -> groter

    def add_adjective_forms(entry, lemma):
        for form in entry.get("forms") or []:
            w = clean(form.get("form", ""))
            tags = set(form.get("tags") or [])
            if not w:
                continue
            excluded.add(w)
            if "inflected" in tags and "positive" in tags:
                inflected.setdefault(w, lemma)
            elif "inflected" in tags and "comparative" in tags and w.endswith("e"):
                inflected.setdefault(w, w[:-1])
            elif "uninflected" in tags:
                other_words.add(w)

    def add_noun(word, entry_tags, sense_tags, forms=()):
        tags = set(entry_tags or [])
        for t in sense_tags:
            tags |= set(t or [])
        # The English edition puts the gender on the "canonical" form: scapulier (n).
        for form in forms or []:
            if "canonical" in (form.get("tags") or []):
                tags |= set(form.get("tags") or [])
        found = {GENDER_TAGS[t] for t in tags if t in GENDER_TAGS}
        if "plural" in tags and not found:
            plurals.add(word)
        genders[word] |= found

    def add_noun_forms(entry):
        for form in entry.get("forms") or []:
            word = clean(form.get("form", ""))
            tags = set(form.get("tags") or [])
            if not word or "canonical" in tags:
                continue
            if "plural" in tags:
                plurals.add(word)
            elif "diminutive" in tags:
                genders[word].add("h")  # diminutives are always het

    # Dutch edition (nl.wiktionary): most nouns, clear verb-form glosses.
    with open_jsonl(nl_path) as f:
        for line in f:
            e = json.loads(line)
            if e.get("lang_code") != "nl":
                continue
            word, pos = clean(e.get("word", "")), e.get("pos")
            if not word:
                continue
            senses = e.get("senses", [])
            if pos == "noun":
                if is_form_of(e, "plural"):
                    plurals.add(word)
                else:
                    add_noun(word, e.get("tags"), [s.get("tags") for s in senses])
                    add_noun_forms(e)
            elif pos == "verb":
                if "form-of" in (e.get("tags") or []):
                    for s in senses:
                        gloss = " ".join(s.get("glosses") or [])
                        if not gloss.startswith(HARMLESS_VERB_FORMS) and "inversion" not in (s.get("tags") or []):
                            excluded.add(word)
                else:
                    excluded.add(word)  # infinitive: "het lopen"
                    for form in e.get("forms") or []:
                        w = clean(form.get("form", ""))
                        if w and RISKY_VERB_TAGS & set(form.get("tags") or []):
                            excluded.add(w)
            elif pos in OTHER_POS:
                excluded.add(word)
                other_words.add(word)
                if pos == "adj":
                    add_adjective_forms(e, word)
                    for sense in senses:
                        m = INFLECTED_GLOSS.match(" ".join(sense.get("glosses") or []))
                        base = clean(m.group(2)) if m else None
                        if base:
                            other_words.discard(word)
                            inflected.setdefault(word, base if m.group(1) == "stellende" else word[:-1])

    # English edition (en.wiktionary): second opinion on genders, plus full conjugation tables.
    if en_path:
        with open_jsonl(en_path) as f:
            for line in f:
                e = json.loads(line)
                word, pos = clean(e.get("word", "")), e.get("pos")
                if not word:
                    continue
                if pos == "noun":
                    if is_form_of(e, "plural"):
                        plurals.add(word)
                    else:
                        add_noun(word, e.get("tags"), [s.get("tags") for s in e.get("senses", [])], e.get("forms"))
                        add_noun_forms(e)
                elif pos == "verb":
                    if not any("form-of" in (s.get("tags") or []) for s in e.get("senses", [])):
                        excluded.add(word)
                    for form in e.get("forms") or []:
                        w = clean(form.get("form", ""))
                        if w and RISKY_VERB_TAGS & set(form.get("tags") or []):
                            excluded.add(w)
                elif pos in OTHER_POS:
                    excluded.add(word)

    entries = {}
    for word, found in genders.items():
        if not found:
            continue
        if word in excluded or word in NEVER:
            entries[word] = "x"
        elif found == {"d"}:
            entries[word] = "d"
        elif found == {"h"}:
            entries[word] = "h"
        else:
            entries[word] = "b"
    for word in plurals:
        if word in entries:
            # Also a singular noun (kussen = pillow, and the plural of kus): don't guess.
            if entries[word] in ("d", "h"):
                entries[word] = "x"
            continue
        entries[word] = "x" if word in excluded or word in NEVER else "p"

    # Every other known word (verb forms such as inbakte, adverbs, plain adjectives) is listed as x,
    # so the keyboard's fallback rules never read it as a noun.
    for word in other_words | excluded:
        entries.setdefault(word, "x")
    for word, base in inflected.items():
        # An inflected adjective is never also flagged as a noun.
        if base != word and word not in NEVER:
            entries[word] = "a	" + base

    # Leave out what the keyboard's own rules already get right: -je is het, -jes is plural.
    def covered_by_rules(word, code):
        return (code == "h" and word.endswith("je") and len(word) >= 4) or                (code == "p" and word.endswith("jes") and len(word) >= 5)

    out = sorted(((w, c) for w, c in entries.items() if not covered_by_rules(w, c)),
                 key=lambda kv: kv[0].encode("utf-8"))
    sys.stdout.buffer.write("".join(f"{w}\t{c}\n" for w, c in out).encode("utf-8"))
    counts = defaultdict(int)
    for _, c in out:
        counts[c[0]] += 1
    print(f"{len(out)} words: {dict(counts)}", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
