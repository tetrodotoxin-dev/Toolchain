#!/usr/bin/env python3
# Copyright (c) 2023-present Matt Kaes and contributors

"""Classify comment prose with a deterministic, inspectable score."""

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import re
import sys


ACCEPT_THRESHOLD = 40
REJECT_THRESHOLD = 60
WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9_+'-]*")
TECHNICAL_TERM = re.compile(
    r"\b(?:ABI|addresses?|alignment|allocation|archive|argument|arrays?|base|"
    r"bits?|blocks?|bodies|body|buffer|byte|bytes|cache|callback|capacity|"
    r"checksum|"
    r"compiler|context|composite|content|coordinate|cursor|descriptor|"
    r"destination|device|diagnostic|digest|element|extent|field|form|frame|"
    r"directory|filename|function|geometry|hash|index|instantiation|interface|"
    r"inventory|key|lane|layout|library|loop|mask|memory|module|multiplication|"
    r"occurrence|operation|output|padding|path|payload|pixel|pointer|policy|"
    r"predictor|provider|record|reference|register|representation|result|route|"
    r"row|sample|scanline|schema|segment|selection|separator|signature|source|"
    r"storage|stream|stride|symbol|table|thread|token|value|vector|width|"
    r"workspace)\b",
    re.IGNORECASE,
)
EXPLICIT_CONSTRUCTOR = re.compile(
    r"(?m)^[ \t]*(?:(?:\[\[[^\n]*\]\]|consteval|constexpr|friend|inline)\s+)*"
    r"explicit(?:\s*\([^{};\n]*\))?\s+(?!operator\b)"
    r"[A-Za-z_][A-Za-z0-9_]*\s*\("
)
EXPLICIT_PREFIX = re.compile(r"\s*(?:template\s*<[^;{}]*>\s*)*")
POLICY_HOOK_CALL = re.compile(
    r"(?:get_policy\s*\(\s*\)\s*\.|policy_type\s*::)\s*"
    r"([A-Za-z_][A-Za-z0-9_]*)\s*\("
)
PROHIBITED_ALIAS_WORDS = frozenset(
    {
        "admissibility",
        "admissibilities",
        "admissible",
        "admissibly",
        "admission",
        "admissions",
        "admissive",
        "admissively",
        "admissiveness",
        "admit",
        "admits",
        "admitted",
        "admitter",
        "admitters",
        "admitting",
        "admittance",
        "admittances",
        "inadmissibility",
        "inadmissibilities",
        "inadmissible",
        "inadmissibly",
    }
)


@dataclass(frozen=True)
class Signal:
    name: str
    points: int
    explanation: str


@dataclass(frozen=True)
class Verdict:
    decision: str
    score: int
    accept_below: int
    reject_at: int
    comment: str
    signals: tuple[Signal, ...]
    path: str | None = None
    line: int | None = None
    attached_line: int | None = None
    attached_code: str | None = None
    minimum_score: int = 0


@dataclass(frozen=True)
class SourceSlice:
    path: str
    line: int
    comment: str
    attached_line: int
    attached: str


EXPLICIT_CONSTRUCTOR_SIGNAL = Signal(
    "unjustified explicit constructor",
    100,
    "Each explicit constructor has its own comment explaining why implicit "
    "construction would violate its contract.",
)


def normalize(comment):
    """Remove common comment delimiters without interpreting source code."""
    lines = []
    for source_line in comment.strip().splitlines():
        line = source_line.strip()
        if line.startswith("//"):
            line = line[2:].lstrip()
        elif line.startswith("#"):
            line = line[1:].lstrip()
        elif line.startswith("/*"):
            line = line[2:].lstrip()
        if line.endswith("*/"):
            line = line[:-2].rstrip()
        if line.startswith("*"):
            line = line[1:].lstrip()
        if line:
            lines.append(line)
    return " ".join(lines)


def paragraphs(comment):
    """Preserve rhetorical paragraph order while removing comment markers."""
    result = []
    current = []
    for source_line in comment.strip().splitlines():
        line = normalize(source_line)
        if line:
            current.append(line)
        elif current:
            result.append(" ".join(current))
            current = []
    if current:
        result.append(" ".join(current))
    return result


def matches(pattern, comment):
    return re.search(pattern, comment, re.IGNORECASE) is not None


def decision(score):
    if score < ACCEPT_THRESHOLD:
        return "Accept"
    if score < REJECT_THRESHOLD:
        return "Warn"
    return "Reject"


def source_verdict(base, context, extra):
    score = max(
        base.minimum_score,
        max(0, min(100, base.score + sum(signal.points for signal in extra))),
    )
    return Verdict(
        decision(score),
        score,
        ACCEPT_THRESHOLD,
        REJECT_THRESHOLD,
        base.comment,
        base.signals + tuple(extra),
        context.path,
        context.line,
        context.attached_line,
        context.attached,
        base.minimum_score,
    )


