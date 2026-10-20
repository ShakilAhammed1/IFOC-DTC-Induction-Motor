# Packaging review — 20 October 2026

## Completed checks

- Uploaded ZIP and both SLX containers pass ZIP CRC checks; XML parts parse.
- Both source models contain embedded model workspaces. Observed library links refer to MathWorks libraries; no external referenced-model or data-dictionary parameter was found in the inspected XML. This is static inspection, not a complete compiled dependency analysis.
- The envelope driver includes the corrected empty structure initialization (`cases=pilot([])`).
- Switching candidates include 1, 0.6, 0.35, 0.2, 0.1, 0.05, 0.025, and 0.01.
- The ordered MATLAB case definitions produce exactly the 37 unique IDs in CASE_INDEX.csv when the recorded band factor 0.01 is selected.
- All 13 audited hashes agree with CASE_INDEX.csv. The organizer report says all 37 raw records were packaged in five archives, including all 13 audited matches. The five raw ZIP assets were not attached to this packaging review and were not reopened here.
- Original two MATLAB drivers, two SLX models, Python analysis, numeric tables, audit evidence, and nonempty figures are preserved byte-for-byte from the uploaded repository.
- Python syntax and the harmonic-fitting synthetic check were checked locally. The checksum verifier passes against this delivered code package.

## Packaging changes

- Removed the zero-byte `results/figures/current_spectra.svg`; the original nonempty PNG is retained. No replacement spectrum was fabricated.
- Added `run_repository.m` for explicit modes, temporary cache/code-generation paths, source-path checks, and session restoration. It does not change the original controller calculations.
- Added a standard-library checksum verification command for repository files and optionally all 37 extracted raw files.
- Replaced incomplete reproduction notes with the full ordered mode sequence and the boundary between reanalysis and expensive simulation regeneration.
- Added metric definitions, reuse/provenance notes, and ignored generated simulation outputs.

## Not established by this review

- No MATLAB installation is available here: the wrapper and models were not compiled or simulated during this review.
- No new 37-case simulation, raw-data reanalysis, spectral result, controller tuning, or scientific novelty claim is made.
- The supplied Python script recomputes 13 audited raw cases; it does not rebuild every figure or presentation table.
- Author/citation metadata, source-example redistribution terms, and publication acceptance remain outside this packaging check.
