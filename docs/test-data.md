# Test data

`testdata/kiln-v2-cases.json` holds the 46 Kiln wire v2 cases. Each accept case is decoded and encoded again. The bytes must match the hex in the case. Each reject case must raise the recorded error name: `FRAME`, `LIMIT`, `EOF`, `TYPE`, `UTF8`, `TRAILING`, or `SCHEMA`.

`testdata/reference/kiln_ref.py` is a test oracle for Frozen scalars, lists, optionals, dicts, and frames. The runtime codec does not import it. The Swift tests also check negative zero and a quiet NaN payload against bytes that oracle produces.

`testdata/schema/point.json` and `testdata/schema/message.json` are the JSON Schema files the generator reads. `scripts/check-generated.sh` runs the generator twice and diffs the output against `tests/generated`.

The wire rules those cases pin are written in the [Kiln wire v2](https://leo-gan.github.io/gld-kiln/spec/) specification.