def classify(source):
    """Return a repeatable style verdict and every contribution to its score."""
    comment = normalize(source)
    grammar_comment = normalize(
        "\n".join(
            line
            for line in source.splitlines()
            if not normalize(line).startswith("auto ")
        )
    )
    punctuation_prose = re.sub(r"`[^`]*`", "", comment)
    punctuation_prose = re.sub(r"\]\([^)]*\)", "]", punctuation_prose)
    punctuation_prose = re.sub(r"https?://\S+", "", punctuation_prose)
    words = WORD.findall(comment)
    prohibited_aliases = {
        word
        for word in words
        if any(alias in word.lower() for alias in PROHIBITED_ALIAS_WORDS)
    }
    imperative = bool(words) and words[0].lower() in {
        "add",
        "build",
        "check",
        "create",
        "generate",
        "get",
        "handle",
        "initialize",
        "keep",
        "make",
        "return",
        "set",
        "update",
        "use",
    }
    structural_heading = (
        1 <= len(words) <= 7
        and re.fullmatch(r"[A-Za-z]+(?:\s+[A-Za-z]+){0,6}", comment) is not None
        and not imperative
        and words[0].lower() not in {"fixme", "todo"}
    )
    bullet_count = sum(
        re.match(r"\s*(?:(?://|#)\s+)?\*\s+", line) is not None
        for line in source.splitlines()
    )
    signals = []
    minimum_score = 0

    def add(name, points, explanation, score_floor=0):
        nonlocal minimum_score
        signals.append(Signal(name, points, explanation))
        minimum_score = max(minimum_score, score_floor)

    if prohibited_aliases:
        add(
            "prohibited alias word",
            100,
            "The admit word family substitutes a generic label for the "
            "operation's concrete verb.",
            100,
        )

    if matches(r"\bCopyright\s*\(c\)", comment):
        add(
            "license metadata",
            -45,
            "A copyright header is file metadata rather than explanatory prose.",
        )

    namespace_annotation = re.fullmatch(
        r"(?:end\s+)?namespace(?:\s+[A-Za-z_][A-Za-z0-9_:]*)?",
        comment,
        re.IGNORECASE,
    ) is not None
    if namespace_annotation:
        add(
            "namespace annotation",
            -45,
            "A namespace annotation marks structure rather than explaining behavior.",
        )

    if re.fullmatch(
        r"(?:'[^']*'|\"[^\"]*\"|[A-Z]+\d+\.?|0x[0-9A-Fa-f]+|\d+|"
        r"[+*/%=<>!&|^~?-])",
        comment,
    ):
        add(
            "literal annotation",
            -45,
            "A literal annotation labels nearby test data rather than making a prose claim.",
        )

    if structural_heading:
        add(
            "structural heading",
            -10,
            "A compact noun heading provides navigation rather than behavioral prose.",
        )

    if 5 <= len(words) <= 10 and not structural_heading:
        add(
            "thin explanation",
            10,
            "The short statement has little room for a mechanism, boundary or reason.",
        )

    if re.search(
        r"(?<=[A-Za-z0-9])-(?=[A-Za-z0-9])|[\u2013\u2014]",
        punctuation_prose,
    ):
        add(
            "hyphenated prose",
            32,
            "A hyphen or dash compresses a relationship that should be stated "
            "directly.",
        )

    if ";" in punctuation_prose:
        add(
            "semicolon joined prose",
            100,
            "A semicolon joins claims that should stand as direct sentences.",
            100,
        )

    if matches(
        r"\b(?:simple|simply|obvious(?:ly)?|easy|straightforward|seamless(?:ly)?|"
        r"robust|flexible|clean(?:ly)?|elegant|comprehensive|powerful|conventional)\b",
        comment,
    ):
        add(
            "generic praise",
            43,
            "A generic quality word substitutes for concrete evidence.",
        )

    generic_benefit = matches(
        r"\b(?:ensure(?:s|d|ing)?|provide(?:s|d|ing)?|allow(?:s|ed|ing)?|"
        r"handle(?:s|d|ing)?|responsible for|improve(?:s|d|ing)?|"
        r"optimi[sz](?:e|es|ed|ing)|efficient(?:ly)?|can)\b",
        comment,
    )

    canned_framing = matches(
        r"\b(?:note that|it is important|in conclusion|as mentioned|"
        r"for completeness|needless to say)\b",
        comment,
    )
    if canned_framing:
        add(
            "canned framing",
            18,
            "The framing delays the technical claim instead of stating it directly.",
        )

    vague_scope = matches(r"\b(?:some form|another form|in some way)\b", comment)
    if vague_scope:
        add(
            "vague semantic scope",
            18,
            "The prose refers to an unspecified form or mechanism instead of "
            "naming the distinction.",
        )

    if canned_framing and vague_scope:
        add(
            "stacked abstraction",
            10,
            "Canned framing compounds an already unspecified semantic claim.",
        )

    if matches(r"\b(?:answers?|questions?)\b", comment):
        add(
            "placeholder protocol term",
            20,
            "Answer or question hides whether the prose means a contract "
            "request, status result, API record, representation or value.",
            60,
        )

    if matches(r"\badditional overhead\b", comment):
        add(
            "unsupported overhead",
            15,
            "Overhead is asserted without a quantity or comparison that establishes its relevance.",
        )

    if matches(
        r"\bthis (?:function|method|class|code|logic|implementation|loop)\b|"
        r"\b(?:helper|utility) (?:function|method|class)\b",
        comment,
    ):
        add(
            "generic subject",
            16,
            "The subject names a code category rather than the local owner or operation.",
        )

    if matches(
        r"\b(?:generator for (?:creating|generating)|"
        r"helper (?:that|to) help|function (?:that|to) function)\b",
        comment,
    ):
        add(
            "tautology",
            26,
            "The description repeats its role without adding a reason or constraint.",
        )

    contradictory_status_action = matches(
        r"\b(?:Satisfied|Success)\s+(?:provides|returns|supplies)\s+"
        r"(?:neither|no|nothing)\b",
        comment,
    )
    if contradictory_status_action:
        add(
            "contradictory status action",
            80,
            "A successful outcome is made the actor of a negated result, which "
            "obscures what the operation actually establishes.",
            70,
        )

    status_as_operational_actor = matches(
        r"\b(?:Satisfied|Success)\s+(?:allocates?|calls?|constructs?|copies|"
        r"creates?|establishes?|fills?|generates?|invokes?|provides|publishes?|"
        r"returns?|stores|supplies|transfers|writes?)\b",
        comment,
    )
    if status_as_operational_actor and not contradictory_status_action:
        add(
            "status used as operational actor",
            20,
            "A returned status is credited with performing work that belongs "
            "to the operation or its provider.",
            60,
        )

    if matches(
        r"\b(?:Satisfied|Success)\b[^.!?]{0,100}\b"
        r"(?:invalid|unavailable|unusable|nothing|neither|no usable)\b|"
        r"\b(?:Unknown|Rejected|Failure)\b[^.!?]{0,100}\b"
        r"(?:publishes?|supplies|returns|produces)\b[^.!?]{0,60}\b"
        r"(?:complete|usable|valid)\s+(?:API|interface|record)\b|"
        r"\b(?:Unknown|Rejected|Failure)\b[^.!?]{0,100}\bcontains\b\s+"
        r"(?:the\s+|an?\s+)?(?:complete|usable|valid)\s+"
        r"(?:API|interface|record)\b",
        comment,
    ):
        add(
            "contradictory binding outcome",
            80,
            "The prose assigns unusable output to success or a complete API "
            "to failure.",
            75,
        )

    if matches(r"\bif\b[^,.!?;]{1,60}\bif\b", comment):
        add(
            "malformed conditional",
            15,
            "A repeated conditional marker leaves the success or failure "
            "condition unparseable.",
            65,
        )

    if matches(
        r"\b(?:caller|callee|consumer|provider)\s+(?:now\s+)?"
        r"owns?\s+(?:(?:a|an|the)\s+)?(?:new\s+)?lifetime\b",
        comment,
    ):
        add(
            "lifetime treated as a resource",
            15,
            "The prose claims ownership of a lifetime instead of naming the "
            "resource, its owner and the access interval.",
            65,
        )

    if matches(
        r"\bdata\b[^.!?]{0,100}\bincluding\s+(?:callables?|functions?)\b",
        comment,
    ):
        add(
            "pointer category confusion",
            10,
            "Data and callable pointers are collapsed into one ownership claim "
            "despite having different providers and validity requirements.",
            60,
        )

    copying_extends_access = matches(
        r"\bcopying\b[^.!?]{0,140}\b(?:acquires?|extends?|grants?)\b"
        r"[^.!?]{0,50}\b(?:access|lifetime|ownership)\b",
        comment,
    )
    copying_denies_extension = matches(
        r"\bcopying\b[^.!?]{0,140}\b(?:cannot|does not|never)\b"
        r"[^.!?]{0,50}\b(?:acquires?|extends?|grants?)\b",
        comment,
    )
    if copying_extends_access and not copying_denies_extension:
        add(
            "copy claims lifetime transfer",
            20,
            "Copying pointer-bearing records is credited with acquiring or "
            "extending access that only the supplying contract can establish.",
            65,
        )

    if matches(
        r"\b(?:supports|support (?:answer|result))\b[^.!?]{0,120}\b"
        r"(?:gains?|grants?|has|obtains?|provides|supplies)\s+"
        r"(?!no\b)(?:direct\s+)?callable access\b",
        comment,
    ):
        add(
            "semantic probe used as binding",
            20,
            "A semantic support answer is credited with callable access that "
            "requires a successful representation binding.",
            65,
        )

    causal = matches(
        r"\b(?:because|since|so that|so|therefore|otherwise|rather than|"
        r"instead of|before|after|until|unless|while|without|even when|"
        r"in order to|prevents?|avoids?|lets?|makes|means?|now that|useful for|"
        r"to aid|would)\b|"
        r"\bmake\b[^.!?]{0,60}\b(?:exact|error)\b|"
        r"\bkeeps?\b[^.!?]{0,60}\b(?:from|independent)\b",
        comment,
    )
    if causal:
        add(
            "causal account",
            -14,
            "The comment connects a mechanism or choice to its consequence.",
        )

    guarantees = re.findall(
        r"\b(?:must|cannot|never|exactly|invalid|unavailable|unsupported|"
        r"undefined behavior|guaranteed|requires?|required|only if|"
        r"(?:does|do|will) not|can overlap|"
        r"only (?:way|when|while|after|before)|"
        r"only that|no such|"
        r"fails?|refus(?:e|es|ed|ing)|reject(?:s|ed|ing)?)\b",
        comment,
        re.IGNORECASE,
    )
    if guarantees:
        points = -min(24, len(guarantees) * 6)
        add(
            "direct guarantees",
            points,
            "Normative language states observable acceptance, failure or validity rules.",
        )

    lifetime_relation = matches(
        r"\b(?:preserv(?:e|es|ed|ing)|retain(?:s|ed|ing)?|"
        r"borrow(?:s|ed|ing)?|release(?:s|d|ing)?|lifetime|ownership|"
        r"caller|callee|synchronous)\b",
        comment,
    )
    if lifetime_relation:
        add(
            "lifetime relation",
            -6,
            "The comment identifies participants or the duration of access.",
        )

    tradeoff = matches(
        r"\b(?:tradeoff|downside|cost|overhead|faster|slower|worse|"
        r"benchmark(?:ed|s|ing)?|measur(?:e|es|ed|ing)|in testing|fallback|"
        r"speed\s+(?:versus|vs\.?)\s+size)\b",
        comment,
    )
    if tradeoff:
        add(
            "tradeoff or evidence",
            -16,
            "The claim records measured evidence, a cost or a rejected alternative.",
        )

    empirical = matches(
        r"\b(?:in testing|we measured|measurements? showed|observed in|"
        r"in practice|seems? to)\b",
        comment,
    )
    if empirical:
        add(
            "empirical voice",
            -12,
            "The author distinguishes observed behavior from a universal claim.",
        )

    stated_benefit = matches(
        r"\bhelps? (?:avoid|reduce|save)\b",
        comment,
    )
    if stated_benefit:
        add(
            "stated benefit",
            -5,
            "The comment names a useful outcome but may still need the basis for its policy.",
        )

    test_purpose = matches(
        r"\b(?:this|that|test|fixture|case|validation)\s+"
        r"(?:catches|checks|exercises|exposes)\b|\bthen exercises\b|"
        r"\bexercises?\s+(?:the\s+)?(?:boundary|case|failure|path)\b",
        comment,
    )
    if test_purpose:
        add(
            "test purpose",
            -10,
            "The comment identifies the behavior that the surrounding "
            "validation is meant to distinguish.",
        )

    if matches(r"\bby default\b", comment) and matches(r"\bbut\b", comment):
        add(
            "default and override",
            -8,
            "The comment distinguishes inherited default behavior from an explicit override.",
        )

    identifiers = (
        re.search(r"`[^`]+`", comment)
        or re.search(r"\b[A-Z][A-Za-z0-9]*[A-Z][A-Za-z0-9]*\b", comment)
        or re.search(r"\b[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_:0-9]*", comment)
        or re.search(r"\b[A-Za-z]+\+\+\b", comment)
        or re.search(r"\b0x[0-9A-Fa-f]+\b", comment)
    )
    if identifiers:
        add(
            "local identifiers",
            -10,
            "Named code or platform vocabulary ties the statement to this implementation.",
        )

    technical_terms = TECHNICAL_TERM.findall(comment)
    if len(technical_terms) >= 2:
        add(
            "concrete mechanism",
            -10,
            "Several implementation terms locate the claim in a specific mechanism.",
        )

    grounded_benefit = (
        generic_benefit
        and guarantees
        and identifiers
        and len(technical_terms) >= 2
    )
    if generic_benefit and not grounded_benefit:
        add(
            "generic benefit",
            8,
            "A broad benefit verb needs a concrete consequence to carry weight.",
        )

    conditional_boundary = matches(
        r"\bif\s+(?:the\s+)?(?:caller|consumer|provider|operation|binding|bind|API)\b"
        r"[^.]{0,100}\b(?:cannot|does not|fails?|refuses?|rejects?)\b",
        comment,
    )
    if conditional_boundary:
        add(
            "conditional boundary",
            -13,
            "The comment names the participant and condition that causes an operation to fail.",
        )

    checkable = matches(
        r"\b(?:RFC\s*\d+|AVX\d*|CUDA|Vulkan|C\+\+\d*|System V|"
        r"Win32|Wayland|MathML|KaTeX|TextMate)\b|\b\d+(?:\.\d+)?\b",
        comment,
    )
    if checkable:
        add(
            "checkable detail",
            -10,
            "A standard, platform or quantity makes the statement independently checkable.",
        )

    if matches(r"\b(?:is|are|was|were) borrowed\b", comment):
        add(
            "contract shorthand",
            25,
            "Passive ownership shorthand hides who guarantees access and when it ends.",
        )

    if matches(
        r"\b(?:frame|buffer|bytes|data|storage|view)\s+is borrowed until\b",
        comment,
    ):
        add(
            "borrowed data shorthand",
            20,
            "A data-bearing input uses borrowed as a loanword instead of "
            "naming access and the caller's lifetime obligation.",
        )

    if matches(r"\bborrowed lifetimes?\b", comment):
        add(
            "borrowed lifetime shorthand",
            20,
            "Borrowed names a project concept without stating who keeps each "
            "value available or when access ends.",
        )

    if matches(
        r"\b(?:has|have|is|are|was|were) (?:already )?"
        r"(?:established|handled|managed|ensured|provided)\b",
        comment,
    ):
        add(
            "unsupported assurance",
            10,
            "The prose asserts completed policy work without naming its observable result.",
        )

    abstract_terms = re.findall(
        r"\b(?:behavior|canonical|concerns?|configuration|description|details?|"
        r"form|geometry|invariants?|logic|normalization|requirements?|state|"
        r"structure)\b",
        comment,
        re.IGNORECASE,
    )
    if (
        len(words) >= 50
        and len(abstract_terms) >= 5
        and not guarantees
        and bullet_count == 0
    ):
        add(
            "abstract inventory",
            28,
            "A long inventory names abstractions without stating direct validity rules.",
        )

    if matches(
        r"^(?:contains?|holds?|stores?) all (?:of )?the\b",
        comment,
    ):
        add(
            "type narration",
            24,
            "The opening inventories a type instead of teaching its invariant or choice.",
            60,
        )

    if matches(
        r"\b(?:mini|just about|mostly fine|somehow|stuff|various things)\b",
        comment,
    ):
        add(
            "imprecise qualification",
            12,
            "Informal qualification leaves the technical extent unspecified.",
        )

    if matches(
        r"^(?:lane|row|column|branch|case|pass|phase)\s+\d+\s*"
        r"\(\s*same as (?:lane|row|column|branch|case|pass|phase)\s+\d+\s*\)$",
        comment,
    ):
        add(
            "duplicate label",
            25,
            "The comment names duplicated structure without explaining why it repeats.",
        )

    if bullet_count >= 2:
        add(
            "explicit inventory",
            -10,
            "A structured list makes several independently reviewable guarantees visible.",
        )

    ownership_terms = re.findall(
        r"\b(?:acquir(?:e|es|ed|ing)|answers?|bind(?:s|ing)?|"
        r"borrow(?:s|ed|ing)?|caller|keeps?|produces?|release(?:s|d|ing)?|"
        r"retain(?:s|ed|ing)?|state|storage)\b",
        comment,
        re.IGNORECASE,
    )
    domain_mechanism = matches(
        r"\b(?:ABI|callback|compile(?:s|d|ing)?|compiler|context|CUDA|"
        r"entry|execution|function|launch|module|native code|source)\b",
        comment,
    )
    if len(words) >= 30 and len(ownership_terms) >= 5 and not domain_mechanism:
        add(
            "ownership-only inventory",
            45,
            "The passage inventories lifetime plumbing without explaining the "
            "domain mechanism it preserves.",
        )

    mechanism_nouns = set(
        value.lower()
        for value in re.findall(
            r"\b(?:API|ABI|binding|buffer|bytes|callback|context|contract|"
            r"descriptor|frame|image|interface|label|layout|module|name|"
            r"policy|pool|result|role|sampler|set|shader|state|storage|view)\b",
            comment,
            re.IGNORECASE,
        )
    )
    sentence_count = len(re.findall(r"[.!?](?:\s|$)", comment))
    if (
        len(words) <= 40
        and sentence_count <= 2
        and len(mechanism_nouns) >= 5
        and not causal
        and not guarantees
        and not lifetime_relation
        and not tradeoff
        and not empirical
    ):
        add(
            "compressed mechanism",
            30,
            "Several interacting concepts are compressed into a claim without "
            "enough reasoning to connect them.",
        )

    substantive = any(
        (
            causal,
            bool(guarantees),
            lifetime_relation,
            tradeoff,
            empirical,
            bool(identifiers),
            len(technical_terms) >= 2,
            checkable,
            bullet_count >= 2,
            stated_benefit,
            test_purpose,
        )
    )
    if len(words) >= 10 and not structural_heading and not substantive:
        add(
            "unsupported description",
            15,
            "The prose describes behavior without a reason, guarantee, tradeoff "
            "or concrete mechanism.",
        )

    deictic_opener = matches(r"^(?:this|these|those|it)\b", comment)
    if (
        (len(words) <= 25 and deictic_opener)
        or (
            len(words) <= 15
            and matches(r"\b(?:this|these|those|it)\b", comment)
            and not causal
        )
    ):
        add(
            "unresolved reference",
            8,
            "A short comment points at nearby code without naming the relationship.",
        )

    if imperative and not causal:
        add(
            "imperative narration",
            35,
            "The comment directs or narrates the next statement without explaining its choice.",
        )

    if (
        grammar_comment[:1].islower()
        and not namespace_annotation
        and not structural_heading
    ):
        add(
            "unmarked identifier",
            25,
            "A lowercase code spelling begins the sentence without code marks, "
            "so it reads as a grammatical error.",
            40,
        )

    if re.search(r"[.!?]\s+[a-z][A-Za-z0-9_]*\b", grammar_comment):
        add(
            "unmarked sentence identifier",
            25,
            "A later sentence begins with a lowercase code spelling that is not marked as code.",
            40,
        )

    score = max(
        minimum_score,
        max(0, min(100, 45 + sum(signal.points for signal in signals))),
    )
    return Verdict(
        decision(score),
        score,
        ACCEPT_THRESHOLD,
        REJECT_THRESHOLD,
        comment,
        tuple(signals),
        minimum_score=minimum_score,
    )


