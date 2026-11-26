#!/usr/bin/env python3
'''
Purpose: Calibrate the four-view rabbit rig with pyCamSet: rig poses in mm, residuals, held-out distance checks

Run by the Reconstruction tab (rabbit_calibration.m), with the Python and the
pyCamSet checkout the user chose:

    python rabbit_pycamset_calibrate.py --job <job.json>

The job names folders of tile images (<dir>/tile1 .. tile4, left to right in the
camera frame; the two outer tiles already flipped left-right), the calibration
target of each recording and the stated lens. Nothing is written outside the
job's output folder and no source file is changed.

What is solved and why. The tiles are narrow crops of a long lens (about 8000 px
over about 400 px), so a free pinhole solve is badly conditioned: pyCamSet's
closed-form seed (Zhang 2000) reports that no camera fits, and a free bundle
adjustment on this rig trades focal length against distance and sends the
distortion to values of several hundred. The focal length is therefore a stated
input, and pyCamSet's bundle adjustment solves the rig: the pose of each virtual
camera and of the target in each frame. Magnification, and with it the scale at
the heart, is fixed by the target's size whatever focal length is stated: a
different focal length moves the cameras further away in proportion. The profile
written with the result shows how little the data constrain the focal length.

A mirror view is a true pinhole view once its image parity is undone (Baker and
Nayar 1999, single viewpoint), which is what the left-right flip of the outer
tiles does, so each view is one virtual camera with a proper rotation.

Sources: pyCamSet (R. Laven and contributors), development branch: PuzzleBoardCube
target, detection, TemplateBundleHandler bundle adjustment. PuzzleBoard: Stelldinger
et al. 2024. Similarity fit of two point sets: Umeyama 1991.
'''
from __future__ import annotations

import argparse
import itertools
import json
import math
import pickle
import sys
import time
from pathlib import Path

import numpy as np

SCHEMA = 'rabbit_calibration.result.v1'
TILES = ('tile1', 'tile2', 'tile3', 'tile4')


def log(text: str) -> None:
    print(text, flush=True)


def build_target(spec: dict):
    """The pyCamSet target a job names; its edge length is in mm, its points in metres."""
    from pyCamSet.calibration_targets.core.target_registry import build_target as make
    return make({'type': spec['type'], 'n_points': int(spec['n_points']), 'length': float(spec['edge_mm'])})


def prep_of(spec: dict) -> dict:
    """Detector preparation for a target: the job's values, else what worked on this rig."""
    default = {'PuzzleBoardCube': (0.5, 0.5, 'upper_byte')}.get(spec['type'], (1.0, 0.5, 'min_max'))
    return {'scale': float(spec.get('scale') or default[0]), 'gamma': float(spec.get('gamma') or default[1]),
            'loader': str(spec.get('loader') or default[2])}


def detect(rec: dict, threads: int):
    """Detect one recording's target. Returns (rows, cam_names, resolutions, target)."""
    from pyCamSet.calibration.camera_calibrator import detect_datapoints_in_imfile
    target = build_target(rec['target'])
    if rec.get('preprocessed'):
        # The tiles were binarised by the app (Sauvola, rabbit_sauvola.m): pyCamSet's own
        # rescale and gamma are left off, as they change nothing on a binary image
        det, res = detect_datapoints_in_imfile(Path(rec['tile_dir']), target, caching=False, threads=threads,
                                               rescale_and_gamma=False)
    else:
        p = prep_of(rec['target'])
        det, res = detect_datapoints_in_imfile(
            Path(rec['tile_dir']), target, caching=False, threads=threads, rescale_and_gamma=True,
            preprocessing_scale=p['scale'], preprocessing_gamma=p['gamma'], preprocessing_loader=p['loader'])
    data = det.get_data()
    return (np.empty((0, 6)) if data is None else data), list(det.cam_names), res, target


