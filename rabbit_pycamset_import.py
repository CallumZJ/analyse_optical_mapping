#!/usr/bin/env python3
'''
Purpose: Take in a pyCamSet camera set made outside the app (the pyCamSet GUI) as a rabbit rig calibration, with the app's own checks

Run by the Reconstruction tab when the user links a .camset in the "pyCamSet camera
set" field:

    python rabbit_pycamset_import.py --job <job.json>

The job is the one rabbit_pycamset_calibrate.py reads (tile folders of the fit and
held-out recordings, their targets, the stated lens), plus 'camset': the camera set
the user exported. Nothing is solved for the cameras: they are taken as they are, and
the record says how well they explain the recordings:

- Fit: the target is found in the fit recordings' tiles as for a calibration. With
  the cameras held, the target's pose in each frame is solved (Levenberg-Marquardt
  over the six pose parameters, from an OpenCV solvePnP start in the view that sees
  the most points), and the reprojection error of every point is measured.
  Observations further than max(2.5 px, median + 5 robust sigma) are left out and the
  poses solved again, up to six times (like, not the same as, the calibration's own
  trimming).
- Held out: distances on the held-out recordings, from the cameras as they are
  (rabbit_pycamset_calibrate.holdout_check), the points first undistorted with each
  camera's own lens.

The result is written as calibration.json in the format of rabbit_pycamset_calibrate
(schema rabbit_calibration.result.v1), so the same gates decide what it may be used
for. The cameras keep their own focal lengths and lens centres; the record states
them, and a run compares them with the sparse model's.

Sources: pyCamSet (R. Laven and contributors), development branch: load_CameraSet,
targets and detection. OpenCV solvePnP and projectPoints. SciPy least_squares.
Umeyama 1991 (held-out similarity, via rabbit_pycamset_calibrate).
'''
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import sys
import time
from pathlib import Path

import numpy as np

# Run with python -I (as the tab runs its scripts), the script's own folder is not
# on the path; the calibration script beside it holds the shared steps. Appended,
# so that it shadows nothing, and no bytecode is written into the repository
sys.dont_write_bytecode = True
sys.path.append(str(Path(__file__).resolve().parent))
import rabbit_pycamset_calibrate as cal  # noqa: E402


def cameras_of(camset_path: Path, tile_sizes: dict | None = None) -> dict:
    """The four cameras of a camera set, by tile name: K, distortion, R and t (world to camera, metres).

    Only pinhole cameras with OpenCV distortion are taken (a telecentric camera set is
    refused), and with tile_sizes ({name: (width, height)}) each camera's image size must
    be its tile's: a camera set made on other tiles would put the lens centre elsewhere.
    """
    from pyCamSet.utils.saving import load_CameraSet
    cs = load_CameraSet(camset_path)
    names = sorted(cs.get_names()) if hasattr(cs, 'get_names') else sorted(cs.camera_dict.keys())
    if sorted(names) != sorted(cal.TILES):
        raise ValueError(f'The camera set holds the cameras {names}; it must hold exactly {list(cal.TILES)} '
                         '(open the folders the app wrote for View1 to View4, so that pyCamSet names the cameras '
                         'after them).')
    out = {}
    for name in cal.TILES:
        c = cs[name] if hasattr(cs, '__getitem__') else cs.camera_dict[name]
        if type(c).__name__ != 'Camera':
            raise ValueError(f'Camera {name} of the camera set is a {type(c).__name__}; only pinhole cameras '
                             '(pyCamSet Camera) can be taken in.')
        if tile_sizes and name in tile_sizes:
            res = tuple(int(v) for v in np.asarray(c.res).ravel()[:2])
            if res != tuple(tile_sizes[name]):
                raise ValueError(f'Camera {name} of the camera set images {res[0]} x {res[1]} px, but its view is '
                                 f'{tile_sizes[name][0]} x {tile_sizes[name][1]} px: the camera set was made on '
                                 'other views. Make it on the views "Open in pyCamSet..." wrote.')
        K = np.asarray(c.intrinsic, dtype=float)
        e = np.asarray(c.extrinsic, dtype=float)
        d = np.zeros(5)
        dc = np.asarray(c.distortion_coefs, dtype=float).ravel()
        d[:min(5, dc.size)] = dc[:5]
        out[name] = {'cam': c, 'K': K, 'dist': d, 'R': e[:3, :3], 't': e[:3, 3]}
    return out


def project(cam: dict, R_t, t_t, X: np.ndarray) -> np.ndarray:
    """Pixels of target points X (metres) at target pose (R_t, t_t in the world), through one camera."""
    import cv2
    Xw = X @ R_t.T + t_t
    rv, _ = cv2.Rodrigues(cam['R'])
    uv, _ = cv2.projectPoints(Xw.reshape(-1, 1, 3), rv, cam['t'].reshape(3, 1), cam['K'], cam['dist'])
    return uv.reshape(-1, 2)