def line_comment_marker(line):
    stripped = line.lstrip()
    if stripped.startswith("//"):
        return "//"
    if stripped.startswith("#") and not re.match(
        r"#\s*(?:define|elif|elifdef|elifndef|else|endif|error|if|ifdef|ifndef|"
        r"include|pragma|undef)\b",
        stripped,
    ):
        return "#"
    return None


def source_slice(path, line):
    """Extract one comment and the source paragraph to which it is attached."""
    source_path = Path(path)
    lines = source_path.read_text().splitlines()
    if line < 1 or line > len(lines):
        raise ValueError(f"{source_path}:{line}: line is outside the source file")
    index = line - 1
    marker = line_comment_marker(lines[index])
    if marker:
        begin = index
        while begin and line_comment_marker(lines[begin - 1]) == marker:
            begin -= 1
        end = index + 1
        while end < len(lines) and line_comment_marker(lines[end]) == marker:
            end += 1
        comment = "\n".join(lines[position] for position in range(begin, end))
    else:
        begin = index
        while begin >= 0 and "/*" not in lines[begin]:
            begin -= 1
        end = index
        while end < len(lines) and "*/" not in lines[end]:
            end += 1
        if begin < 0 or end == len(lines):
            raise ValueError(f"{source_path}:{line}: line does not belong to a comment")
        end += 1
        comment = "\n".join(lines[position] for position in range(begin, end))

    attached = end
    while attached < len(lines) and not lines[attached].strip():
        attached += 1
    attached_end = attached
    code_lines = 0
    while attached_end < len(lines) and code_lines < 16:
        current = lines[attached_end]
        if not current.strip() or line_comment_marker(current):
            break
        attached_end += 1
        code_lines += 1
    return SourceSlice(
        str(source_path),
        begin + 1,
        comment,
        attached + 1,
        "\n".join(lines[attached:attached_end]),
    )