def lens_blocks(cams: list, tile_pp: dict, f: float, k1: float) -> tuple:
    """pyCamSet's two ways of pinning a lens: for the seed, and for the bundle adjustment."""
    seed, solve = {}, {}
    for name in cams:
        x, y = tile_pp[name]
        d = np.array([k1, 0.0, 0.0, 0.0, 0.0])
        seed[name] = {'int': np.array([[f, 0.0, x], [0.0, f, y], [0.0, 0.0, 1.0]]), 'dst': d}
        solve[name] = {'int': np.concatenate([[f, x, f, y], d])}
    return seed, solve


def solve_rig(data, cams, res, target, tile_pp, f, k1, threads, max_ims):
    """pyCamSet's bundle adjustment with the lens held: rig and target poses are solved."""
    from pyCamSet.calibration.camera_calibrator import run_initial_calibration
    from pyCamSet.calibration_targets.core.target_detections import TargetDetection
    from pyCamSet.workflow import phase3
    det = TargetDetection(cams, data, max_ims=max_ims)
    seed, fixed = lens_blocks(cams, tile_pp, f, k1)
    start = run_initial_calibration(det, target, res, save=False, fixed_params=seed)
    options = {'max_nfev': 40, 'outliers': 'n', 'verbosity': 0, 'ref_cam': 0, 'ref_pose': 0}
    handler, opt, out, stats = phase3.solve(start, det, target, fixed_params=fixed, options=options, threads=threads)
    used = handler._optimised_detection().get_data()
    r = np.linalg.norm(opt.fun.reshape(-1, 2), axis=1)
    if len(r) != len(used):
        raise RuntimeError('pyCamSet returned a residual per observation that does not match its detections.')
    return handler, out, used, r


def trim_outliers(data, cams, res, target, tile_pp, f, k1, threads, max_ims, floor_px=2.5, rounds=6):
    """Drop observations further than max(floor, 5 robust sigma) from the solved rig, repeatedly.

    PuzzleBoard decoding on a cube occasionally joins two faces into one window; those
    points are hundreds of pixels out and pull the solve away from every good point.

    Returns (points, trace, solution). solution is None when the rounds converged, and the
    caller solves the kept points once more; otherwise see below.
    """
    n_start = len(data)
    trace = []
    best = None
    solution = None
    for k in range(rounds):
        handler, out, used, r = solve_rig(data, cams, res, target, tile_pp, f, k1, threads, max_ims)
        med = float(np.median(r))
        # Each round seeds the rig afresh, and a seed can land in a worse minimum
        # (June 2026: 0.56 px, 0.61 px, then 11.5 px). Trimming against that solve
        # would drop good points, and solving the same points again lands there again,
        # so the best round's solve, and the points it kept, are the result.
        if best is not None and med > max(2 * best['med'], best['med'] + 1.0):
            trace.append({'round': k + 1, 'observations': int(len(r)), 'median_px': med,
                          'threshold_px': None, 'dropped': 0, 'rejected': True})
            data, solution = best['data'], best['solution']
            log(f'  outlier round {k + 1}: {len(r)} points, median {med:.2f} px: the solve landed in a worse '
                f'minimum; kept the solve of round {best["round"]} and its {len(data)} points')
            break
        thr = max(floor_px, 5 * 1.4826 * float(np.median(np.abs(r - med))))
        keep = r <= thr
        trace.append({'round': k + 1, 'observations': int(len(r)), 'median_px': med,
                      'threshold_px': thr, 'dropped': int((~keep).sum()), 'rejected': False})
        log(f'  outlier round {k + 1}: {len(r)} points, median {med:.2f} px, threshold {thr:.2f} px, dropped {(~keep).sum()}')
        if best is None or med <= best['med']:
            best = {'round': k + 1, 'med': med, 'data': used[keep],
                    'solution': (handler, out, used[keep], r[keep])}
        if keep.all():
            data = used
            break
        data = used[keep]
    return data, {'kept_fraction': len(data) / max(n_start, 1), 'rounds': trace}, solution