def solve_poses(data: np.ndarray, cams: dict, target) -> np.ndarray:
    """With the cameras held, the target pose of each frame; returns the residual (px) of every row of data."""
    import cv2
    from scipy.optimize import least_squares
    pts = np.asarray(target.point_data, dtype=float)
    ncols = data.shape[1]
    keys = data[:, 2:ncols - 2].astype(int)
    X_all = pts[tuple(keys.T)]
    names = list(cal.TILES)
    r = np.full(len(data), np.nan)
    for im in np.unique(data[:, 1].astype(int)):
        rows = np.where(data[:, 1].astype(int) == im)[0]
        ci = data[rows, 0].astype(int)
        best = np.bincount(ci, minlength=4).argmax()
        sel = rows[ci == best]
        if len(sel) < 6:
            continue
        cam = cams[names[best]]
        ok, rv, tv = cv2.solvePnP(X_all[sel], data[sel, -2:].astype(float), cam['K'], cam['dist'],
                                  flags=cv2.SOLVEPNP_ITERATIVE)
        if not ok:
            continue
        Rc, _ = cv2.Rodrigues(rv)
        # target -> camera = (world -> camera) o (target -> world)
        R_t = cam['R'].T @ Rc
        t_t = cam['R'].T @ (tv.ravel() - cam['t'])

        def resid(p):
            Rt, _ = cv2.Rodrigues(p[:3])
            out = []
            for k in range(4):
                s = rows[ci == k]
                if len(s):
                    out.append((project(cams[names[k]], Rt, p[3:], X_all[s]) - data[s, -2:]).ravel())
            return np.concatenate(out)

        p0 = np.concatenate([cv2.Rodrigues(R_t)[0].ravel(), t_t])
        sol = least_squares(resid, p0, method='lm', max_nfev=200)
        Rt, _ = cv2.Rodrigues(sol.x[:3])
        for k in range(4):
            s = rows[ci == k]
            if len(s):
                r[s] = np.linalg.norm(project(cams[names[k]], Rt, sol.x[3:], X_all[s]) - data[s, -2:], axis=1)
    return r


def undistorted(data: np.ndarray, cams: dict) -> np.ndarray:
    """The detections undistorted by each camera's own lens, in pixels of one focal length.

    holdout_check divides both pixel axes by one focal length (fx), so the points are
    put into a camera with fx on both axes and the camera's own centre: a camera set
    with fx different from fy then gives the right rays.
    """
    import cv2
    out = data.copy().astype(float)
    names = list(cal.TILES)
    for k in range(4):
        s = data[:, 0].astype(int) == k
        if s.any():
            c = cams[names[k]]
            P = np.array([[c['K'][0, 0], 0.0, c['K'][0, 2]], [0.0, c['K'][0, 0], c['K'][1, 2]], [0.0, 0.0, 1.0]])
            u = cv2.undistortPoints(data[s, -2:].reshape(-1, 1, 2).astype(float), c['K'], c['dist'], P=P)
            out[s, -2:] = u.reshape(-1, 2)
    return out


def tile_sizes(recs: list) -> dict:
    """(width, height) of each tile of the first fit recording, from its first image."""
    import cv2
    fit = [r for r in recs if r['role'] == 'fit']
    out = {}
    if not fit:
        return out
    for name in cal.TILES:
        files = sorted(Path(fit[0]['tile_dir'], name).glob('*.tif*'))
        if files:
            im = cv2.imread(str(files[0]), cv2.IMREAD_UNCHANGED)
            if im is not None:
                out[name] = (int(im.shape[1]), int(im.shape[0]))
    return out