def source_signals(context):
    """Find placement and coverage evidence unavailable from prose alone."""
    comment = normalize(context.comment)
    attached_lines = [line for line in context.attached.splitlines() if line.strip()]
    signals = []
    path = Path(context.path)
    path_words = {part.lower() for part in path.parts}
    technical_term_count = len(TECHNICAL_TERM.findall(comment))

    explicit_constructor = attached_explicit_constructor(context)
    if explicit_constructor and not explains_explicit_constructor(comment):
        signals.append(EXPLICIT_CONSTRUCTOR_SIGNAL)

    if (
        "validation" in path_words
        and len(WORD.findall(comment)) >= 8
        and (
            technical_term_count >= 2
            or matches(
                r"\b(?:boundary|cannot|different|empty|exact|fail(?:s|ed|ure)?|"
                r"independent|invalid|malformed|must|neither|only|optional|"
                r"either|dangling|destruction|discard(?:s|ed|ing)?|leak|"
                r"preserv(?:e|es|ed|ing)|refusal|reject(?:s|ed|ing)?|same|"
                r"unchanged|without)\b",
                comment,
            )
        )
    ):
        signals.append(
            Signal(
                "validation oracle",
                -12,
                "The comment identifies the distinction or failure boundary "
                "that the surrounding validation exercises.",
            )
        )

    declaration_contract = (
        path.suffix in {".h", ".hh", ".hpp", ".hxx"}
        and (
            technical_term_count >= 2
            or matches(
                r"\b(?:cannot|empty|fails?|invalid|must|preserv(?:e|es|ed|ing)|"
                r"returns?|stops?|until|when)\b",
                comment,
            )
        )
        and (
            ";" in context.attached
            or matches(r"\b(?:class|struct|enum|typedef)\b", context.attached)
        )
    )
    if declaration_contract:
        signals.append(
            Signal(
                "declaration contract",
                -10,
                "The comment states an observable boundary for the attached declaration.",
            )
        )

    function_declaration = re.search(
        r"\bauto\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        context.attached,
    )
    if function_declaration:
        function_name = function_declaration.group(1)
        self_references = re.findall(
            r"`(?:[A-Za-z_][A-Za-z0-9_]*::)*"
            + re.escape(function_name)
            + r"`",
            comment,
        )
        if self_references:
            signals.append(
                Signal(
                    "self referential function comment",
                    5 * len(self_references),
                    "The comment repeats the attached function's name even though "
                    "the declaration already supplies that context.",
                )
            )

        relocation_policy = (
            function_name == "relocate"
            and matches(r"\bdestination\b", context.attached)
            and matches(r"\bsource\b", context.attached)
        )
        if relocation_policy:
            names_both_locations = matches(r"`destination`", comment) and matches(
                r"`source`", comment
            )
            explains_lifetime_choice = matches(
                r"\b(?:allocation|Arena|block|capacity|lifetime|owner|release|"
                r"remit|reset|storage)\b",
                comment,
            )
            if not names_both_locations or not explains_lifetime_choice:
                signals.append(
                    Signal(
                        "incomplete relocation contract",
                        60,
                        "A relocation policy must name the destination storage, "
                        "the source value and the ownership or lifetime reason "
                        "for copying or moving between them.",
                    )
                )

            if matches(
                r"\bwhen that expression is valid\b|"
                r"\brejects? (?:constant source|rvalue|lvalue) construction\b|"
                r"\bconstructed from (?:the |an? )?(?:constant source|rvalue|lvalue)\b",
                comment,
            ):
                signals.append(
                    Signal(
                        "type trait narration",
                        45,
                        "The comment paraphrases constructibility dispatch instead "
                        "of explaining the policy invariant that requires it.",
                    )
                )

    container_name = path.stem.lower()
    if (
        "memory" in path_words
        and ("vector" in container_name or "bytes" in container_name)
        and matches(r"\belements?\b", comment)
    ):
        signals.append(
            Signal(
                "container value alias",
                45,
                "Vector and Bytes use value for contained items. Element adds a "
                "second identity for the same contract subject.",
            )
        )

    primary_declaration = re.search(
        r"\b(?:class|struct)\s+([A-Za-z_][A-Za-z0-9_]*)\b",
        context.attached,
    )
    primary_type_evidence = (
        len(WORD.findall(comment)) > 35
        or technical_term_count >= 2
        or matches(
            r"\b(?:because|cannot|lifetime|must|only|ownership|rather than|"
            r"requires?|since|until|valid|without)\b",
            comment,
        )
        or matches(
            r"`[^`]+`|\b[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_:0-9]*",
            comment,
        )
    )
    if (
        path.suffix == ".hpp"
        and primary_declaration
        and primary_declaration.group(1).lower() == path.stem.lower()
        and not primary_type_evidence
    ):
        signals.append(
            Signal(
                "thin primary type contract",
                25,
                "The header's primary type receives a short description without "
                "its model, contract boundary or reason for owning the abstraction.",
            )
        )

    primary_type = (
        path.suffix == ".hpp"
        and primary_declaration
        and primary_declaration.group(1).lower() == path.stem.lower()
    )
    comment_paragraphs = paragraphs(context.comment)
    opening = comment_paragraphs[0] if comment_paragraphs else comment
    if primary_type:
        type_name = primary_declaration.group(1)
        literal_opening = matches(
            r"^(?:(?:A|An|The)\s+)?"
            + re.escape(type_name)
            + r"\s+(?:is|owns|contains|holds|stores|wraps)\b",
            opening,
        )
        purpose = matches(
            r"\b(?:because|decouples?|exists to|lets?|allows?|rather than|"
            r"separates?|so that|therefore|unifies?|without duplicating)\b",
            opening,
        )
        named_variants = {
            name
            for name in re.findall(r"\b[A-Z][A-Za-z0-9_]*\b", opening)
            if name not in {"A", "An", "The", type_name}
        }
        implementation_inventory = (
            len(named_variants) >= 3
            and matches(
                r"\b(?:implementations?|polic(?:y|ies)|variants?)\b",
                opening,
            )
        )
        if literal_opening and implementation_inventory and not purpose:
            signals.append(
                Signal(
                    "implementation inventory before purpose",
                    70,
                    "The primary type opens with literal storage or role details "
                    "and implementation variants before explaining why the shared "
                    "abstraction exists.",
                )
            )

        policy_behavior_sentences = []
        policy_behavior_actors = set()
        for sentence in re.split(r"[.!?](?:\s|$)", comment):
            assignment = re.match(
                r"\s*(?P<actors>[A-Z][A-Za-z0-9_]*"
                r"(?:(?:,\s*|\s+and\s+|,\s+and\s+)"
                r"[A-Z][A-Za-z0-9_]*)*)"
                r"(?:\s+(?:policies|implementations|variants))?\s+"
                r"(?:allocates?|constructs?|defaults?|ends?|keeps?|owns?|"
                r"reclaims?|releases?|requires?|reserves?|retains?|supplies?|"
                r"uses?)\b",
                sentence,
            )
            if assignment:
                policy_behavior_sentences.append(sentence)
                policy_behavior_actors.update(
                    re.findall(
                        r"\b[A-Z][A-Za-z0-9_]*\b",
                        assignment.group("actors"),
                    )
                )
        if (
            matches(r"\b(?:policies|implementations|variants)\b", comment)
            and len(policy_behavior_sentences) >= 2
            and len(policy_behavior_actors) >= 2
        ):
            signals.append(
                Signal(
                    "foreign policy invariants",
                    70,
                    "The shared type assigns behavior to multiple named policies "
                    "instead of leaving each contract with its implementation.",
                )
            )

        destructor_suppression = matches(
            r"\b(?:does not|do not|never)\s+(?:call|invoke)\s+"
            r"(?:(?:individual|object|element)\s+)?destructors?\b|"
            r"\b(?:calls?|invokes?)\s+no\s+"
            r"(?:(?:individual|object|element)\s+)?destructors?\b|"
            r"\bwithout\s+(?:calling|invoking)\s+"
            r"(?:(?:individual|object|element)\s+)?destructors?\b|"
            r"\bno\s+(?:(?:individual|object|element)\s+)?destructors?\s+"
            r"(?:run|runs|are called)\b",
            comment,
        )
        invalidation_boundary = matches(
            r"\binvalidates?\b|\breset ends\b|"
            r"\baccess (?:ends?|promise|promises)\b|"
            r"\bno longer (?:accessible|available|valid)\b|"
            r"\bcannot (?:be )?(?:accessed|inspected|used)\b|"
            r"\buntil (?:the )?Arena resets\b|"
            r"\bpointers?\b[^.]{0,100}\buntil\b[^.]{0,50}\breset",
            comment,
        )
        resource_boundary = matches(
            r"\bindependently owned resources?\b|"
            r"\b(?:objects?|values?) owned by the same Arena\b|"
            r"\bstate governed by the same Arena\b",
            comment,
        )
        if destructor_suppression and not invalidation_boundary:
            signals.append(
                Signal(
                    "destructor suppression without invalidation",
                    55,
                    "A bulk lifetime contract skips destructors without naming "
                    "when existing pointers and references lose access.",
                )
            )
        if destructor_suppression and not resource_boundary:
            signals.append(
                Signal(
                    "destructor suppression without resource boundary",
                    55,
                    "A bulk lifetime contract skips destructors without ruling "
                    "out resources that require individual cleanup.",
                )
            )

    method_inventory = re.findall(
        r"`[^`]+`\s+(?:adds?|creates?|gets?|performs?|reads?|removes?|"
        r"returns?|selects?|writes?)\b",
        comment,
        re.IGNORECASE,
    )
    if primary_type and len(method_inventory) >= 2:
        signals.append(
            Signal(
                "primary type method inventory",
                60,
                "The primary type comment enumerates current methods instead "
                "of defining which responsibilities belong to the abstraction.",
            )
        )

    if primary_type and matches(
        r"\boperation belongs here\b|\bbelong elsewhere\b",
        comment,
    ):
        signals.append(
            Signal(
                "meta abstraction instruction",
                25,
                "The comment tells maintainers what belongs in the type instead "
                "of making that boundary evident from the type's model.",
            )
        )

    numbers = {
        "zero": "0",
        "one": "1",
        "two": "2",
        "three": "3",
        "four": "4",
    }
    for term in ("binding", "column", "index", "lane", "location", "offset", "row", "slot"):
        if not matches(r"\b" + term + r"\b", comment):
            continue
        values = [
            value
            for word, value in numbers.items()
            if matches(r"\b" + word + r"\b", comment)
        ]
        values.extend(re.findall(r"\b\d+\b", comment))
        for position, code in enumerate(attached_lines):
            separated = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", code).lower()
            if term in separated and (not values or any(value in code for value in values)):
                if position >= 3 and not declaration_contract:
                    signals.append(
                        Signal(
                            "distant code anchor",
                            20,
                            f"The {term} claim first reaches matching code "
                            f"{position + 1} statements after the comment.",
                        )
                    )
                break

    operations = sum(
        bool(
            re.search(r"(?<![=!<>])=(?!=)", line)
            or re.search(r"\b(?:if|for|while|switch)\s*\(", line)
            or re.search(r"\b[A-Za-z_][A-Za-z0-9_:]*\s*\(", line)
        )
        for line in attached_lines
    )
    if (
        operations >= 6
        and path.name not in {"BUILD", "BUILD.bazel"}
        and len(WORD.findall(comment)) <= 35
        and not matches(
            r"\b(?:because|before|cannot|must|only if|rather than|since|so|"
            r"therefore|until|while|without)\b",
            comment,
        )
        and not matches(
            r"\b(?:caller|lifetime|owns?|preserv(?:e|es|ed|ing)|"
            r"retain(?:s|ed|ing)?|release(?:s|d|ing)?|version\s+\w+)\b",
            comment,
        )
    ):
        signals.append(
            Signal(
                "underexplained source paragraph",
                15,
                f"The attached paragraph performs {operations} operations "
                "without a corresponding reason or boundary.",
            )
        )

    declaration = re.search(
        r"\b(?:class|struct)\s+(Program|Kernel|Buffer|Context|Image|Module|Runtime)\b",
        context.attached,
    )
    domains = path_words.intersection({"cuda", "godot", "vulkan", "wayland", "win32"})
    if declaration and domains and not any(
        matches(r"\b" + re.escape(domain) + r"\b", comment) for domain in domains
    ):
        domain = sorted(domains)[0]
        signals.append(
            Signal(
                "missing domain anchor",
                20,
                f"The generic {declaration.group(1)} declaration belongs to "
                f"{domain}, but its comment never explains that domain relationship.",
            )
        )

    if (
        matches(r"\bbound Abstract\b", comment)
        and "ttx_binding_status" in context.attached
        and "ttx_storage" in context.attached
        and "ttx_abstract" not in context.attached
    ):
        signals.append(
            Signal(
                "misnamed binding result",
                20,
                "The operation fills requested storage with an arbitrary API "
                "record, but the comment calls that result an Abstract.",
            )
        )
    return signals