def focal_sweep(data, cams, res, target, tile_pp, f, k1, threads, max_ims):
    """The rig solved again across the focal lengths the data leave open.

    Distance from each camera to the target's middle at each focal length: the
    tab works out from these how far mm per pixel moves, per view.
    """
    values = [f * s for s in (0.75, 0.875, 1.0, 1.125, 1.25, 1.5, 1.75, 2.0)]
    rmse, depth = [], []
    for value in values:
        _, out, _, r = solve_rig(data, cams, res, target, tile_pp, value, k1, threads, max_ims)
        rmse.append(math.sqrt(float((r ** 2).mean())))
        depth.append([float(np.asarray(out[n].extrinsic)[2, 3]) * 1000 for n in cams])
    return {'focal_px': values, 'k1': k1, 'rmse_px': rmse, 'depth_mm': depth}


def camera_record(cam, name, f, k1, tile_pp, n_pts, n_images, rmse):
    e = np.asarray(cam.extrinsic, dtype=float)
    R, t = e[:3, :3], e[:3, 3]
    c = -R.T @ t
    return {'tile': name, 'focal_px': f, 'k1': k1, 'pp_tile_px': list(map(float, tile_pp[name])),
            'R_world_to_cam': R.tolist(), 't_world_to_cam_mm': (1000 * t).tolist(), 'centre_mm': (1000 * c).tolist(),
            'axis_world': R[2, :].tolist(), 'det_R': float(np.linalg.det(R)), 'points': int(n_pts),
            'images': int(n_images), 'rmse_px': float(rmse)}


def rig_geometry(cams):
    C = np.array([c['centre_mm'] for c in cams])
    A = np.array([c['axis_world'] for c in cams])
    pairs = list(itertools.combinations(range(len(cams)), 2))
    return {'baselines_mm': {f'{i + 1}-{j + 1}': float(np.linalg.norm(C[i] - C[j])) for i, j in pairs},
            'axis_angles_deg': {f'{i + 1}-{j + 1}': float(np.degrees(np.arccos(np.clip(A[i] @ A[j], -1, 1)))) for i, j in pairs}}


def triangulate(rays: list) -> np.ndarray:
    """Least-squares meeting point of rays (centre, unit direction)."""
    M, b = np.zeros((3, 3)), np.zeros(3)
    for c, d in rays:
        P = np.eye(3) - np.outer(d, d)
        M += P
        b += P @ c
    return np.linalg.solve(M, b)


def fit_scale(a: np.ndarray, b: np.ndarray) -> tuple:
    """Umeyama (1991): s, R, t minimising |b - (s R a + t)|. Returns (s, rms residual)."""
    ma, mb = a.mean(0), b.mean(0)
    A, B = a - ma, b - mb
    U, S, Vt = np.linalg.svd(B.T @ A / len(a))
    D = np.eye(3)
    if np.linalg.det(U) * np.linalg.det(Vt) < 0:
        D[2, 2] = -1
    R = U @ D @ Vt
    s = float(np.trace(np.diag(S) @ D) / (A ** 2).sum(1).mean())
    res = B - s * (R @ A.T).T
    return s, float(np.sqrt((res ** 2).sum(1).mean()))


