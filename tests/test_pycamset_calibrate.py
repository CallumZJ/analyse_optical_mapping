'''
Purpose: Synthetic checks of rabbit_pycamset_calibrate.py with known cameras, target size and scale

The pure geometry runs anywhere. The tests that call pyCamSet's solver need
OM_PYCAMSET_CHECKOUT, and are skipped without it.
'''
import importlib.util
import os
import sys
from pathlib import Path

import numpy as np
import pytest

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('rabbit_pycamset_calibrate', HERE / 'rabbit_pycamset_calibrate.py')
rc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc)

CHECKOUT = os.environ.get('OM_PYCAMSET_CHECKOUT', '')
needs_pycamset = pytest.mark.skipif(not CHECKOUT, reason='OM_PYCAMSET_CHECKOUT is not set')


def rot(axis, deg):
    a = np.radians(deg)
    c, s = np.cos(a), np.sin(a)
    return {'x': np.array([[1, 0, 0], [0, c, -s], [0, s, c]]),
            'y': np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]),
            'z': np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])}[axis]


def rig(distance_mm=1000.0):
    """Four cameras about the origin, 90 degrees apart, looking at it (world to camera)."""
    out = []
    for yaw in (0, 90, 180, 270):
        R = rot('y', yaw)
        t = np.array([0, 0, distance_mm])
        out.append((R, t))
    return out


class CubeStub:
    """A target with the fields holdout_check reads: points in metres, 6 faces x n x 2 keys."""

    def __init__(self, edge_m=0.03, n=6):
        u = np.linspace(-edge_m / 2, edge_m / 2, n)
        g = np.array([[x, y] for x in u for y in u])
        faces = []
        for axis in range(3):
            for sign in (-1, 1):
                p = np.insert(g, axis, sign * edge_m / 2, axis=1)
                faces.append(p)
        self.point_data = np.array(faces)


def project(target, cams, f, poses, noise=0.0, seed=0):
    rng = np.random.default_rng(seed)
    rows = []
    pts = target.point_data.reshape(-1, 3) * 1000
    keys = [(a, b) for a in range(target.point_data.shape[0]) for b in range(target.point_data.shape[1])]
    for im, (Rp, tp) in enumerate(poses):
        X = pts @ Rp.T + tp
        for c, (R, t) in enumerate(cams):
            Y = X @ R.T + t
            uv = f * Y[:, :2] / Y[:, 2:3] + 200
            normal_ok = Y[:, 2] < np.median(Y[:, 2]) + 5
            for k, (key, p, ok) in enumerate(zip(keys, uv, normal_ok)):
                if ok:
                    rows.append([c, im, key[0], key[1], *(p + rng.normal(0, noise, 2))])
    return np.array(rows, dtype=float)


def cam_record(R, t, f, pp=(200.0, 200.0)):
    c = -R.T @ t
    return {'focal_px': f, 'pp_tile_px': list(pp), 'R_world_to_cam': R.tolist(), 'centre_mm': c.tolist()}


def poses(n=12, seed=1):
    rng = np.random.default_rng(seed)
    out = []
    for k in range(n):
        Rp = rot('x', rng.uniform(-30, 30)) @ rot('y', rng.uniform(-180, 180)) @ rot('z', rng.uniform(-30, 30))
        out.append((Rp, rng.uniform(-3, 3, 3)))
    return out


def test_similarity_recovers_a_known_scale():
    a = np.random.default_rng(0).normal(size=(20, 3))
    R = rot('z', 30) @ rot('x', 40)
    b = 3.7 * a @ R.T + np.array([1, 2, 3])
    s, res = rc.fit_scale(a, b)
    assert abs(s - 3.7) < 1e-9 and res < 1e-9


def test_triangulation_meets_at_the_point():
    p = np.array([1.0, 2.0, 3.0])
    rays = []
    for c in ([10, 0, 0], [0, 10, 0], [0, 0, 10]):
        c = np.array(c, float)
        d = (p - c) / np.linalg.norm(p - c)
        rays.append((c, d))
    assert np.linalg.norm(rc.triangulate(rays) - p) < 1e-9


@pytest.mark.parametrize('true_edge_m', [0.03, 0.027])
def test_holdout_sees_a_wrongly_stated_size(true_edge_m):
    """The rig is right; a cube really 27 mm reads 10 percent small against a stated 30 mm."""
    cams = rig()
    f = 8000.0
    truth = CubeStub(true_edge_m)
    stated = CubeStub(0.03)
    data = project(truth, cams, f, poses(), noise=0.1)
    out = rc.holdout_check(data, [0, 1, 2, 3], stated, [cam_record(R, t, f) for R, t in cams])
    assert out['frames_used'] >= 10
    assert abs(out['scale_median'] - true_edge_m / 0.03) < 0.003


def test_holdout_sees_a_drifted_camera():
    """One camera turned by 2 degrees after calibration: the shape residual grows."""
    cams = rig()
    f = 8000.0
    target = CubeStub()
    good = rc.holdout_check(project(target, cams, f, poses()), [0, 1, 2, 3], target, [cam_record(R, t, f) for R, t in cams])
    moved = list(cams)
    moved[1] = (rot('x', 2.0) @ cams[1][0], cams[1][1])
    bad = rc.holdout_check(project(target, moved, f, poses()), [0, 1, 2, 3], target, [cam_record(R, t, f) for R, t in cams])
    assert good['residual_mm_median'] < 0.01
    # A turn about the camera's own centre hardly changes distances; the shape
    # residual shows it. Comparing the rig with the sparse model is the real drift check.
    assert bad['residual_mm_median'] > 5 * good['residual_mm_median']