def attached_explicit_constructor(context):
    """Find the explicit constructor directly governed by one comment block."""
    match = EXPLICIT_CONSTRUCTOR.search(context.attached)
    if not match or not EXPLICIT_PREFIX.fullmatch(context.attached[: match.start()]):
        return None
    return context.attached_line + context.attached[: match.start()].count("\n")


def explains_explicit_constructor(comment):
    """Recognize a comment that states the constructor's conversion boundary."""
    if matches(
        r"\b(?:call site|construct(?:ion|or) syntax|convert(?:ed|ing|s)?|"
        r"conversion|implicit(?:ly)?)\b",
        comment,
    ):
        return True
    return matches(r"\bexplicit construction\b", comment) and matches(
        r"\b(?:distinguishes?|exposes?|keeps?|makes?|prevents?|requires?)\b",
        comment,
    )


def explicit_constructor_lines(source, code):
    """Locate every explicit constructor while strings and comments are masked."""
    return tuple(
        source.count("\n", 0, match.start()) + 1
        for match in EXPLICIT_CONSTRUCTOR.finditer(code)
    )


def policy_extension_signals(context, code):
    """Require an open CRTP capability to publish every invoked policy hook."""
    if not code or "policy_type" not in context.attached:
        return []
    if not re.search(
        r"\b(?:class|struct)\s+[A-Za-z_][A-Za-z0-9_]*",
        context.attached,
    ):
        return []

    hooks = sorted(set(POLICY_HOOK_CALL.findall(code)))
    if len(hooks) < 2:
        return []

    contract_lines = []
    for line in context.comment.splitlines():
        marked = re.match(r"^\s*(?://|#)(.*)$", line)
        contract_lines.append(marked.group(1) if marked else line)
    signature_lines = {}
    for hook in hooks:
        for index, line in enumerate(contract_lines):
            if re.match(
                r"^ {2}auto\s+" + re.escape(hook) + r"\s*\(",
                line,
            ):
                signature_lines[hook] = index
                break

    missing = [hook for hook in hooks if hook not in signature_lines]
    undocumented = []
    for hook, index in signature_lines.items():
        description = index + 1
        while description < len(contract_lines) and not normalize(
            contract_lines[description]
        ):
            description += 1

        description_lines = []
        while description < len(contract_lines) and normalize(
            contract_lines[description]
        ):
            description_lines.append(contract_lines[description])
            description += 1

        if (
            not description_lines
            or any(
                re.match(r"^ {4}\S", line) is None
                for line in description_lines
            )
            or len(WORD.findall(normalize("\n".join(description_lines)))) < 5
        ):
            undocumented.append(hook)
    if not missing and not undocumented:
        return []

    failures = []
    if missing:
        names = ", ".join(f"`{hook}`" for hook in missing)
        failures.append(f"missing signatures for {names}")
    if undocumented:
        names = ", ".join(f"`{hook}`" for hook in undocumented)
        failures.append(f"missing local invariants for {names}")
    return [
        Signal(
            "incomplete policy extension contract",
            65,
            "The capability's primary contract has " + " and ".join(failures) + ".",
        ),
    ]


