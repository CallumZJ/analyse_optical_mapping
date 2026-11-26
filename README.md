# analyse_optical_mapping
Code for GUI-based matlab analysis of panoramic or single camera optical mapping data.

Includes modified versions of sifread, grs2rgb and load_acq from matlab exchange.

For full functionality requires the following additional files:
CANDLE package for median filtering https://www.mcgill.ca/bic/software/tools-data-analysis/anatomical-mri/candle
CircStat2012a for conduction velocity statistics https://www.jstatsoft.org/article/view/v031i10
Altmany-export_fig https://github.com/altmany/export_fig
Findfirst https://uk.mathworks.com/matlabcentral/fileexchange/2631-findfirst
Natsort for files https://uk.mathworks.com/matlabcentral/fileexchange/47434-natural-order-filename-sort
FilterM (FiltFiltM) for temporal filtering: included in third_party/FilterM (see below)

Additionally if high quality movie export is desired ffmpeg should be installed and on the path.


Code generated primarily by Callum Zgierski-Johnston and Teo Puig Walz

## Changes to master's existing analysis

These change the numbers of an analysis that master's app could already do
(`rabbit_cv_map.m` unless named):

- CV, Nearest Neighbour: speed = gradient / |gradient|^2, from the 3x3
  pixels around each point within its own view (was 1/component per axis;
  small components were set to 0).
- CV, Remove local outliers: each outlier pixel is blanked, and the passes
  repeat until none is removed (was the block of outlier rows x columns,
  one pass).
- CV, Bayly: a fit with fewer than 3 distinct rows or columns, or
  rcond(A'A) < 1e-8, gives no value (was a value with MATLAB's "singular"
  warning).
- CV, mean + 3 SD cut: only with Remove local outliers on (was always).
- CV defaults: a 3x3 median of the activation times on, and a time window of
  two frame intervals (2000/fps ms), at least 10 ms, until a value is typed.
  A workspace saved without these settings keeps no smoothing and 6 ms, and
  History says so.
- CV, pixel size: one size per view for the rabbit data; Measure length
  gives µm/pixel, as the CV map reads it (it gave mm/pixel, 1000 times too
  small).
- Binning keeps the ROIs and the segmentation area, rescaled; Average beats
  works with one beat (see Processing below).

## Rabbit panoramic system and 3D reconstruction (2026)

Added by Collin Snitchler (2026) on top of the code above, for the rabbit
panoramic system: four views of one heart through mirrors, seen by one camera.

- **Regions and cut images**: a two-panel editor for the four view regions
  (`rabbit_panoramic_editor.m`), the region file (`rabbit_stack_io.m`), and
  TIFF copies of each view cut with the same regions (`rabbit_cut_tiffs.m`).
- **Reconstruction tab** (`rabbit_reconstruction_ui.m`): builds a 3D mesh of
  the heart from the cut reconstruction images. The steps are a COLMAP sparse
  model
  (`rabbit_sfm_build.m`), dense clouds ("COLMAP" or "APDe-MVS + COLMAP",
  chosen per run; COLMAP always runs, as the mesh checks take from its cloud
  which cameras see each point), a mesh
  (`rabbit_mesh_cleanup.m`, `rabbit_membrane_fit.m`) and checks of the mesh
  against the images (`rabbit_mesh_alignment.m`). `rabbit_reconstruction_tab.m`
  runs these steps and keeps a record of each run.
- **Rig calibration** with pyCamSet (`rabbit_calibration.m`,
  `rabbit_calibration_dialog.m`, `rabbit_pycamset_*.py`). It gives the mesh
  in mm and the mm per pixel of each view. `rabbit_fov_position.m` places
  recordings whose camera area of interest differs.
- **Pixel size per view** (`rabbit_calibration_scale.m`, `rabbit_cv_map.m`):
  after the cut, a calibration recording loaded with the data can be
  calibrated at once ("Calibrate now..." or "Later"), through the
  Reconstruction tab's own calibration window. Its size of a pixel of each
  view, at the cube's depth, fills the Conduction Velocity tab's View1 to
  View4 fields once the cube edge it rests on is confirmed; each field shows
  where its value came from. Input Scale changes only the fields edited, and
  Measure length only the view the line is in (in µm/pixel, as the CV map
  reads it; master's Measure length stored mm/pixel, and a workspace saved
  with such a value is not converted on load). The CV map measures each view with its own size and fits
  within one view. Data without the four rabbit regions keep one value.
- **Bayly defaults** (`rabbit_cv_map.m`; chosen for the rabbit data, not from
  a reference): the activation
  times go through a 3x3 median first (NaN ignored, within the tissue and
  each view), and the time window is two frame intervals (2000/fps ms) until
  a value is typed. Both are settings on the Conduction Velocity tab, and
  History and the run manifest record them. A workspace saved before this
  change keeps the old settings (no smoothing, 6 ms), and History says so. The mean + 3 SD cut of the CV
  map runs only with Remove local outliers on. When the middle half
  (25-75 %) of a view's activation times lies within 10 ms, the CV tab,
  History, the Results box and the Visualise CV caption warn that CV there is
  an apparent speed.