def run(job: dict) -> dict:
    t0 = time.time()
    threads = int(job.get('threads', 6))
    out_dir = Path(job['output_dir'])
    camset_path = Path(job['camset'])
    recs = job['recordings']
    cams = cameras_of(camset_path, tile_sizes(recs))
    fit = [r for r in recs if r['role'] == 'fit']
    if not fit:
        raise ValueError('The job has no recording to check the camera set on.')
    cal.log('PROGRESS 1 Finding the target in the fit recordings')
    chunks, offset, target, rec_out = [], 0, None, []
    for r in fit:
        d, names, _, target = cal.detect(r, threads)
        if list(names) != list(cal.TILES):
            raise ValueError('Expected the views View1 to View4, found '
                             + ', '.join(n.replace('tile', 'View') for n in names) + '.')
        if len(d):
            d = d.copy()
            d[:, 1] += offset
            chunks.append(d)
        offset += int(r['n_frames'])
        rec_out.append({'name': r['name'], 'role': 'fit', 'points_detected': int(len(d))})
    data = np.vstack(chunks) if chunks else np.empty((0, 6))
    if len(data) == 0:
        raise ValueError('The target was not found in any frame. Check the target type and its number of squares.')
    cal.log('PROGRESS 2 Solving the target poses with the camera set held')
    keep = np.ones(len(data), bool)
    rounds = 0
    for rounds in range(1, 7):
        r = solve_poses(data[keep], cams, target)
        good = np.isfinite(r)
        med = float(np.median(r[good])) if good.any() else float('nan')
        sigma = 1.4826 * float(np.median(np.abs(r[good] - med))) if good.any() else float('nan')
        thr = max(2.5, med + 5 * sigma)
        drop = ~good | (r > thr)
        cal.log(f'  round {rounds}: {int(good.sum())} points, median {med:.2f} px, threshold {thr:.2f} px, dropped {int(drop.sum())}')
        if not drop.any():
            break
        idx = np.where(keep)[0]
        keep[idx[drop]] = False
    used = data[keep]
    r = solve_poses(used, cams, target)
    ok = np.isfinite(r)
    used, r = used[ok], r[ok]
    if len(r) == 0:
        raise ValueError('The camera set does not explain any detected target point.')
    records = []
    cam_col = used[:, 0].astype(int)
    for i, name in enumerate(cal.TILES):
        sel = cam_col == i
        c = cams[name]
        rec = cal.camera_record(c['cam'], name, float(c['K'][0, 0]), float(c['dist'][0]),
                                {name: (float(c['K'][0, 2]), float(c['K'][1, 2]))}, int(sel.sum()),
                                len(set(used[sel, 1].astype(int))),
                                math.sqrt(float((r[sel] ** 2).mean())) if sel.any() else float('nan'))
        rec['focal_px_y'] = float(c['K'][1, 1])
        rec['distortion'] = c['dist'].tolist()
        z = float(rec['t_world_to_cam_mm'][2])
        rec['depth_at_target_mm'] = z
        rec['mm_per_px_at_target'] = z / rec['focal_px']
        records.append(rec)
    if any(not math.isfinite(q['rmse_px']) for q in records):
        raise ValueError('A view of the camera set explains none of its target points: '
                         + ', '.join(f"{q['tile']} {q['points']}" for q in records))
    cal.log('PROGRESS 3 Checking distances on the held-out recordings')
    checks = []
    for rec in [q for q in recs if q['role'] == 'holdout']:
        d, _, _, tgt = cal.detect(rec, threads)
        chk = cal.holdout_check(undistorted(d, cams), list(cal.TILES), tgt, records) if len(d) else \
            {'frames_used': 0, 'points': 0}
        chk.update({'name': rec['name'], 'target': rec['target'], 'points_detected': int(len(d))})
        cal.log(f'  {rec["name"]}: {json.dumps({k: v for k, v in chk.items() if k != "target"})}')
        checks.append(chk)
        rec_out.append({'name': rec['name'], 'role': 'holdout', 'points_detected': int(len(d))})
    self_check = cal.holdout_check(undistorted(used, cams), list(cal.TILES), target, records)
    cal.log('PROGRESS 4 Saving')
    shutil.copyfile(camset_path, out_dir / 'cameras.camset')
    digest = hashlib.sha256(camset_path.read_bytes()).hexdigest()
    focal = [q['focal_px'] for q in records]
    return {
        'schema': cal.SCHEMA,
        'lens': {'focal_px': float(np.mean(focal)), 'k1': float(np.mean([q['k1'] for q in records])),
                 'source': 'the linked pyCamSet camera set (each camera keeps its own lens)',
                 'focal_px_per_camera': focal},
        'imported_camset': {'path': str(camset_path), 'sha256': digest},
        'lens_centre_frame_px': job.get('lens_centre_frame_px'),
        'pycamset': {'checkout': job.get('pycamset_checkout', ''), 'commit': job.get('pycamset_commit', '')},
        'pixel_pitch_um': job.get('pixel_pitch_um'),
        'focal_mm_stated': float(np.mean(focal)) * float(job.get('pixel_pitch_um') or 0) / 1000,
        'target': fit[0]['target'],
        'preprocess': job.get('preprocess'),
        'recordings': rec_out,
        'observations': {'detected': int(len(data)), 'used': int(len(used)),
                         'kept_fraction': float(len(used) / len(data)), 'rounds': rounds},
        'residual': {'rmse_px': math.sqrt(float((r ** 2).mean())), 'median_px': float(np.median(r)),
                     'p95_px': float(np.percentile(r, 95))},
        'cameras': records,
        'rig': cal.rig_geometry(records),
        'lens_profile': [],
        'holdout': checks,
        'self_check': self_check,
        'elapsed_s': time.time() - t0,
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--job', required=True)
    a = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    job = json.loads(Path(a.job).read_text(encoding='utf-8'))
    if job.get('pycamset_checkout'):
        sys.path.insert(0, job['pycamset_checkout'])
    out = Path(job['output_dir'])
    try:
        result = run(job)
    except Exception as exc:  # the tab shows this text and keeps the folder for inspection
        (out / 'calibration_error.txt').write_text(f'{type(exc).__name__}: {exc}\n', encoding='utf-8')
        cal.log(f'CALIBRATION FAILED: {type(exc).__name__}: {exc}')
        return 2
    (out / 'calibration.json').write_text(json.dumps(result, indent=1, allow_nan=False), encoding='utf-8')
    cal.log('CALIBRATION DONE')
    return 0


if __name__ == '__main__':
    sys.exit(main())
