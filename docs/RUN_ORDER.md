# Reproduction order

1. Inspect CASE_INDEX.csv and obtain all 13 audited raw records.
2. Extract the release archives to data/raw/ and run the Python command in README.md. Compare results/recomputed with the supplied tables.
3. For simulation regeneration, the source models must remain beside run_stage12.m in its source_models folder. Open MATLAB in code/matlab and inspect run_stage12('preflight') before any new simulation. This organizer does not run or validate MATLAB code.
4. The established base script modes are pilot, envelope, switching, and refine. The expanded switching calibration and additional DTC finer-step checks may use separate local helper scripts. Their latest versions and exact run order must be confirmed before calling this a complete simulation-regeneration release. Additional candidates are retained outside the repository in 03_LOCAL_REVIEW.

Do not substitute an older script merely because its filename matches. This package performs collection, checksumming and archive validation, not controller or MATLAB runtime validation.