def classify_file(path, line):
    source = Path(path).read_text()
    context = source_slice(path, line)
    base = classify(context.comment)
    return source_verdict(
        base,
        context,
        source_signals(context) + policy_extension_signals(context, source),
    )


def source_contexts(path, source, comments):
    """Join line comments and attach each block to its source paragraph."""
    blocks = []
    for start, end, comment in comments:
        marker = source[start : start + 2]
        if blocks:
            (
                previous_start,
                previous_end,
                previous_comment,
                previous_marker,
            ) = blocks[-1]
            between = source[previous_end:start]
            if (
                marker == "//"
                and previous_marker == "//"
                and between.count("\n") == 1
                and not between.strip()
            ):
                blocks[-1] = (
                    previous_start,
                    end,
                    previous_comment + "\n" + comment,
                    marker,
                )
                continue
        blocks.append((start, end, comment, marker))

    lines = source.splitlines()
    contexts = []
    for start, end, comment, _ in blocks:
        if not normalize(comment):
            continue
        attached = source.count("\n", 0, end) + 1
        while attached < len(lines) and not lines[attached].strip():
            attached += 1
        attached_end = attached
        code_lines = 0
        while attached_end < len(lines) and code_lines < 16:
            current = lines[attached_end]
            if (
                not current.strip()
                or line_comment_marker(current)
                or current.lstrip().startswith("/*")
            ):
                break
            attached_end += 1
            code_lines += 1
        contexts.append(
            SourceSlice(
                str(path),
                source.count("\n", 0, start) + 1,
                comment,
                attached + 1,
                "\n".join(lines[attached:attached_end]),
            )
        )
    return tuple(contexts)