def holdout_check(data, cams, target, cam_records, min_points=12):
    """Distances on a target the rig never saw: triangulate its points, compare with the target.

    The rig is held. Each frame's points seen in two or more views are triangulated in
    mm, and one similarity is fitted to the target's own geometry: its scale is the
    ratio of the distances the rig recovers to the stated size of this target.
    """
    pts_mm = 1000 * np.asarray(target.point_data, dtype=float)
    ncols = data.shape[1]
    keys = data[:, 2:ncols - 2].astype(int)
    frames = []
    by_cam = {i: c for i, c in enumerate(cam_records)}
    for im in np.unique(data[:, 1].astype(int)):
        rows = data[:, 1].astype(int) == im
        groups = {}
        for row, key in zip(data[rows], keys[rows]):
            groups.setdefault(tuple(key), []).append(row)
        X, Y = [], []
        for key, members in groups.items():
            if len({int(m[0]) for m in members}) < 2:
                continue
            rays = []
            for m in members:
                c = by_cam[int(m[0])]
                x = (m[-2] - c['pp_tile_px'][0]) / c['focal_px']
                y = (m[-1] - c['pp_tile_px'][1]) / c['focal_px']
                R = np.array(c['R_world_to_cam'])
                d = R.T @ np.array([x, y, 1.0])
                rays.append((np.array(c['centre_mm']), d / np.linalg.norm(d)))
            X.append(triangulate(rays))
            Y.append(pts_mm[key])
        if len(X) < min_points:
            continue
        X, Y = np.array(X), np.array(Y)
        s, res = fit_scale(Y, X)
        frames.append({'frame': int(im), 'points': int(len(X)), 'scale': s, 'residual_mm': res})
    if not frames:
        return {'frames_used': 0, 'points': 0}
    good = [fr for fr in frames if fr['residual_mm'] <= max(0.5, 3 * float(np.median([q['residual_mm'] for q in frames])))]
    scale = np.array([fr['scale'] for fr in good])
    q1, med, q3 = np.percentile(scale, [25, 50, 75])
    return {'frames_used': len(good), 'frames_rejected': len(frames) - len(good), 'points': int(sum(fr['points'] for fr in good)),
            'scale_median': float(med), 'scale_iqr': float(q3 - q1), 'scale_error_percent': float(100 * (med - 1)),
            'scale_se_percent': float(100 * 1.2533 * 0.7413 * (q3 - q1) / math.sqrt(len(good))),
            'residual_mm_median': float(np.median([fr['residual_mm'] for fr in good])),
            'edge_recovered_mm': float(med * float(target.point_data.max() - target.point_data.min()) * 1000)}