- **Reprojection**: the activation map, the frames and the conduction velocity
  of the Analysis tabs are put onto the mesh with RHYTHM
  (`rabbit_rhythm_reproject.m`) and shown in Visualise.
- **Segmentation**: the masks for the reconstruction use the threshold of
  segmentationAssist (`rabbit_segmentation_core.m`, `_masks.m`, `_preview.m`).
- **Confidence of the projection**: each projected face has a class (1 direct,
  2 overlap, 3 edge at RHYTHM's 0.55, 4 low confidence, 5 unassigned), saved
  next to the projection. Visualise's "Low-confidence fills" checkbox shows or
  greys out class 4; it starts unticked when the edge weight is below 0.55.
- **Conduction velocity direction**: the CV vectors of each view are lifted onto
  the mesh surface through that view's camera (`cv_direction.mat`, approximate)
  and drawn as arrows in Visualise ("Arrows" under the CV panel). Visualise starts with the
  colour ranges recorded at projection (`display_limits`), else auto: the
  1st-99th percentile of the values drawn, for the activation as for the CV
  panel; values outside show in their own colours. A typed range wins.
- **Activation spread caution**: Results and the activation caption warn when
  the 5-95 % spread of the activation the panel draws is above 80 ms (chosen
  for the rabbit data, not from a reference); a pacing cycle given in Step 2
  (Pacing cycle, ms, optional; recorded with the run and with each
  projection) is named in the row.
  Text only: no data are changed, and no step counts as warned.
- **Recording rhythm** (`rabbit_recording_rhythm.m`): File > Recording
  rhythm... marks the loaded recording as Sinus rhythm, Paced (cycle in ms or
  rate in Hz, kept in ms) or Not stated (the default; never guessed). While it
  is Not stated the app asks once, at the first CV map or projection (never
  with `OM_APP_HEADLESS=1`; scripts call `app.set_recording_rhythm`). The top
  line, History, Results, the Visualise captions and saved pictures show it;
  Step 2's Pacing cycle is the same value; it is saved with the workspace and
  recorded with each projection (`recording_rhythm`). Marked Paced while every
  view activates nearly simultaneously (the CV warning's own check), a caution
  says so. Labelling only: no computed value changes.
- **Saving visuals** (`om_export.m`): every data visual saves as PNG, JPG or
  PDF (graphs and maps also as CSV), from a save button or its right-click
  menu. In Visualise each panel has a Save panel... button and the window
  a Save... button; their pictures carry a footer line (run, units, colour
  range, date), are named after the run and go first to the run folder's
  `exports` folder.
- **Menus**: File > Open Reconstruction Manifest (go on from a saved run) and
  File > Reconstruction Help. The tab's Guide button opens the same help
  (`reconstruction_help_content.m`).
- **Processing**:
  - A load that runs out of memory stops cleanly and says how much memory is
    free.
  - Binning keeps the ROIs and the segmentation area, rescaled, and Undo puts
    the earlier ones back. Master's ROI restore on binning is kept;
    the exact pixel-centre scaling, the NaN masks and Undo are added.
  - Undo with nothing to undo says so.
  - Average beats works with one beat.
  - beat_averaging.mlapp ignores a press before it has started and shows the
    filter labels whole.
- **Outside functions**: `om_require_function.m` finds FiltFiltM in the copy in
  `third_party/FilterM` when it is not on the path, and names findfirst when
  it is missing.
- **Job wrapper**: `job_wrapper.ps1` runs the outside tools of a run (Windows)
  in a Job Object, so a cancel stops the whole tool.
- **Tests**: `tests/` holds headless MATLAB tests (`OM_APP_HEADLESS=1`). They
  start the app without a window and check one feature each.

`dat_reader.m` and `dat_header_reader.m` were restored from this project's earlier history
because the app still calls `dat_reader` to open .dat files. They carry no
licence statement; their origin is in the credits below.

### Words used in the code

- **View1..View4**: the four mirror views, numbered left to right in the
  camera frame. The regions file stores their boxes in the rows
  `[View2; View3; View1; View4]` (`rabbit_panoramic_editor.m`). On the
  activation map (the "canvas") their order follows the rotation setting
  (`rabbit_rhythm_reproject.m`, "Canvas un-mapping"). The calibration's
  `tile1..tile4` are View1..View4.
- **Stage** (code) = **step** (screen): one program run of a reconstruction,
  e.g. `image_undistorter`. Steps 1-4 on the left of the tab are the inputs,
  not stages.
- **`<stem>.matom`**: a folder the app makes next to the recording to hold
  the Reconstruction tab's state, its runs and their exports. Deleting it
  deletes every run of that recording. A recording can have further ones,
  `<stem>_01.matom` and so on.
- **Fresh / restore**: a new run / a run opened with File > Open
  Reconstruction Manifest (Help's "journeys", the journey strip, the tests).
- **Gate**: a check with PASS/WARN/FAIL; codes M1-M10 and A1-A6 (see "Mesh
  and alignment checks" below).

### Editing the .mlapp files

An App Designer save rebuilds an app's code from the App Designer model
stored inside the file (`appdesigner/appModel.mat`), not from the code
(`matlab/document.xml`). When the model is older than the code, a save
deletes every part of the code the model does not hold.
`tests/helpers/mlapp_sync_model.m` rebuilds a model from the code, and
`tests/probe_mlapp_model_consistency.m` checks every .mlapp: it writes,
headless, the code App Designer would write from the model and compares it
with the code.

An App Designer save of these files writes back the same code. For
that, the code keeps to what App Designer can hold:

- nothing but App Designer's own lines inside `createComponents` (no
  comments, no other code);
- only callbacks (`function name(app, event)`) in the callbacks block;
  other functions go in the editable `methods` blocks above it;
- the apps hide their window for scripts and tests (`OM_APP_HEADLESS=1`)
  as the first statement of `startupFcn`, because `createComponents` shows
  it. In a desktop MATLAB with `OM_APP_HEADLESS=1` the window therefore
  flashes up briefly; run the tests with `-noFigureWindows`, as
  `tests/run_probes.py` does (see Running the tests).

After any save in App Designer, run `tests/probe_mlapp_model_consistency.m`:
it shows what the save changed.

Editing the code outside App Designer:

- Unzip `matlab/document.xml`, edit the code in the CDATA block, then zip it
  again. `tests/helpers/mlapp_surgery.py` does the zip step and leaves the
  other parts of the file byte-identical.
- After a change, run `tests/probe_mlapp_components.m` and
  `tests/probe_mlapp_model_consistency.m`. If the second fails, bring the
  model up to date: `mlapp_sync_model('<app>.mlapp', '<app>.mlapp',
  '<new>.mlapp')` (headless, MATLAB R2026a), probe `<new>.mlapp`, then
  replace the app with it. MATLAB's serializer may leave out the newline
  after `</w:document>`; `mlapp_surgery.py` puts the original
  `document.xml` back byte for byte.

The Reconstruction tab, its controls and its two File menus are built by
`rabbit_reconstruction_ui.m`, not by the .mlapp. The app makes that object in
`startupFcn` (`app.recon = rabbit_reconstruction_ui(app, app.TabGroup,
app.FileMenu)`). The class header lists every member of the app it reads or
writes, and why.

Controls added at start-up, not in the .mlapp, into the Conduction Velocity
tab's grid `GridLayout22` at fixed cells (row, columns):

- `rabbit_cv_map.controls`: the outlier test drop-down (1, 6), the slowest
  speed resolved (2, 5-6), Smooth activation times (5, 5-6) and Leave out
  activation times above the display limit (5, 7-9); it also sets the row
  heights of the SET LIMITS panel's grid `GridLayout8_2`;
- `rabbit_calibration_scale.show`: the pixel size per view (4, 3-6), Scale
  from calibration... (3, 4) and its note (3, 5-6).

In `analyse_optical_mapping.mlapp` itself (createComponents), column 5 of
`GridLayout6` (FILTERING tab) is 'fit', so that 'Kernel size:' and 'Cutoff
frequency (Hz):' are not cut off.

Keep those cells free in App Designer. If App Designer renames
`GridLayout22` or `GridLayout8_2`, change these two files: the controls are
left out without an error when the grid is not found.

### Credits and sources

Code and methods by others that these additions use, adapt or follow:

- **COLMAP**, for structure from motion and multi-view stereo. Schönberger
  J.L. & Frahm J.-M. (2016) Structure-from-Motion Revisited, CVPR;
  Schönberger J.L., Zheng E., Pollefeys M. & Frahm J.-M. (2016) Pixelwise View
  Selection for Unstructured Multi-View Stereo, ECCV. https://colmap.github.io
  (BSD licence). It is run as an outside program and not shipped here.
- **APDe-MVS**, an optional dense cloud. Zeng, Wang & Guan (2025) Matching
  Ambiguity-Resilient Multi-View Stereo via Adaptive Patch Deformation,
  Pattern Recognition 112593. https://github.com/whoiszzj/APDe-MVS. It is run
  as an outside program.
- **RHYTHM 2.0**, for projecting the optical mapping data onto the mesh.
  Gloschat C. et al. (2018) RHYTHM: An Open Source Imaging Toolkit for Cardiac
  Panoramic Optical Mapping, Sci Rep 8:2921 (PMID 29440763), Efimov Lab, MIT
  licence. The software lineage is Laughner J.I. et al. (2012) Am J Physiol
  Heart Circ Physiol 303(7):H753-65 (PMID 22821993). Nine files are copied
  unchanged in `third_party/RHYTHM`; `NOTICE.md` there lists them with their
  hashes. https://github.com/optocardiography/RHYTHM-2.0
  RHYTHM's own files build on others' work: imdist.m on Janne Heikkilä's
  camera model (Heikkilä J. (2000) Geometric Camera Calibration Using Circular
  Control Points, IEEE TPAMI 22(10):1066-1077); pred.m and dataProjection02.m
  on code by Matt W. Kay (about 2002-2004, as their headers say);
  convex_intersect.m on the algorithm in J. O'Rourke, Computational Geometry
  in C, Cambridge University Press (its header gives 1996).
- **pyCamSet**, for the rig calibration. Robin Laven and contributors,
  https://github.com/rlav440/pyCamSet, Apache-2.0 licence. It is run as an
  outside Python package. Its closed-form seed follows Zhang Z. (2000) A
  Flexible New Technique for Camera Calibration, IEEE TPAMI 22(11):1330-1334.
- **FilterM** (FiltFiltM), for temporal filtering. Jan Simon, MATLAB File
  Exchange, BSD licence. A copy is in `third_party/FilterM`, and the app adds
  it to the path only when no other copy is found.
- **Membrane fit**, the default mesh. Collin Snitchler (2026), a MATLAB port of
  his own Python membrane_fit.py (MIT licence; not published separately). The
  method is a Laplacian-regularised least-squares fit: a closed surface pulled
  towards the dense cloud and held inside the camera silhouettes, with the
  uniform graph Laplacian of its displacement as the bending term.
- **Mesh and cloud methods**: alpha shapes (Edelsbrunner & Mücke 1994, ACM
  TOG 13(1):43-72); statistical outlier removal (Rusu et al. 2008, Robotics
  and Autonomous Systems 56(11):927-941); silhouette test after the visual hull
  (Laurentini 1994, IEEE PAMI 16(2):150-162).
- **Sparse model step**: SIFT (Lowe 2004, IJCV 60(2):91-110); ALIKED (Zhao et
  al. 2023, IEEE TIM 72, BSD-3-Clause); LightGlue (Lindenberger, Sarlin &
  Pollefeys 2023, ICCV, Apache-2.0); GLOMAP (Pan et al. 2024, ECCV); CLAHE
  (Zuiderveld 1994, Graphics Gems IV); Otsu (1979, IEEE Trans. SMC 9(1):62-66).
  Mirror views as virtual cameras follow Gluckman & Nayar (2001, IJCV
  44(1):65-79) and Baker & Nayar (1999, A Theory of Single-Viewpoint
  Catadioptric Image Formation, IJCV 35(2):175-196). A cropped principal point follows
  Hartley & Zisserman (2004), sec. 6.1. The depth-reversal guard follows
  Koenderink & van Doorn (1991), Tomasi & Kanade (1992) and Szeliski & Kang
  (1997).
- **Image steps**: Sauvola binarisation (Sauvola & Pietikäinen 2000, Pattern
  Recognition 33(2):225-236), with border handling as scikit-image (van der
  Walt et al. 2014, PeerJ 2:e453); masked normalised cross-correlation
  (Padfield D. (2012) Masked Object Registration in the Fourier Domain, IEEE
  Trans. Image Process. 21(5):2706-2718) to place recordings, equal to
  normxcorr2 (Lewis J.P. (1995) Fast Normalized Cross-Correlation, Vision
  Interface) where one frame lies inside the other; similarity fits (Umeyama
  1991, IEEE PAMI 13(4):376-380); closest point on a triangle (Ericson C.
  (2005) Real-Time Collision Detection, Morgan Kaufmann, sec. 5.1.5).
- **natsortfiles** (Stephen Cobeldick, MATLAB File Exchange): the natural
  filename order of `rabbit_stack_io.m` gives the same order, without needing
  it.
- **dat_reader.m and dat_header_reader.m** (this repository): based on files
  by Martin, Cornell University (2005), with changes by Stefan Luther and
  Amgad Squires (2006-2009), Johannes Schroeder-Schetelig (2010) and
  T. Alexander Quinn (2013), as dat_reader.m says.
- **This repository**: the segmentation step follows segmentationAssist
  (Callum Zgierski-Johnston and Teo Puig Walz).

`citations()` in `rabbit_reconstruction_tab.m` is the table of every
reference a run can use. Each run manifest copies the whole table
(`citations`), and each step's record names the keys of the methods that
step ran.

## Running the app

Requires MATLAB (the apps were saved with R2026a) and the Image Processing
Toolbox (for example `adapthisteq`, `imgaussfilt`, `normxcorr2`,
`imbinarize`, `imfill`, `bwdist`). The mesh steps and their checks also use
the Statistics and Machine Learning Toolbox (`knnsearch`, `randsample`).
The packages listed at the top of this README are still needed for the
analysis tabs.

Put the repository folder itself on the path, not its subfolders, and start
the main app:

    addpath('<repo folder>')
    analyse_optical_mapping

Do not use `addpath(genpath(...))`: `tests/helpers/headless` holds stand-ins
for `uialert`, `uiconfirm`, `uigetfile`, `inputdlg` and other dialogs, and
on the path they replace MATLAB's own.

The app adds its two shipped folders when it needs them: `third_party/FilterM`
when no FiltFiltM is found (`om_require_function.m`), and `third_party/RHYTHM`
at the first projection (`rabbit_rhythm_reproject.ensure_rhythm_path`).

`OM_APP_HEADLESS=1` hides the windows and the questions, for scripts and
tests. Leave it unset for normal use.

A first reconstruction: File > Load file and compute the activation map;
File > Define regions (the four views), whose cut writes the reconstruction
images and the regions file and fills them in on the Reconstruction tab; in
Step 2 choose the sparse model (Build from images by default); Step 3, Check
tools; Step 4, Run (its last step projects the activation map onto the
mesh); then Visualise. The Guide button opens the same checklist.

Privacy note for shared data: a run folder records the name of the computer
that runs it (the `host=` line of its lock file, so that a lock left by
another computer is not taken for one of this computer's), and its
`manifest.json` records the dataset folder, the tool paths (in each step's
command) and the folder name of the Python environment.

## Reconstruction tab setup

The tab runs outside programs. Each is chosen once in the tab (Step 3, or the
calibration window for pyCamSet) and then remembered.

| Tool | Needed for | What the app checks (Check tools) |
|---|---|---|
| COLMAP 4.x, a CUDA build | every run: sparse model, undistortion, dense cloud (`patch_match_stereo` needs a GPU), fusion | `colmap help` reports a 4.x version; every command and option of the chosen SfM recipe exists (the recipes were written for COLMAP 4.2.1) |
| COLMAP model files (ONNX), optional | SfM recipes with ALIKED or LightGlue | each model file has the sha256 the recipe pins, in the COLMAP models folder or as COLMAP's own default; with no folder given, COLMAP downloads its default on first use (network needed) |
| APDe-MVS (`APD.exe` and `run.py`), optional | the "APDe-MVS + COLMAP" dense cloud | `APD.exe --help` runs (it needs its OpenCV, Boost and CUDA DLLs next to it or on the PATH); `<python> run.py --help` exits 0 |
| Python for APDe-MVS | `run.py` | `<python> -c "import sys; print(sys.version)"` runs |
| An NVIDIA GPU and driver | `patch_match_stereo`, `apde_run`, GPU SfM recipes | `nvidia-smi` answers and the GPU has at least 1024 MiB free (without `nvidia-smi`, MATLAB's `gpuDevice` is asked instead) |
| pyCamSet checkout and a Python with its packages (numpy included) | rig calibration (Step 2, Calibrate...) | the calibration job runs `rabbit_pycamset_calibrate.py` with that Python and checkout |

The outside programs run through `job_wrapper.ps1` (Windows PowerShell, a
Job Object), so Cancel stops the whole tool. These steps therefore run on
Windows only. The meshing, alignment and projection steps are MATLAB only.

### How the app finds the tools

Each tool field is filled, highest first, from
(`rabbit_reconstruction_tab.resolve_tool_path`):

1. a path typed or browsed to in this session;
2. the path saved in the dataset's `tab-state.json`, if it still exists;
3. the path last used on this computer, kept in the MATLAB preferences
   (group `analyse_optical_mapping_reconstruction`, in `prefdir`, never in the
   repository or a dataset);
4. an environment variable, if set and the path exists;
5. when none of 2-4 exists, the first of them that is set, so that Check
   tools says where it was looked for; else empty.

| Field | Environment variable |
|---|---|
| COLMAP | `OM_COLMAP_EXE` |
| COLMAP models folder (optional) | `OM_COLMAP_MODELS` |
| APD.exe | `OM_APD_EXE` |
| APDe-MVS run.py | `OM_APDE_RUN_PY` |
| Python env (APDe-MVS) | `OM_APDE_PYTHON` |
| pyCamSet Python | `OM_PYCAMSET_PYTHON` |
| pyCamSet checkout | `OM_PYCAMSET_CHECKOUT` |

A path that no longer exists never wins over one that does. A path is
remembered only when it exists (`remember_tool_path`).

### Mesh and alignment checks

The run's step records and the Results box use these codes
(`rabbit_reconstruction_tab.check_names`):

| Code | Check | Code | Check |
|---|---|---|---|
| M1 | finite points | M9 | direct views |
| M2 | outliers | M10 | point spacing |
| M3 | normal length | A1 | inputs |
| M4 | normals | A2 | alignment |
| M5 | pieces | A3 | camera placement |
| M6 | faces | A4 | silhouette |
| M7 | mesh fit | A5 | scale |
| M8 | holes | A6 | outline |

M1-M10 are measured in `rabbit_mesh_cleanup.m`, A1-A6 in
`rabbit_mesh_alignment.m`. Each gives PASS, WARN or FAIL; a FAIL stops the
run.

## Running the tests

`tests/` holds headless MATLAB tests, one feature each (`probe_*.m`), and a
few Python tests. A probe is a function: it prints one `PASS`/`FAIL` line per
check and a result line, and ends with an error when a check fails.

Every probe needs:

| Variable | Value |
|---|---|
| `OM_APP_HEADLESS` | `1` |
| `MATLAB_PREFDIR` | an empty throw-away folder, so the tests never touch your own MATLAB preferences (MATLAB reads it at start-up) |

`tests/run_probes.py` (Python 3, no packages) sets both and runs every
probe, each in a new headless MATLAB, and counts the PASS, FAIL and SKIP
lines of each:

    python tests/run_probes.py --logs <new log folder> [--matlab <matlab>] [--workers 2] [probe_name ...]

MATLAB comes from `--matlab`, the `OM_MATLAB` variable or the PATH. Each
probe writes `<log folder>/<probe>.log`, and `<log folder>/summary.tsv`
lists every probe with its status and counts; the runner ends with exit
code 1 when a probe failed. `--reuse-matlab` lets one MATLAB run several
probes, with a reset between them; `python tests/run_probes.py --help`
says what that reset cannot put back. Before each probe the runner waits
until 8 GB of memory are free (`--min-ram-gb`, or the `OM_PROBES_MIN_RAM_GB`
variable for a machine's own floor, e.g. 12) and 9 GB in the temporary
folder (`--min-free-gb`); the first wait is printed. Each MATLAB uses the
number of computational threads MATLAB chooses for the machine.

A full run takes about 3.7 hours of MATLAB time in all (the sum of
`tests/probe_timings.tsv`), so roughly 2 hours with `--workers 2`. A quick
check after a small change:

    python tests/run_probes.py --logs <new log folder> probe_mlapp_components probe_mlapp_model_consistency probe_contextual_help probe_results_box probe_cv_defaults

Many probes compare the exact words of messages, tooltips, Help and the
Results box. After changing any text a user sees, grep `tests/` for it, and
run at least probe_contextual_help, probe_results_box, probe_saved_warnings
and probe_visualise_captions.

Writing a probe: a function in `tests/` named `probe_<feature>.m` that prints
`PASS <check>` or `FAIL <check>` per check and ends with `error(...)` when
one failed (a `matlab.unittest.TestCase` class works too; the runner calls
`runtests` on it). With `OM_APP_HEADLESS=1` the dialogs are answered by the
stand-ins in `tests/helpers/headless`: `headless_push('uiconfirm', 'Yes')`
queues an answer for the next `uiconfirm`, and every dialog the stand-ins
did not show is kept in `getappdata(groot, 'om_headless_dialogs')` (by
`headless_record`) and printed to the log.

Run one probe by hand, with both variables set in the shell:

    matlab -noFigureWindows -batch "addpath('<repo folder>'); addpath('<repo folder>/tests'); addpath('<repo folder>/tests/helpers'); addpath('<repo folder>/tests/helpers/headless'); probe_cv_defaults"

Most probes need nothing more: they build synthetic data under `tempdir`,
or use the fake COLMAP in `tests/helpers/fake_colmap`.

The others need test data that is not in the repository. Without it, a
probe prints a `SKIP` line naming the variables (`SKIP <probe>: ...`, or
`PROBE_SKIP <check>` for one check) and returns without an error; the
checks that need no data still run. Their variables:

| Variables | Probes | Data |
|---|---|---|
| `OM_REDO_DS`, `OM_REDO_STEM`, `OM_REDO_RUN` | probe_activation_relative, probe_activation_zero, probe_confidence_classes, probe_cv_arrow_gradient, probe_cv_arrows, probe_cv_projection, probe_cv_range, probe_cv_surface_speed, probe_edge_threshold, probe_export_visuals (X6), probe_reproject_redo, probe_results_box, probe_rhythm_marker (R3b), probe_saved_warnings, probe_view_orientation, probe_visualise_details_layout, probe_visualise_face_csv, probe_visualise_live_captions | a copy of `<stem>.matom` with a COMPLETED run: `<dataset folder>`, the stem, and the run id. A probe that changes it works on its own copy under `tempdir` (`tests/helpers/om_redo_copy.m`), removed afterwards; one that only reads it reads it in place and reports any change (`SHARED_COPY_CHANGED`) |
| `OM_EDGE_BASELINE`, `OM_EDGE_MODE`, `OM_EDGE_REPO` | probe_edge_threshold (all three), probe_cv_projection (`OM_EDGE_BASELINE`) | a projection made by an earlier version of the code, to compare with |
| `OM_TEST_SPREAD_DS`, optional | probe_results_box, probe_visualise_live_captions | a dataset copy whose activation spreads more than 80 ms |
| `OM_ALIGN_OM`, `OM_ALIGN_REC`, `OM_ALIGN_ROI`, `OM_ALIGN_RUN` | probe_om_alignment_image | a dataset copy whose run stopped at the projection check |
| `OM_FOV_PROBE_SMALL`, `OM_FOV_PROBE_LARGE` | probe_fov_measure | two recordings of one camera with different areas of interest |
| `OM_RABBIT_WALK_*` and the tool variables above | probe_rabbit_gui_walk | a full dataset, driven through the GUI from load to projection |
| `OM_TEST_RESTORE_GOLDEN_ROOT` | probe_manifest_containment, probe_manifest_moved_run, probe_manifest_moved_run_anomaly, probe_manifest_open_acceptance, probe_manifest_open_smoke, probe_manifest_partial_runs, probe_manifest_ply_payloads, probe_manifest_singleton_collections, probe_manifest_v1_malformed, probe_restore_and_visualise_gui (these through `tests/helpers/om_restore_fixture_paths.m`), probe_restore_gui_safety, probe_run_cancel_resume, probe_run_open_and_views, probe_run_status, probe_sparse_model_build | the folder holding the golden run's `subset.matom` |
| `OM_TEST_REPROJECTION_GOLDEN_ROOT` | probe_camera_view_restore, probe_reprojection_reference, probe_membrane_fit | the reprojection golden run |
| `OM_TEST_VISUALISE_FIXTURE_ROOT` | probe_visualise_captions | the visualise fixtures |
| `OM_TEST_JOURNEY_GOLDEN_ROOT`, `OM_TEST_JOURNEY_ATTEMPT_ROOT`, `OM_TEST_JOURNEY_ASSERTIONS` | probe_fresh_and_restore_journeys, `tests/helpers/journey_gui_events.m` (needs the app on screen) | the golden run, an empty folder to work in, and a new file for the check rows |
| `OM_COLMAP_EXE`, `OM_PYCAMSET_CHECKOUT` | probe_tool_path_prefs, probe_rabbit_gui_walk, test_pycamset_calibrate.py | the real tools |

Where the data come from. The golden run is run `20260909T110043_d091bb44`
of `subset.matom`, a four-view subset of the reference rabbit recording; it
is not public, so ask the repository's maintainers for a copy. A dataset for
the `OM_REDO_*` probes is made by loading any rabbit recording, cutting it
and running one reconstruction to COMPLETED; set `OM_REDO_DS` to its
folder, `OM_REDO_STEM` to its stem and `OM_REDO_RUN` to the run id.

Switches you can set to leave parts of a probe out: `OM_DENSE_SKIP_GUI`
(probe_dense_options), `OM_SFM_SKIP_GUI` (probe_sparse_model_build); no
production code reads them. Set by the probes themselves: `OM_FAKE_COLMAP_*`
(the fake COLMAP's exit code, delay and model), `OM_PYCAMSET_GUI_DRY_RUN`
(read by `rabbit_reconstruction_tab.m`).

Python tests (`tests/test_*.py`) need Python 3 with `pytest` and `numpy`:

    python -m pytest tests

`test_pycamset_calibrate.py` skips its pyCamSet cases without
`OM_PYCAMSET_CHECKOUT`.

## Map of the large files

Line numbers move; search the named file for the quoted text instead. All of these are
`classdef` files; most hold `methods (Static)` grouped by feature.

Where a run's state lives, and which copy wins (also in the header of
`rabbit_reconstruction_tab.m`):

- `runs/<id>/manifest.json`: the record of a run (its stages, status,
  inputs). It wins over `tab-state.json` for every action that changes a run.
- `runs/<id>/manifest.v2.json`: written beside it when a run made by an older
  version is opened (`convert_v1_to_v2`); `manifest.json` is never rewritten.
  It is used instead of `manifest.json` only when its two hashes match
  `manifest.json`; else it is ignored and reported.
- `tab-state.json`: the dataset's list of runs and the Step 2/3 inputs; for
  the run list a cache, reconciled with each run's manifest before an action.
- `runs/<id>/.lock`: a run is active (RUNNING) only while its lock is live
  (the `pid=` and `host=` of the MATLAB driving it).
- In memory: `obj.state` (the tab-state mirror), `obj.pipeline_run` (the run
  this session drives), `obj.manifest_pins` (which manifest file is in use
  per run).

### rabbit_reconstruction_tab.m (about 26,500 lines): the Reconstruction tab's engine, no UI

| Area | Search for | What is there |
|---|---|---|
| Overview | `%% Reconstruction and reprojection tab backend` | pipeline, run folder layout, citations |
| Active manifest | `% ---- Active-manifest source ----` | which manifest file of a run is in use |
| Tool paths | `function t = tool_path_names` | env variables, preferences, `resolve_tool_path` |
| Stage orders and warning limits | `function order = stage_order_for_source`, `function ms = SPREAD_WARN_MS` | which steps a run has; the limits behind the Results warnings |
| Tab state | `% ---- Tab-state JSON v1 ----` | `load_state`, `write_state`, Step 2 inputs |
| Rig calibration | `% ---- Rig calibration (pyCamSet) ----` | `run_calibration`, the pyCamSet GUI and import |
| Pre-flight | `% ---- Pre-flight ----` | `preflight`: which checks each step needs |
| Runs | `% ---- Run isolation ----` | create, start, cancel, resume and close runs; locks; Reproject run |
| Results box | `function rows = report_rows` | the Results rows: projection rows (sub-sections "% ---- Projection ..."), alignment checks, mesh checks, sparse model, other warnings |
| Stage driver | `% ---- Stage driver ----` | `run_stage`, `run_pipeline`, `build_stage_command`, `run_matlab_stage`, `spawn_and_wait`, `validate_stage` |
| APDe-MVS scene | `% ---- MATLAB-native APDe scene writer ----` | `write_apde_scene`, COLMAP model readers and writers |
| Manifest | `% ---- Manifest helpers ----` | `fresh_manifest`, `record_stage_entry`, `citations`, `write_manifest`, `read_manifest` |
| Visualise | `% ---- MATLAB-native reconstruction/mesh visualisation ----` | `visualise_artifacts` and every `viewer_*` method: panels, captions, colour ranges, arrows, export |
| CV on the mesh | `% ---- conduction velocity on the mesh` | the CV panel of Visualise |
| Point and mesh edits | `% ---- MATLAB-native reversible mesh touch-up ----` | touch-up; each edit writes a copy |
| Point filtering | `% ---- Copy-on-write dense-point intensity filtering ----` | the intensity filter of the dense points |
| Area removal | `% ---- 2D screen-area point removal (copy-on-write) ----` | removing the points inside a drawn area |
| Smoothing | `% ---- Bounded circular mesh smoothing (screen-space brush) ----` | the smoothing brush |
| Opening a saved run | `function [ok, err, info] = open_manifest` | File > Open Reconstruction Manifest |
| Run status | `% Status, progress, resume boundary and activity` | `reconstruction_stage_projection`, lock liveness |
| Manifest v2 | `% v2-aware manifest access` | v1 to v2 conversion, sidecar, digests, strict JSON parser, writer and recovery locks |
| Tool checks | `function results = check_colmap(obj, results)` | `check_colmap`, `check_colmap_recipe`, `check_apde`, `check_python_env`, `check_gpu` |
| Output checks | `function [ok, err] = check_pair_file` | PLY and CDF checks used by `validate_stage` |

### rabbit_reconstruction_ui.m (about 9,900 lines): the tab's window

| Area | Search for | What is there |
|---|---|---|
| Contract with the app | `% Contract with the app (obj.host):` | every app member it reads or writes |
| Layout | `% ---- Journey strip (always visible) ----` to `% ---- Results panel (right) ----` | the constructor: Steps 1-4, tools, Steps list, Results |
| Open a saved run | `function OpenReconstructionManifestMenuSelected` | the restore steps 1-8 |
| Buttons | `function ReconstructionRunButtonPushed` | Run, Resume, Cancel, Reproject, Visualise |
| Point and mesh edits | `function ReconstructionTouchupPreviewButtonPushed` | preview, apply, reset (the `reconstruction_edit_*` methods); `test_edit_fixture_check` (test code) |
| Enablement | `% ---- gate state + accordion helpers` | `reconstruction_gate_state`: which buttons are on and why |
| Runs and steps lists | `function reconstruction_update_run_list` | run list, step rows, logs, attempts |
| Step 2 | `% ---- Step 2: build the sparse model` | SfM recipe, dense choice, calibration, pacing cycle |
| CV map | `function cv = reconstruction_cv_map` | the CV tab's inputs for the projection |
| Help | `% Contextual help and the first-run checklist` | Help window, preferences, first-run trigger |

### rabbit_rhythm_reproject.m (about 4,700 lines): projection onto the mesh

| Area | Search for |
|---|---|
| Entry points (`run`, `run_from_app`) | `% 1. Entry points` |
| Which frame's cameras project the views; frame check | `% 1b. Which frame's cameras` |
| Canvas to per-view maps | `% 2. Canvas <-> per-view source maps` |
| COLMAP readers | `% 3. COLMAP readers` |
| PLY reader | `% 4. PLY mesh reader` |
| Mesh topology | `% 5. Mesh topology` |
| The projection (shipped RHYTHM code); CV direction lift | `% 6. The projection` |
| MATLAB transcription of `dataProjection02` (fallback) | `% 6a. FALLBACK` |
| Exports (CDF, PLY, video, confidence, manifest) | `% 7. Exports` |

### rabbit_cv_map.m (about 930 lines): the Conduction Velocity tab's methods

Bayly and nearest-neighbour fits with a pixel size per view (`function cv = bayly`,
`function cv = nearest`), local outliers, the 3x3 median (`median3`), the per-view
spread check (`simultaneous_check`), and the tab's controls and History text
(`function controls(app)`, `function t = history_text`).

### rabbit_calibration*.m: rig calibration and pixel size

| File | Search for | What is there |
|---|---|---|
| rabbit_calibration.m (1,600) | `% 1. Settings of a calibration` ... `% 5. Pixel size on the mesh` | spec and gates (`GATE`, `RIG_GATE`), tile folders, reading the pyCamSet result, the sparse rig against the calibration, mm per pixel |
| rabbit_calibration_dialog.m (490) | `function run(obj)` | the calibration window only |
| rabbit_calibration_scale.m (1,000) | `% ---- The question after the cut ----` ... `% ---- The state ----` | View1-View4 pixel sizes on the CV tab: from a calibration, by hand, after binning |

### rabbit_mesh_*.m: mesh and its checks

| File | Search for | What is there |
|---|---|---|
| rabbit_mesh_cleanup.m (2,500) | `function r = run(`, `% Membrane method:` | mesh from the dense cloud (membrane fit by default, alpha shape as an option) and gates M1-M10 (each marked by a `% M<n>` comment) |
| rabbit_mesh_alignment.m (1,300) | `function r = run(`, then `% ---- A2:` ... `% ---- A6:` | gates A1-A6: the mesh against the cameras and tissue masks; nothing is moved |

### Smaller files: rhythm marker, activation zero, saving visuals, stacks

| File | Search for | What is there |
|---|---|---|
| rabbit_recording_rhythm.m (840) | `% ---- The marker ----` ... `% ---- The app side ----` | File > Recording rhythm...: the marker, its words, the cautions, the Paced dialog |
| rabbit_activation_zero.m (130) | `classdef rabbit_activation_zero` | what time 0 of an activation map is, recorded with the map and its projection, for the colour-bar label |
| om_export.m (950) | `classdef om_export` | Save as PNG / JPG / PDF and Save data as CSV on the data axes of every app |
| rabbit_stack_io.m (1,300) | `classdef rabbit_stack_io` | reading the stacks, the combined display and the region (ROI) JSON |