def classify_comments(path, source, comments, code=None):
    """Classify every authored comment block in one C or C++ source file."""
    contexts = source_contexts(path, source, comments)
    verdicts = []
    covered_constructors = set()
    for context in contexts:
        base = classify(context.comment)
        constructor = attached_explicit_constructor(context)
        if constructor:
            covered_constructors.add(constructor)
        extra = source_signals(context)
        if code is not None:
            extra += policy_extension_signals(context, code)
        verdicts.append(source_verdict(base, context, extra))
    if code is not None:
        for line in explicit_constructor_lines(source, code):
            if line in covered_constructors:
                continue
            context = SourceSlice(str(path), line, "", line, "")
            verdicts.append(
                source_verdict(
                    classify(""),
                    context,
                    (EXPLICIT_CONSTRUCTOR_SIGNAL,),
                )
            )
    return tuple(sorted(verdicts, key=lambda verdict: verdict.line or 0))


def diagnostic(verdict):
    """Render one source finding for the repository formatter."""
    signals = list(
        dict.fromkeys(
            signal.name for signal in verdict.signals if signal.points > 0
        )
    )
    basis = ", ".join(signals) if signals else "baseline requires review"
    severity = "error" if verdict.decision == "Reject" else "warning"
    return (
        f"{verdict.path}:{verdict.line}: {severity}: comment quality "
        f"{verdict.decision} "
        f"({verdict.score}/100): {basis}"
    )


