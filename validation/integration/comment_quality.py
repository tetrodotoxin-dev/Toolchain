# Copyright (c) 2023-present Matt Kaes and contributors

"""Keep the reviewed comment corpus reproducible as the classifier changes."""

from collections import Counter
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

from python.runfiles import runfiles


if __name__ == "__main__":
    resolver = runfiles.Create()
    classifier_path = Path(resolver.Rlocation(sys.argv[1]))
    corpus_path = Path(resolver.Rlocation(sys.argv[2]))
    specification = importlib.util.spec_from_file_location(
        "comment_quality", classifier_path
    )
    classifier = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = classifier
    specification.loader.exec_module(classifier)
    assert classifier.line_comment_marker("#elifdef TOOLCHAIN_LINUX") is None
    assert classifier.line_comment_marker("#elifndef TOOLCHAIN_WINDOWS") is None
    markdown_link = classifier.classify(
        "[Photophore](https://github.com/tetrodotoxin-dev/Photophore)"
    )
    assert "hyphenated prose" not in {
        signal.name for signal in markdown_link.signals
    }
    license_header = classifier.classify(
        "# Tetrodotoxin\n"
        "# Copyright (c) 2023-present Matt Kaes and contributors"
    )
    assert license_header.decision == "Accept", license_header
    assert license_header.score == 0, license_header
    assert {signal.name for signal in license_header.signals} == {
        "license metadata"
    }, license_header
    copyright_prose = classifier.classify(
        "The parser treats Copyright (c) as ordinary payload text."
    )
    assert "license metadata" not in {
        signal.name for signal in copyright_prose.signals
    }, copyright_prose
    for prohibited in classifier.PROHIBITED_ALIAS_WORDS:
        verdict = classifier.classify(
            f"The operation uses {prohibited} as its result."
        )
        assert verdict.decision == "Reject", (prohibited, verdict)
        assert "prohibited alias word" in {
            signal.name for signal in verdict.signals
        }, (prohibited, verdict)
    for identifier in ("admission_result", "AdmissionResult"):
        verdict = classifier.classify(
            f"The operation returns `{identifier}`."
        )
        assert verdict.decision == "Reject", (identifier, verdict)
        assert "prohibited alias word" in {
            signal.name for signal in verdict.signals
        }, (identifier, verdict)

    corpus = [
        json.loads(line)
        for line in corpus_path.read_text().splitlines()
        if line.strip()
    ]

    def suite(name):
        return [sample for sample in corpus if sample["suite"] == name]

    examples = suite("examples")
    feedback = {
        sample["id"]: sample for sample in suite("feedback")
    }
    revisions = suite("revisions")
    holdout = suite("holdout")
    holdout_feedback = {
        sample["id"]: sample for sample in suite("holdout_feedback")
    }
    edited = suite("edited")
    source_context = suite("source_context")
    source_holdout = suite("source_holdout")
    correction = suite("correction")
    adversarial = suite("adversarial")
    punctuation = suite("punctuation")
    ownership = suite("ownership")
    assert len(corpus) == 173
    assert len(examples) == 24
    assert len(feedback) == 14
    assert len(revisions) == 1
    assert len(holdout) == 24
    assert len(holdout_feedback) == 17
    assert len(edited) == 10
    assert len(source_context) == 36
    assert len(source_holdout) == 24
    assert len(correction) == 2
    assert len(adversarial) == 13
    assert len(punctuation) == 2
    assert len(ownership) == 6
    assert Counter(sample["repository"] for sample in source_holdout) == Counter(
        {
            "cuda": 3,
            "godot": 3,
            "perimortem": 3,
            "photophore": 3,
            "tetrodotoxin": 3,
            "toolchain": 3,
            "ttx": 3,
            "website": 3,
        }
    )
    assert Counter(sample["repository"] for sample in holdout) == Counter(
        {
            "cuda": 3,
            "godot": 3,
            "perimortem": 3,
            "photophore": 3,
            "tetrodotoxin": 3,
            "toolchain": 3,
            "ttx": 3,
            "website": 3,
        }
    )
    assert Counter(example["repository"] for example in examples) == Counter(
        {
            "cuda": 3,
            "godot": 3,
            "perimortem": 3,
            "photophore": 3,
            "tetrodotoxin": 3,
            "toolchain": 3,
            "ttx": 3,
            "website": 3,
        }
    )

    verdicts = {}
    for example in examples:
        verdict = classifier.classify(example["comment"])
        review = feedback.get(example["id"])
        if review:
            assert verdict.decision == review["decision"], (example["id"], verdict)
        elif example["expected"] == "AI Slop":
            assert verdict.decision == "Reject", (example["id"], verdict)
        else:
            assert verdict.decision != "Reject", (example["id"], verdict)
        if review and "score_min" in review:
            assert review["score_min"] <= verdict.score <= review["score_max"], (
                example["id"],
                verdict,
            )
        assert classifier.classify(example["comment"]) == verdict
        marked = "// " + example["comment"].replace("\n", "\n// ")
        assert classifier.classify(marked) == verdict
        verdicts[example["id"]] = verdict

    for revision in revisions:
        verdict = classifier.classify(revision["comment"])
        assert verdict.decision == revision["decision"], (revision["id"], verdict)
        assert verdict.score < verdicts[revision["compare_to"]].score

    for sample in holdout:
        verdict = classifier.classify(sample["comment"])
        review = holdout_feedback.get(sample["id"])
        if review:
            assert verdict.decision == review["decision"], (sample["id"], verdict)
            if "score_min" in review:
                assert review["score_min"] <= verdict.score <= review["score_max"], (
                    sample["id"],
                    verdict,
                )
        elif sample["decision"] == "Reject":
            assert verdict.decision == "Reject", (sample["id"], verdict)
        else:
            assert verdict.decision != "Reject", (sample["id"], verdict)
        assert classifier.classify(sample["comment"]) == verdict
        verdicts[sample["id"]] = verdict

    for revision in edited:
        verdict = classifier.classify(revision["comment"])
        assert verdict.decision == revision["decision"], (revision["id"], verdict)
        if "compare_to" in revision:
            prior = verdicts[revision["compare_to"]].score
            if revision["comparison"] == "lower":
                assert verdict.score < prior, (revision["id"], prior, verdict)
            else:
                assert verdict.score == prior, (revision["id"], prior, verdict)

    with tempfile.TemporaryDirectory(prefix="comment-quality-") as temporary:
        temporary_root = Path(temporary)
        source_context_verdicts = {}
        for case in source_context:
            path = temporary_root / case["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(case["source"])
            verdict = classifier.classify_file(path, case["line"])
            assert verdict.decision == case["decision"], (case["id"], verdict)
            names = {signal.name for signal in verdict.signals}
            assert names.issuperset(case.get("signals", [])), (case["id"], verdict)
            assert names.isdisjoint(case.get("absent_signals", [])), (
                case["id"],
                verdict,
            )
            if "score_min" in case:
                assert case["score_min"] <= verdict.score <= case["score_max"], (
                    case["id"],
                    verdict,
                )
            if "compare_to" in case:
                prior = source_context_verdicts[case["compare_to"]].score
                assert verdict.score < prior, (case["id"], prior, verdict)
            source_context_verdicts[case["id"]] = verdict

    for sample in source_holdout:
        context = classifier.SourceSlice(
            sample["path"],
            sample["line"],
            sample["comment"],
            sample["attached_line"],
            sample["attached"],
        )
        base = classifier.classify(sample["comment"])
        verdict = classifier.source_verdict(
            base,
            context,
            classifier.source_signals(context),
        )
        assert verdict.decision == sample["decision"], (sample["id"], verdict)
        assert classifier.source_verdict(
            base,
            context,
            classifier.source_signals(context),
        ) == verdict

    correction_verdicts = {}
    for sample in correction:
        verdict = classifier.classify(sample["comment"])
        assert verdict.decision == sample["decision"], (sample["id"], verdict)
        marked = "// " + sample["comment"].replace("\n", "\n// ")
        assert classifier.classify(marked) == verdict
        if "score_min" in sample:
            assert verdict.score >= sample["score_min"], (sample["id"], verdict)
        if "score_max" in sample:
            assert verdict.score <= sample["score_max"], (sample["id"], verdict)
        if "compare_to" in sample:
            assert verdict.score < correction_verdicts[sample["compare_to"]].score
        correction_verdicts[sample["id"]] = verdict

    bad = next(sample for sample in adversarial if sample["stage"] == "bad")
    repaired = next(
        sample for sample in adversarial if sample["stage"] == "clean"
    )
    mutations = [
        sample for sample in adversarial if sample["stage"] == "mutation"
    ]

    adversarial_by_id = {sample["id"]: sample for sample in adversarial}

    def adversarial_comment(sample):
        if "comment" in sample:
            return sample["comment"]
        source = adversarial_by_id[sample["base"]]["comment"]
        assert source.count(sample["replace"]) == 1, sample["id"]
        return source.replace(sample["replace"], sample["with"])

    bad_verdict = classifier.classify(adversarial_comment(bad))
    assert bad_verdict.decision == "Reject", (bad["id"], bad_verdict)
    assert bad_verdict.score >= bad["score_min"], (bad["id"], bad_verdict)

    repaired_verdict = classifier.classify(adversarial_comment(repaired))
    assert repaired_verdict.decision == "Accept", (
        repaired["id"],
        repaired_verdict,
    )
    assert (
        repaired["score_min"]
        <= repaired_verdict.score
        <= repaired["score_max"]
    ), (repaired["id"], repaired_verdict)

    canonicals = [
        sample for sample in correction + adversarial if sample.get("canonical")
    ]
    assert {sample["id"] for sample in canonicals} == {
        "ttx-supports-direct",
        "ttx-bind-direct",
        "ttx-binding-status-canonical",
        "ttx-query-contract-canonical",
    }
    for sample in canonicals:
        verdict = classifier.classify(adversarial_comment(sample))
        assert verdict.decision == "Accept", (sample["id"], verdict)
        assert sample["score_min"] <= verdict.score <= sample["score_max"], (
            sample["id"],
            verdict,
        )

    for sample in mutations:
        verdict = classifier.classify(adversarial_comment(sample))
        assert verdict.decision == "Reject", (sample["id"], verdict)
        assert verdict.score >= sample["score_min"], (sample["id"], verdict)
        assert verdict.score > repaired_verdict.score, (sample["id"], verdict)

    ownership_verdicts = {}
    for sample in ownership:
        verdict = classifier.classify(sample["comment"])
        assert verdict.decision == sample["decision"], (sample["id"], verdict)
        marked = "// " + sample["comment"].replace("\n", "\n// ")
        assert classifier.classify(marked) == verdict
        if "score_min" in sample:
            assert verdict.score >= sample["score_min"], (sample["id"], verdict)
        names = {signal.name for signal in verdict.signals}
        assert names.issuperset(sample.get("signals", [])), (sample["id"], verdict)
        assert names.isdisjoint(sample.get("absent_signals", [])), (
            sample["id"],
            verdict,
        )
        if "compare_to" in sample:
            assert verdict.score < ownership_verdicts[sample["compare_to"]].score
        ownership_verdicts[sample["id"]] = verdict

    punctuation_verdicts = {}
    for sample in punctuation:
        verdict = classifier.classify(sample["comment"])
        assert verdict.decision == sample["decision"], (sample["id"], verdict)
        assert sample["score_min"] <= verdict.score <= sample["score_max"], (
            sample["id"],
            verdict,
        )
        names = {signal.name for signal in verdict.signals}
        assert names.issuperset(sample.get("signals", [])), (sample["id"], verdict)
        assert names.isdisjoint(sample.get("absent_signals", [])), (
            sample["id"],
            verdict,
        )

        context = classifier.SourceSlice(
            "source/perimortem/memory/dynamic/vector.hpp",
            1,
            sample["comment"],
            sample["attached_line"],
            sample["attached"],
        )
        source_verdict = classifier.source_verdict(
            verdict,
            context,
            classifier.source_signals(context),
        )
        assert source_verdict.decision == sample["source_decision"], (
            sample["id"],
            source_verdict,
        )
        assert (
            sample["source_score_min"]
            <= source_verdict.score
            <= sample["source_score_max"]
        ), (sample["id"], source_verdict)

        if "compare_to" in sample:
            assert verdict.score < punctuation_verdicts[sample["compare_to"]].score
        punctuation_verdicts[sample["id"]] = verdict