def test_lens_blocks_use_pycamset_layout():
    seed, fixed = rc.lens_blocks(['tile1'], {'tile1': (-500.0, 399.5)}, 8000.0, 0.0)
    assert seed['tile1']['int'][0, 2] == -500.0
    assert list(fixed['tile1']['int'][:4]) == [8000.0, -500.0, 8000.0, 399.5]


def test_trim_keeps_last_converged_points_when_a_round_diverges(monkeypatch):
    """A round whose fresh solve lands in a worse minimum must not trim good points."""
    data = np.arange(600, dtype=float).reshape(100, 6)
    calls = []

    def fake_solve(d, *args):
        calls.append(len(d))
        r = np.full(len(d), 0.5)
        if len(calls) == 1:
            r[:5] = 50.0          # five real outliers in the first solve
        else:
            r[:] = 20.0           # the second solve diverged
        return None, None, d, r

    monkeypatch.setattr(rc, 'solve_rig', fake_solve)
    kept, trim, solution = rc.trim_outliers(data, list(rc.TILES), None, None, None, 8000.0, 0.0, 1, 1)
    assert calls == [100, 95]
    # the first round's solve, without its five outliers, is the result
    assert len(kept) == 95 and trim['kept_fraction'] == 0.95
    assert solution is not None and len(solution[2]) == 95 and np.all(solution[3] == 0.5)
    assert trim['rounds'][-1]['rejected'] and not trim['rounds'][0]['rejected']


@needs_pycamset
def test_rig_solve_recovers_rig_from_detections():
    """pyCamSet's solve with the lens held, on synthetic detections of its own target."""
    sys.path.insert(0, CHECKOUT)
    from pyCamSet.calibration_targets.puzzleboard_cube import PuzzleBoardCube
    target = PuzzleBoardCube(n_points=7, length=30.0)
    f = 8000.0
    cams_true = rig()
    px = target.point_data.reshape(-1, 3) * 1000
    shape = target.point_data.shape[:-1]
    keys = np.array(np.unravel_index(np.arange(np.prod(shape)), shape)).T
    rows = []
    for im, (Rp, tp) in enumerate(poses(30)):
        X = px @ Rp.T + tp
        for c, (R, t) in enumerate(cams_true):
            Y = X @ R.T + t
            uv = f * Y[:, :2] / Y[:, 2:3] + 200
            n = Y[:, 2] < np.percentile(Y[:, 2], 40)
            for key, p in zip(keys[n], uv[n]):
                rows.append([c, im, *key, *p])
    data = np.array(rows, float)
    # a few decoding mistakes, far from where they belong
    data[::97, -2:] += 150
    names = list(rc.TILES)
    res = [(400, 400)] * 4
    pp = {n: (200.0, 200.0) for n in names}
    kept, trim, solution = rc.trim_outliers(data, names, res, target, pp, f, 0.0, 2, 30)
    assert trim['kept_fraction'] > 0.9 and solution is None
    _, out, _, r = rc.solve_rig(kept, names, res, target, pp, f, 0.0, 2, 30)
    assert np.sqrt((r ** 2).mean()) < 0.1
    C = np.array([1000 * (-np.asarray(out[n].extrinsic)[:3, :3].T @ np.asarray(out[n].extrinsic)[:3, 3]) for n in names])
    d = [np.linalg.norm(C[i] - C[(i + 1) % 4]) for i in range(4)]
    assert all(abs(x - 1000 * np.sqrt(2)) < 1.0 for x in d), d
    sweep = rc.focal_sweep(kept, names, res, target, pp, f, 0.0, 2, 30)
    assert sweep['focal_px'][0] == 6000.0 and sweep['focal_px'][-1] == 16000.0
    z = np.array(sweep['depth_mm'])
    # the rig moves back in proportion, so pixels at the cube hardly change size
    assert np.all(np.abs(z[-1] / z[2] - 2.0) < 0.02), z


def test_preprocessed_tiles_skip_pycamsets_rescale_and_gamma(monkeypatch):
    """Tiles the app binarised (Sauvola, rabbit_sauvola.m) are read as they are; others keep prep_of."""
    import types
    seen = []

    class Det:
        cam_names = list(rc.TILES)

        def get_data(self):
            return None

    def fake(folder, target, **kw):
        seen.append(kw)
        return Det(), []

    mod = types.ModuleType('pyCamSet.calibration.camera_calibrator')
    mod.detect_datapoints_in_imfile = fake
    monkeypatch.setitem(sys.modules, 'pyCamSet.calibration.camera_calibrator', mod)
    monkeypatch.setattr(rc, 'build_target', lambda spec: object())
    cube = {'type': 'Ccube', 'n_points': 6, 'edge_mm': 30.0}
    rc.detect({'tile_dir': 'x', 'target': cube, 'preprocessed': True}, 1)
    rc.detect({'tile_dir': 'x', 'target': cube}, 1)
    assert seen[0]['rescale_and_gamma'] is False and 'preprocessing_gamma' not in seen[0]
    assert seen[1]['rescale_and_gamma'] is True and seen[1]['preprocessing_gamma'] == 0.5
