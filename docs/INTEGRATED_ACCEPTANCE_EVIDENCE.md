# Integrated acceptance evidence

`scripts/verify-integrated-acceptance.py` is the fail-closed gate for the physical
OS matrix, external drawer, real adapters, performance, eight-hour soak, and the
five-user study. It intentionally cannot synthesize or infer physical results.

Create one JSON document from the exact source tree under test. Copy
`sourceCommit` and `sourceFileSHA256` from `scripts/write-evidence-metadata.py`.
Record physical cells for `14.2`, `15`, and `26`; record the macOS 27 developer
beta result with `betaSafeIncompatibility`. Each supported cell must include all
keys printed by this command:

```sh
python3 - <<'PY'
import importlib.util
from pathlib import Path
p = Path('scripts/verify-integrated-acceptance.py')
s = importlib.util.spec_from_file_location('gate', p)
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print('drawerItems:', *sorted(m.DRAWER_ITEMS))
print('drawerChecks:', *sorted(m.DRAWER_CHECKS))
print('scenarios:', *sorted(m.SCENARIOS))
print('userTasks:', *sorted(m.TASKS))
PY
```

Every boolean records an observed result and must be `true`; missing values fail.
The performance object uses the metric names and thresholds enforced in the
script. Five user sessions must each include the ten task keys and
`criticalEvents: 0`.

Run:

```sh
python3 scripts/verify-integrated-acceptance.py /path/to/acceptance.json
```

Any source change invalidates the document because the full source hash map is
compared with the current worktree. Raw logs, Instruments exports, screenshots,
permission state, hardware identifiers, and participant consent records remain
outside the JSON and should be stored beside it in the private evidence folder.
