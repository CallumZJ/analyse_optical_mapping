FilterM (FiltFiltM) - vendored dependency
=========================================

This directory contains ONE file of Jan Simon's FilterM package from the
MATLAB File Exchange ("FilterM", version of 20 July 2011), vendored
unmodified, with its licence. The Temporal filter step of
analyse_optical_mapping calls FiltFiltM for zero-phase (forward and
backward) filtering of the image stack along time.

Vendored files (VERBATIM copies; byte-identical, no modifications)
------------------------------------------------------------------
  FiltFiltM.m   ($JRev: R-t V:019 Date:20-Jul-2011 10:29:21 $)
  license.txt   (BSD licence, "Copyright (c) 2011, Jan Simon")

Files intentionally NOT vendored
--------------------------------
  FilterM.m, FilterX.c (the C-MEX filter): FiltFiltM uses MATLAB's own
  filter() when FilterX is not compiled; the File Exchange folder used
  with the app on the development machine has no FilterX MEX either. Leaving both out
  keeps the numbers the same, needs no compiler and works on Windows,
  Linux and macOS. Without FilterM.m on the path FiltFiltM also stays
  silent instead of asking for FilterX.c to be compiled.
  uTest_FilterM.m, uTest_FiltFiltM.m (upstream unit tests).

How the file is used
--------------------
  om_require_function.m (repository root) adds this folder to the end of
  the MATLAB path for the session when FiltFiltM is not already on the
  path, so a copy the user installed still takes precedence. The saved
  MATLAB path is not changed.
  tests/probe_filtfilt_beat_averaging.m checks that Temporal filter works
  with the path MATLAB starts with, and that the result equals filtfilt of
  the Signal Processing Toolbox (relative difference below 1e-9).

SHA-256 of the vendored files (must not change)
-----------------------------------------------
  0db8f7f8e5f7e3880dbde1b5db866f8f3ae365d813524dcee2afacf5d9673559  FiltFiltM.m
  b20fc6c70badffd0759013d402c5d23c26775e57319f82588439827ababf74a6  license.txt

Licence
-------
  BSD-style (two clauses), see license.txt in this folder. Redistribution
  of the source is allowed when the copyright notice, the conditions and
  the disclaimer are kept, which license.txt here does.
