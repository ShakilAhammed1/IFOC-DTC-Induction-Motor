# IFOC and DTC Induction Motor Study

Simulation study of torque ripple, current harmonic distortion, load-step speed response, rotor-resistance sensitivity, and switching-activity transfer.

## Included evidence

The result tables describe 37 cases. Thirteen raw records were independently reprocessed in the associated analysis. This packaged copy contains 37 raw records, of which 13 match those audited SHA-256 checksums. Check docs/CASE_INDEX.csv for exact coverage. Other raw records, where included, are linked by case filename to simulation summaries and have not been independently revalidated by this packager.

## Requirements and analysis

MATLAB/Simulink R2025b and Simscape Electrical are needed to run the models. Python analysis uses numpy, scipy, h5py, and matplotlib. Raw data are distributed as separate release assets.

After extracting raw files into data/raw/, run from the repository root:

```text
python -m pip install -r code/python/requirements.txt
python code/python/recompute_raw_metrics.py data/raw results/recomputed
```

The analysis script requires all 13 audited raw records named in audit/raw_sha256.json. The supplied summary tables do not require MATLAB to view.

## Contents

- code/python: independent raw-data reprocessing.
- code/matlab: locally collected MATLAB package, when uniquely identified; see docs/RUN_ORDER.md.
- results/tables and results/figures: previously verified processed results.
- audit: validation records and checksums.
- docs/CASE_INDEX.csv: case settings and raw-data coverage.

## Interpretation

Simulation only. Known-resistance correction is a diagnostic intervention, not an online estimator. Switching activity is matched only where the measured tolerance is satisfied. THD through harmonic 50 excludes other spectral content. No universal controller superiority or hardware validation is claimed.

## Version and reuse

Before publication, add the final author/citation information, release tag, and appropriate reuse terms. Preserve original notices in third-party-derived models and code. Public availability does not itself establish reuse permissions.
