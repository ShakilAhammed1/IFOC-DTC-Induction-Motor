# Metric interpretation

- `TorqueRMS_Nm` in the original MATLAB summaries is the population standard deviation of torque about its mean. The audited Python table names this `TorqueStd_Nm`; it is not total RMS torque.
- Current RMS is the mean of the three per-phase RMS values.
- Gate activity is the average rising-edge rate across six gate signals, not a measured switching-energy or efficiency metric.
- The physical-metric windows are [3, 3.5) seconds at 1600 rpm and [3.5, 4.5) seconds at 900 rpm.
- The settled screen requires speed MAE below 1% of reference, half-window mean-speed drift below 1 rpm, torque-mean drift below 1% of torque base, and aggregate current-RMS drift below 1%.
- Load recovery uses a +/-2% speed band after 1.6 seconds. Zero means the speed never left that band; it does not mean instantaneous physical response. No torque-step rise time is provided.
- Spectral analysis uses antialias resampling to 40 kHz, a fitted fundamental, and harmonic least squares through harmonic 50. The principal window spans 20 cycles. Two shifted 10-cycle windows measure window sensitivity; their range is not a statistical confidence interval.
- Low harmonic THD does not imply low nonharmonic residual. Report the residual metric alongside THD where relevant.
- Results that fail the tracking screen are diagnostic and are not a fair steady-state controller ranking.
- Finer-resolution checks change both main/local solver resolution and the IFOC block integration step; feedback/control sampling remains as recorded. These are combined resolution checks, not isolated solver convergence proof.
- Correcting the controller resistance estimate with the known plant value is a sensitivity diagnostic. It is not online parameter identification.
- The fixed-tuning comparison does not prove equal loop bandwidth or equal physical rotor/stator flux targets.
