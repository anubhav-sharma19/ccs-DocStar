"""Print run_eval.py's table for Dart predictions, plus verified-but-wrong.

    python3 tool/eval_pred.py <reference-root> <corpus-dir> <pred-dir>

run_eval imports the pdfplumber-based engine at module level; scoring predictions never calls it, so it is stubbed.
"""
import json
import sys
import types
from pathlib import Path

root, corpus, preds = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
sys.modules["pdfplumber"] = types.ModuleType("pdfplumber")
sys.path.insert(0, str(root / "eval"))
import run_eval  # noqa: E402

run_eval.main([str(corpus), "--pred-dir", str(preds)])
strict = money = 0
for f in sorted(corpus.glob("*.pdf")):
    sc = run_eval.score_doc(json.loads((preds / f"{f.stem}.pred.json").read_text()), json.loads(f.with_suffix(".json").read_text()))
    if sc["status"] == "verified" and not sc["perfect"]:
        strict += 1  # anything imperfect, narration included
        money += not (sc["matched"] == sc["gt"] == sc["pred"] and sc["bal_ok"] == sc["bal_n"])  # dates/amounts/balances wrong
        print(f"  verified but imperfect: {f.name} {sc['errs'][:1]}")
print(f"verified_but_wrong: money (README definition) = {money}, strict incl. narration = {strict}")
