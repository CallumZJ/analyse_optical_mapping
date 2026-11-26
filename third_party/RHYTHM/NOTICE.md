RHYTHM (2.0) - vendored dependency
===================================

This directory contains a SUBSET of the upstream RHYTHM 2.0 panoramic
optical mapping toolkit, vendored unmodified for the reprojection stage
of analyse-optical-mapping (the "collin-dev" rabbit panoramic feature).

Upstream repository
-------------------
  https://github.com/optocardiography/RHYTHM-2.0
  Branch: master
  Pinned commit: dc4818acfc9bcd393785d77920a7e77de80c6400
                 (2018-04-26, "Added conefilt.m" - last push 2018-04-26)
  License: MIT (upstream License.txt, "Copyright (c) 2017 Efimov Lab,
           The George Washington University")

Vendored files (VERBATIM copies of the pinned commit; byte-identical,
no modifications)
-------------------
  Source Code/MATLAB/Common_files/configc.m        (system/camera configuration)
  Source Code/MATLAB/Common_files/imdist.m         (Heikkila lens-distortion model)
  Source Code/MATLAB/Common_files/pred.m           (perspective projection pred())
  Source Code/MATLAB/ORIENT_files/checkpoly.m      (convex polygon check/sort)
  Source Code/MATLAB/ORIENT_files/conefilt.m       (cone edge filter)
  Source Code/MATLAB/ORIENT_files/convex_intersect.m (polygon intersection area)
  Source Code/MATLAB/ORIENT_files/dataProjection02.m (RHYTHM projection core)
  Source Code/MATLAB/ORIENT_files/line_intersect.m (line intersection helper)
  Source Code/MATLAB/ORIENT_files/smoothregionbdr.m (view-border smoothing)
  License.txt                                       (upstream licence, MIT;
                                                     copied byte for byte)

How the files are used
----------------------
  rabbit_rhythm_reproject.m calls dataProjection02.m itself (the default
  method), with views resampled to its 100x100 camera grid, in a
  temporary working folder, closing the msgbox/waitbar it opens.
  dataProjection02 uses pred, imdist, configc, conefilt, smoothregionbdr,
  checkpoly, convex_intersect and line_intersect, all vendored here, so
  no further upstream file is needed. The adapter's fallback
  reimplementation calls the same helpers directly.

SHA-256 of the vendored files (must not change)
-----------------------------------------------
  f717cc79b1726fe17dfb3a4abd12ea83f875436e05c27053f3824d0777016f5b  Common_files/configc.m
  7c761621383ac633ad83bd1fe7e884733548c6ef87d85365a31141edc9f9fd97  Common_files/imdist.m
  d3b1c8e30fea16a76566aadf679fc315be3d83edadbdc1fe53139950e0e96d3a  Common_files/pred.m
  98f337fb3285e9c1ccd41da5f15b3de70da7881d9d326a86775ffeb2e5e0318a  ORIENT_files/checkpoly.m
  685e0c8f76e75d6e003a266ff60d141cef894dd54f093d7a872a541dc4a62fe7  ORIENT_files/conefilt.m
  f8c29637d928af5302b7d5394d253aae830939a596566b7e0a736cbc388b078a  ORIENT_files/convex_intersect.m
  289ba0fb10a61a82c08cc37e28d6fd9c1e3ae4dae8c946eb70c59bfa7189b885  ORIENT_files/dataProjection02.m
  377a1ecda4df1d45c7602421c7308642b4866aca9cc880e54acc78031e8041b7  ORIENT_files/line_intersect.m
  1dc2a829cef8548d5308fde2a355e4433a5c0768cd01be1d591b1b6d19fb5ff7  ORIENT_files/smoothregionbdr.m
  (paths relative to Source Code/MATLAB/; checked by tests/probe_rhythm_pure.m)
  f8733d16cab8eca9f8269363f806a280ab2a19b793244a66c9e80aa9ed871c64  License.txt
  (in this folder; upstream License.txt at the pinned commit, added 23.11.2026)

Files intentionally NOT vendored
--------------------------------
  ORIENT2.m / FIT3.m / WHIRL2.m and their GUIs (the analysis is driven
  from analyse-optical-mapping's own GUI; only the projection math is
  consumed through rabbit_rhythm_reproject.m).
  WHIRL_files/CPP_files/*.mexw64 (2018 Windows MEX binaries - not needed;
  COLMAP/APDe-MVS provide the reconstruction).
  LabVIEW sources, documentation, sample data, example calibration files.

Attribution (required by the upstream MIT license)
--------------------------------------------------
  RHYTHM: An Open Source Imaging Toolkit for Cardiac Panoramic Optical
  Mapping. Gloschat C, Aras K, Gupta S, et al. Sci Rep 2018;8:2921.
  doi:10.1038/s41598-018-21333-w. PMID 29440763.
  RHYTHM 2.0 software heritage: built on the original rhythm software
  package by Laughner et al (2012), Am J Physiol Heart Circ Physiol
  2012;303(7):H753-65. PMID 22821993.

Sources named inside the vendored files
---------------------------------------
  imdist.m: Janne Heikkila, University of Oulu (version 3.0, 10-17-00);
    camera model of Heikkila J. (2000) Geometric Camera Calibration Using
    Circular Control Points, IEEE TPAMI 22(10):1066-1077.
  pred.m: "2002, MWKay"; dataProjection02.m: "a modification and
    implementation of the code written by Dr. Matt Kay (circa 2004)" -
    Matt W. Kay.
  convex_intersect.m: "based on the algorithm of JOSEPH O'ROUKE,
    Computational Geometry in C, Cambridge University Press, 1996"
    (J. O'Rourke; the file spells the name and gives the year so).

License text (MIT)
------------------
  Copyright (c) 2017 Efimov Lab, The George Washington University

  Permission is hereby granted, free of charge, to any person obtaining
  a copy of this software and associated documentation files (the
  "Software"), to deal in the Software without restriction, including
  without limitation the rights to use, copy, modify, merge, publish,
  distribute, sublicense, and/or sell copies of the Software, and to
  permit persons to whom the Software is furnished to do so, subject to
  the following conditions:

  The above copyright notice and this permission notice shall be
  included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
  ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

Provenance
----------
  Vendored 2026-09-04 for analyse_optical_mapping: the original RHYTHM
  source is kept unchanged and called through an adapter
  (rabbit_rhythm_reproject.m); upstream files are never modified.
  Upstream archive sha256: c230b06fbec971ab157a35dc55bf8742e88eda32f172f938d2daaed8867caa0e
  (RHYTHM-2.0 dc4818ac master tarball).
