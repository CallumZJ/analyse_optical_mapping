#!/usr/bin/env python3
'''
Purpose: Open the pyCamSet GUI (development branch) at Phase 1 on a folder of rabbit tile images

Started by the Reconstruction tab's "Open in pyCamSet..." button, with the Python
and the pyCamSet checkout the user chose:

    python rabbit_pycamset_gui.py --checkout <pyCamSet checkout> --images <folder>

<folder> holds one subfolder per camera (tile1 .. tile4, as rabbit_calibration.m
writes them: tiles of the reconstruction frame, outer tiles flipped left-right),
which is the layout pyCamSet's Phase 0/1 read. The GUI opens with that folder as
its image folder in every phase and shows Phase 1 (detection); from there the user
goes through the phases as they wish, and exports a camera set (.camset) that the
Reconstruction tab can take in ("pyCamSet camera set" field). pyCamSet itself is
not changed: the window is built as pyCamSet's own main_window() builds it.

Sources: pyCamSet (R. Laven and contributors), development branch: pyCamSet.gui.
'''
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True   # nothing written into the repository or the checkout


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--checkout', required=True, help='the pyCamSet checkout (development branch)')
    ap.add_argument('--images', required=True, help='folder of camera subfolders tile1 .. tile4')
    ap.add_argument('--target', default='',
                    help='the calibration target as JSON, e.g. {"type": "PuzzleBoardCube", "n_points": 7, "length": 30}')
    ap.add_argument('--target-file', default='',
                    help='a UTF-8 JSON file holding the target, as --target (the app uses this: safe on Windows)')
    ap.add_argument('--dry-run', action='store_true',
                    help='build the window, set the folder and Phase 1, print what is shown, and close (tests)')
    a = ap.parse_args(argv)
    images = Path(a.images).resolve()
    if not images.is_dir():
        print(f'The image folder {images} does not exist.', file=sys.stderr)
        return 1
    sys.path.insert(0, str(Path(a.checkout).resolve()))
    try:
        from pyCamSet.gui.__main__ import advice_for
    except ImportError as exc:
        print(f'pyCamSet could not be imported from {a.checkout}: {exc}', file=sys.stderr)
        return 1
    try:
        from PySide6.QtWidgets import QApplication
        from pyCamSet.gui.main_window import PyCamSetApp
        from pyCamSet.gui.shared_functions import TAB_PHASE1
    except ImportError as exc:
        print(advice_for(exc), file=sys.stderr)
        return 1
    # As pyCamSet's main_window(): coloured reports in the terminal pane, and the
    # OpenGL surface format set before the application exists
    from pyCamSet.utils.report_format import force_colour
    force_colour(True)
    from pyCamSet.gui.education_perf import configure_surface_format
    configure_surface_format()
    app = QApplication.instance() or QApplication(sys.argv[:1])
    window = PyCamSetApp()
    window.show()
    folder = str(images)
    for name in ('phase0_tab', 'phase1_tab', 'phase2_tab', 'phase3_tab', 'phase4_tab'):
        tab = getattr(window, name, None)
        if tab is not None and hasattr(tab, 'set_image_folder'):
            tab.set_image_folder(folder)
    # The calibration's target, so that Phase 1 detects the right cube at the
    # right size (the GUI showed its last target)
    shown = ''
    import json
    if a.target_file:
        a.target = Path(a.target_file).read_text(encoding='utf-8')
    if a.target:
        spec = json.loads(a.target)
        form = getattr(getattr(window, 'phase1_tab', None), '_target_form', None)  # noqa: SLF001
        if form is not None and hasattr(form, 'apply_spec'):
            form.apply_spec(spec)
            shown = json.dumps(form.spec(), sort_keys=True) if hasattr(form, 'spec') else ''
        else:
            print('The pyCamSet GUI has no target form to set; set the target by hand: ' + a.target, flush=True)
    window.switch_to_tab(TAB_PHASE1)
    if a.dry_run:
        nb = window._notebook  # noqa: SLF001 - read only, to report what is shown
        print(f'PYCAMSET_GUI_READY tab="{nb.tabText(nb.currentIndex())}" images="{folder}" target={shown}', flush=True)
        window.close()
        return 0
    return app.exec()


if __name__ == '__main__':
    sys.exit(main())
