# Fixtures of the gate tests (HU-14)

The `*.json` files here are **synthetic** reports in the shape of a Trivy JSON report (they only carry what the gate reads:
`SchemaVersion` and the `Severity` of each vulnerability). They are not scan results of any real image and the
`SYNTHETIC-xxxx` identifiers are not CVEs. They exist so that the gate logic can be tested offline and repeatably.
`invalid.json` and `empty.json` check that a broken report is an error, never a pass.