def summary(verdicts):
    """Render aggregate status for one formatter source selection."""
    counts = {"Accept": 0, "Warn": 0, "Reject": 0}
    total_score = 0
    for verdict in verdicts:
        counts[verdict.decision] += 1
        total_score += verdict.score
    scanned = len(verdicts)
    mean = total_score / scanned if scanned else 0.0
    return "\n".join(
        [
            "Comment quality:",
            f"  Scanned: {scanned}",
            f"  Approved: {counts['Accept']}",
            f"  Warning: {counts['Warn']}",
            f"  Rejected: {counts['Reject']}",
            f"  Mean comment score: {mean:.2f}/100",
        ]
    )


def render(verdict):
    lines = [f"{verdict.decision} (AI Slop {verdict.score}/100)"]
    if verdict.signals:
        lines.append("Signals:")
        for signal in verdict.signals:
            sign = "+" if signal.points > 0 else ""
            lines.append(
                f"  {sign}{signal.points}: {signal.name}. {signal.explanation}"
            )
    else:
        lines.append("Signals: no strong style evidence; the score remains uncertain.")
    lines.append("Quality decision only; authorship is not inferred.")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Rate comment prose for generic AI-slop characteristics."
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="write the complete verdict as JSON",
    )
    parser.add_argument("--source", help="source file containing the comment")
    parser.add_argument("--line", type=int, help="one-based line inside the comment")
    parser.add_argument(
        "comment",
        nargs="*",
        help="comment text; standard input is used when omitted",
    )
    arguments = parser.parse_args()
    if arguments.source:
        if arguments.line is None:
            parser.error("--source requires --line")
        if arguments.comment:
            parser.error("comment text cannot accompany --source")
        try:
            verdict = classify_file(arguments.source, arguments.line)
        except (OSError, ValueError) as error:
            parser.error(str(error))
    else:
        if arguments.line is not None:
            parser.error("--line requires --source")
        source = " ".join(arguments.comment) if arguments.comment else sys.stdin.read()
        if not source.strip():
            parser.error("comment text is empty")
        verdict = classify(source)
    if arguments.json:
        print(json.dumps(asdict(verdict), indent=2))
    else:
        print(render(verdict))
    return 0


if __name__ == "__main__":
    sys.exit(main())