def run(job: dict) -> dict:
    t0 = time.time()
    threads = int(job.get('threads', 6))
    out_dir = Path(job['output_dir'])
    lens = job['lens']
    f, k1 = float(lens['focal_px']), float(lens.get('k1', 0.0))
    tile_pp = {k: tuple(v) for k, v in job['tile_pp'].items()}
    recs = job['recordings']
    fit = [r for r in recs if r['role'] == 'fit']
    if not fit:
        raise ValueError('The job has no recording to fit.')
    if len({json.dumps({k: r['target'][k] for k in ('type', 'n_points', 'edge_mm')}, sort_keys=True) for r in fit}) != 1:
        raise ValueError('The recordings to fit must all show the same target.')
    log('PROGRESS 1 Finding the target in the recordings')
    chunks, offset, cams, res, target = [], 0, None, None, None
    rec_out = []
    for r in fit:
        d, cams, res, target = detect(r, threads)
        log(f'  {r["name"]}: {len(d)} points')
        if len(d):
            d = d.copy()
            d[:, 1] += offset
            chunks.append(d)
        offset += int(r['n_frames'])
        rec_out.append({'name': r['name'], 'role': 'fit', 'points_detected': int(len(d))})
    data = np.vstack(chunks) if chunks else np.empty((0, 6))
    if len(data) == 0:
        raise ValueError('The target was not found in any frame. Check the target type and its number of squares.')
    if list(cams) != list(TILES):
        raise ValueError('Expected the views View1 to View4, found '
                         + ', '.join(c.replace('tile', 'View') for c in cams) + '.')
    seen = [int((data[:, 0].astype(int) == i).sum()) for i in range(4)]
    if min(seen) == 0:
        raise ValueError(f'A view has no target points (points per view {seen}).')
    log('PROGRESS 2 Solving the rig with pyCamSet')
    trimmed, trim, solution = trim_outliers(data, cams, res, target, tile_pp, f, k1, threads, offset)
    if solution is None:
        solution = solve_rig(trimmed, cams, res, target, tile_pp, f, k1, threads, offset)
    handler, out, used, r = solution
    cam_col = used[:, 0].astype(int)
    records = []
    for i, name in enumerate(cams):
        sel = cam_col == i
        records.append(camera_record(out[name], name, f, k1, tile_pp, sel.sum(), len(set(used[sel, 1].astype(int))),
                                     math.sqrt(float((r[sel] ** 2).mean()))))
    depth = []
    for c in records:
        t = np.array(c['t_world_to_cam_mm'])
        depth.append(float(t[2]))  # the target's middle sits near the world origin
    for c, z in zip(records, depth):
        c['depth_at_target_mm'] = z
        c['mm_per_px_at_target'] = z / f
    log('PROGRESS 3 Measuring how well the data fix the lens')
    profile = []
    for scale in (0.75, 1.0, 1.25, 1.5, 2.0):
        for k in (-1.0, 0.0, 1.0):
            _, _, _, rr = solve_rig(trimmed, cams, res, target, tile_pp, f * scale, k, threads, offset)
            profile.append({'focal_px': f * scale, 'k1': k, 'rmse_px': math.sqrt(float((rr ** 2).mean()))})
    sweep = focal_sweep(trimmed, cams, res, target, tile_pp, f, k1, threads, offset)
    log('PROGRESS 4 Checking distances on the held-out recordings')
    checks = []
    for rec in [q for q in recs if q['role'] == 'holdout']:
        d, _, _, tgt = detect(rec, threads)
        chk = holdout_check(d, cams, tgt, records) if len(d) else {'frames_used': 0, 'points': 0}
        chk.update({'name': rec['name'], 'target': rec['target'], 'points_detected': int(len(d))})
        log(f'  {rec["name"]}: {json.dumps({k: v for k, v in chk.items() if k != "target"})}')
        checks.append(chk)
        rec_out.append({'name': rec['name'], 'role': 'holdout', 'points_detected': int(len(d))})
    self_check = holdout_check(trimmed, cams, target, records)
    log('PROGRESS 5 Saving')
    out.save(out_dir / 'cameras.camset')
    with open(out_dir / 'detections.pkl', 'wb') as fid:
        pickle.dump({'data': trimmed, 'cam_names': cams}, fid)
    return {
        'schema': SCHEMA,
        'pycamset': {'checkout': job.get('pycamset_checkout', ''), 'commit': job.get('pycamset_commit', '')},
        'lens': {'focal_px': f, 'k1': k1, 'lens_centre_frame_px': job.get('lens_centre_frame_px'),
                 'source': lens.get('source', '')},
        'pixel_pitch_um': job.get('pixel_pitch_um'),
        'focal_mm_stated': f * float(job.get('pixel_pitch_um') or 0) / 1000,
        'target': fit[0]['target'],
        'preprocess': job.get('preprocess'),
        'recordings': rec_out,
        'observations': {'detected': int(len(data)), 'used': int(len(used)), 'kept_fraction': trim['kept_fraction'], 'rounds': trim['rounds']},
        'residual': {'rmse_px': math.sqrt(float((r ** 2).mean())), 'median_px': float(np.median(r)), 'p95_px': float(np.percentile(r, 95))},
        'cameras': records,
        'rig': rig_geometry(records),
        'lens_profile': profile,
        'focal_sweep': sweep,
        'holdout': checks,
        'self_check': self_check,
        'elapsed_s': time.time() - t0,
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--job', required=True)
    a = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')  # the log is read as UTF-8, whatever the console uses
    job = json.loads(Path(a.job).read_text(encoding='utf-8'))
    if job.get('pycamset_checkout'):
        sys.path.insert(0, job['pycamset_checkout'])
    out = Path(job['output_dir'])
    try:
        result = run(job)
    except Exception as exc:  # the tab shows this text and keeps the folder for inspection
        (out / 'calibration_error.txt').write_text(f'{type(exc).__name__}: {exc}\n', encoding='utf-8')
        log(f'CALIBRATION FAILED: {type(exc).__name__}: {exc}')
        return 2
    (out / 'calibration.json').write_text(json.dumps(result, indent=1, allow_nan=False), encoding='utf-8')
    log('CALIBRATION DONE')
    return 0


if __name__ == '__main__':
    sys.exit(main())
