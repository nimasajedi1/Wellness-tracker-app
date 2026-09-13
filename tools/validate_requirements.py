#!/usr/bin/env python3
"""Validate this requirements pack, NOT the application or a language model.

Uses only the Python standard library. Reports structural integrity and selected
fixture arithmetic. It does not compile Swift, call a model, fetch live sources,
or turn any requirement/test scenario into a passed application test.
"""
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQ_PATTERN = re.compile(r'^\*\*([A-Z][A-Z0-9]*-\d{3}) \[([^\]]+)\]', re.M)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', action='store_true', help='Write docs/VALIDATION_REPORT.md')
    args = parser.parse_args()
    results: list[tuple[str, bool, str]] = []

    def check(name: str, ok: bool, detail: str = '') -> None:
        results.append((name, bool(ok), detail))

    required = [
        'README.md', 'AGENTS.md', 'docs/PRD.md', 'docs/IMPLEMENTATION_PLAN.md',
        'docs/LEGACY_BASELINE.md', 'docs/ACCEPTANCE_MATRIX.md',
        'fixtures/catalog_fixtures.json', 'fixtures/evaluation_cases.json',
        'fixtures/owner_template_example.json',
    ]
    for relative in required:
        check(f'File exists: {relative}', (ROOT / relative).is_file())
    if any(not ok for _, ok, _ in results):
        for name, ok, _ in results:
            print(('PASS ' if ok else 'FAIL ') + name)
        return 1

    prd = (ROOT / 'docs/PRD.md').read_text(encoding='utf-8')
    ids = [m[0] for m in REQ_PATTERN.findall(prd)]
    id_set = set(ids)
    check('Unique requirement IDs', len(ids) == len(id_set), f'{len(ids)} requirements')
    headings = [int(x) for x in re.findall(r'^## (\d+)\.', prd, re.M)]
    check('Complete numbered PRD sections', headings == list(range(1, 24)), f'{len(headings)} sections')
    matrix = (ROOT / 'docs/ACCEPTANCE_MATRIX.md').read_text(encoding='utf-8')
    matrix_ids = re.findall(r'^\| ([A-Z][A-Z0-9]*-\d{3}) \|', matrix, re.M)
    check('Acceptance matrix covers each requirement once', set(matrix_ids) == id_set and len(matrix_ids) == len(id_set))

    for md in sorted(ROOT.rglob('*.md')):
        if md.name == 'VALIDATION_REPORT.md':
            continue
        content = md.read_text(encoding='utf-8')
        fences = [line for line in content.splitlines() if line.startswith('```')]
        check(f'Balanced Markdown fences: {md.relative_to(ROOT)}', len(fences) % 2 == 0)

    parsed: dict[str, object] = {}
    for file in sorted((ROOT / 'fixtures').glob('*.json')):
        try:
            parsed[file.name] = json.loads(file.read_text(encoding='utf-8'))
            check(f'JSON parses: {file.name}', True)
        except (OSError, json.JSONDecodeError) as exc:
            check(f'JSON parses: {file.name}', False, str(exc))
    if len(parsed) != 3:
        for name, ok, detail in results:
            print(('PASS ' if ok else 'FAIL ') + name + (': ' + detail if detail else ''))
        return 1

    catalog = parsed['catalog_fixtures.json']
    suite = parsed['evaluation_cases.json']
    template = parsed['owner_template_example.json']
    foods = catalog['records']
    cases = suite['cases']
    check('Fixture catalog excluded from production', catalog.get('productionUseAllowed') is False)
    check('Unique food fixture IDs', len({f['foodID'] for f in foods}) == len(foods), f'{len(foods)} records')
    check('Every fixture has explicit source type', all(f['evidence']['type'] in {'syntheticFixture','labelTranscription'} for f in foods))
    check('Nutrient fixtures are nonnegative or unknown', all(v is None or (isinstance(v, (int,float)) and v >= 0) for f in foods for v in f['nutrients'].values()))
    check('Serving fixture bases positive', all(f['basis']['amount'] > 0 for f in foods))
    case_ids = [c['id'] for c in cases]
    check('Unique evaluation case IDs', len(set(case_ids)) == len(case_ids), f'{len(cases)} scenarios')
    regressions = set(re.findall(r'^\| (REG-\d{3}) \|', prd, re.M))
    case_regs = [c['regressionID'] for c in cases]
    check('Every PRD regression has one seed case', set(case_regs) == regressions and len(case_regs) == len(regressions))
    check('All case requirement references resolve', all(r in id_set for c in cases for r in c['requirements']))
    check('Seed app/model cases remain NOT RUN', all(c['executionStatus'] == 'notRun' for c in cases))
    check('Seed not falsely labeled held-out benchmark', all(c['split'] == 'developmentSeed' for c in cases))
    check('Seed scenarios include setup/input/expected', all(isinstance(c.get(k), dict) for c in cases for k in ('initialState','input','expected')))

    section = prd.split('### 22.1 Configuration shape',1)[1].split('### 22.2',1)[0]
    embedded_template = json.loads(re.search(r'```json\n(.*?)\n```', section, re.S).group(1))
    check('Template fixture equals PRD example', embedded_template == template)
    metric_ids = {m['id'] for m in template['metrics']}
    check('Example layout references valid metrics', all(mid in metric_ids for card in template['layout'] for mid in card['metricIDs']))
    p = next(m for m in template['metrics'] if m['id'] == 'nutrition.protein')
    w = next(m for m in template['metrics'] if m['id'] == 'hydration.water')
    check('Protein exact green threshold retained in example', p['goal']['metMinimum'] == 130)
    check('Water exact green threshold retained in example', w['goal']['metMinimum'] == 2000)

    # Arithmetic consistency is of seed expectations, not application code.
    def d(value: object) -> Decimal:
        return Decimal(str(value))

    food_map = {f['foodID']: f for f in foods}
    for case in cases:
        if case['kind'] != 'arithmetic':
            continue
        action, state, expected = case['input'], case['initialState'], case['expected']
        op = action['operation']
        actual: dict[str, Decimal] = {}
        if op == 'scaleFood':
            f = food_map[action['foodID']]
            mass = d(action['amount']) * (Decimal('28.349523125') if action['unit'] == 'oz' else Decimal(1))
            factor = mass / d(f['basis']['amount'])
            actual = {'mass_g':mass, **{k:d(v)*factor for k,v in f['nutrients'].items() if v is not None}}
        elif op == 'restingEnergy':
            actual = {'energy_kcal':d(10)*d(action['weightKg']) + d('6.25')*d(action['heightCm']) - d(5)*d(action['ageYears']) + d(action['equationConstant'])}
        elif op == 'duration':
            delta = datetime.fromisoformat(action['end']) - datetime.fromisoformat(action['start'])
            actual = {'minutes':d(delta.total_seconds()) / d(60)}
        elif op == 'recipePortion':
            actual = {'energy_kcal':d(state['batchEnergy_kcal'])*d(action['portionMass_g'])/d(state['finishedBatchMass_g'])}
        elif op == 'adjustThenAdd':
            actual = {'adjustment_g':d(action['setTotal_g'])-d(state['protein_g']), 'finalProtein_g':d(action['setTotal_g'])+d(action['newFoodProtein_g']), 'afterRemovingNewFood_g':d(action['setTotal_g'])}
        else:
            check(f'Known arithmetic operation: {case["id"]}', False, op)
            continue
        matches = all(k in actual and abs(actual[k]-d(v)) <= Decimal('0.0000001') for k,v in expected.items())
        check(f'Fixture arithmetic consistent: {case["id"]}', matches)

    # Bibliography identifiers required by the authoritative PRD.
    refs = {x for x in re.findall(r'^- \*\*\[([SLU]\d{2})\]', prd, re.M)}
    expected_refs = {f'S{i:02d}' for i in range(1,21)} | {'L01','U01','U02','U03'}
    check('Implementation/project bibliography complete', expected_refs <= refs, f'{len(refs)} reference IDs')
    check('AGENTS remains concise', (ROOT/'AGENTS.md').stat().st_size < 12000, f'{(ROOT/"AGENTS.md").stat().st_size} bytes')

    failures = sum(not ok for _,ok,_ in results)
    for name, ok, detail in results:
        print(('PASS ' if ok else 'FAIL ') + name + (': ' + detail if detail else ''))
    print(f'\nPack checks: {len(results)-failures}/{len(results)} passed.')
    print('Application builds, model evaluations, live-source tests, and device benchmarks: NOT RUN.')
    if args.report:
        rows = '\n'.join(f'| {name} | {"Pass" if ok else "Fail"} | {detail or "-"} |' for name,ok,detail in results)
        report = f'''# Requirements-pack validation report

**Scope:** document structure, cross-references, JSON fixtures, and selected fixture arithmetic only.

**Command:** `python tools/validate_requirements.py --report`

**Result:** {len(results)-failures} of {len(results)} pack-consistency checks passed.

## What was NOT tested

- Swift/Xcode compilation or signing.
- Installation or inference on an iPhone 16e.
- Any Apple model, prompt accuracy, or measured device latency.
- Live restaurant/brand source availability or production nutrition correctness.
- Implemented app acceptance criteria, UI accessibility, or HealthKit behavior.

All {len(cases)} seed application/model scenarios remain **not run**, and all {len(ids)} requirements remain **not implemented / not run** in the acceptance matrix. A consistent specification is not a completed application.

## Pack checks

| Check | Result | Detail |
|---|---|---|
{rows}
'''
        (ROOT/'docs/VALIDATION_REPORT.md').write_text(report, encoding='utf-8')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
