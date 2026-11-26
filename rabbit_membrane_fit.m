function [V, F, report] = rabbit_membrane_fit(points, cams, opts)

%% Membrane fit of a dense point cloud
% Collin Snitchler (MATLAB port of his Python membrane fit)
% 06.10.2026
% Fits a smooth surface mesh to a dense point cloud, optionally held inside the camera
% silhouettes. Used by rabbit_mesh_cleanup as its default mesh method.
% Inputs:
%   points: N x 3 dense cloud (world units, e.g. native COLMAP units)
%   cams: struct array of silhouette cameras, or [] / empty struct for no silhouette cap.
%       Fields: name, R (3 x 3 world-to-camera rotation), t (3 x 1), f ([fx fy]),
%       c ([cx cy]), width, height, mask (height x width logical silhouette, true = heart),
%       scale (image px per native sensor px, default 1). COLMAP pixel convention.
%       Optional band (height x width logical, empty = none): the mask's field band
%       (rabbit_sfm_build.field_band), pixels beyond a mask edge that is the edge of the
%       mirror's field of view; the silhouette sets no limit there.
%   opts: struct of settings; missing fields take the defaults in default_options below.
% Outputs:
%   V: vertices (M x 3) of the fitted and cut surface
%   F: faces (K x 3, 1-based, outward winding)
%   report: struct with the resolved settings, start shape, iteration log, solver counts,
%       cut record, quality checks, vertex normals (report.normals) and timings
%
% Algorithm: a smooth closed "balloon" surface is fitted to the cloud, then opened where the
% cloud has no support (e.g. the unreconstructed base).
%   1. Start: an icosphere mapped onto the ellipsoid of the cloud's principal axes.
%   2. Each iteration: a per-vertex outer-layer data target (a percentile of the signed normal
%      offsets of the nearby points), a hard cap pulling vertices that project outside a
%      silhouette back inside, an optional rim (outline) target, then one sparse solve of
%      argmin sum w |x - t|^2 + lambda |L (x - X0)|^2 + mu |x - x_prev|^2
%      with the uniform graph Laplacian L, in two stiffness stages (stage 2 re-anchors X0).
%   3. Finish: unsupported regions above an area are cut, the largest piece is kept and the
%      cut rim is smoothed; then the cloud-to-mesh distance and silhouette checks.
%      single_open_edge 1 (an addition, not in the original; default 0): a large unsupported region
%      that is cut off from the open edge only by a narrow strip of support is joined to it,
%      so the strip does not leave a hole. Of the large unsupported regions next to the kept
%      piece, the one with the longest border with it is the open edge (e.g. the
%      unreconstructed base). Another such region whose distance to the open edge, measured
%      along the surface through supported faces, is at most its own size (the radius of a
%      disc of its area; at least twice the support distance) is joined to the open edge: the
%      supported faces on the shortest connections (at most twice the support distance longer)
%      are cut too. A region further away is cut and leaves a hole, which M8 reports;
%      no unsupported surface above cut_area_mm2 is ever kept. Why: a narrow strip of sparse
%      support (on the reference rabbit data, points the silhouette filter keeps in the field
%      band) split the open base into two regions, and cutting both left a hole. Spanning the
%      far regions instead kept up to 11 reference mm2 of surface with no cloud support, so far
%      regions are cut.
%   4. Output density (an addition, not in the original): the cut mesh is split by midpoint
%      subdivision, which leaves the surface unchanged, until it has about as many vertices
%      as the cloud has points, at most 3 levels and at most 200 000 faces
%      (output_subdivisions sets the levels, 0 = off, within the same face cap). The
%      projected activation is stored per vertex, so a coarse fit mesh would show it
%      coarsely; the pure RHYTHM projection samples the faces itself.
%
% Source: a port of the author's unpublished Python membrane fit,
% membrane_fit.py, by Collin Snitchler (ColDSnit). Defaults are the original's, with the
% outline pull off (rim_weight 0), as in its no-pull setting.
% Not ported (options of the original that are off by default or need inputs this pipeline lacks):
% the cotangent bending operator, the smooth rim ramp, the apex taper, the hole stiffness
% boost, the early stage end, the GPU backend and the image-edge offset of the silhouettes
% (the silhouette edge used here is the mask edge, the original's edge_reference 'mask').
%
% Units: the original states its lengths in millimetres of a metric mouse heart. Here the world
% scale is arbitrary, so by default one "reference mm" is the cloud's mean ellipsoid radius
% divided by the mean radius of mouse1 (3.475 mm; mouse1 is the mouse heart dataset used to
% tune the original defaults), i.e. lengths keep the same ratio to the
% heart's size. Set world_units_per_mm for a metric cloud. The icosphere level follows the
% cloud's density (about 6.6 points per vertex, as mouse1 at level 7) and the stiffness is
% rescaled with it (x 16 per level), so the smoothing length relative to the heart is kept.
%
% Section map (search for the quoted line; line numbers move)
%   Settings ........ "%% Settings"
%   Geometry ........ "%% Geometry"
%   Data targets .... "%% Data targets"
%   Silhouettes ..... "%% Silhouettes"
%   The fit ......... "%% The fit"
%   Cut and rim ..... "%% Finish: cut, largest piece, rim smoothing"
%   Checks .......... "%% Checks"
%
% Licence of the ported code (MIT):
% Copyright (c) 2026 Collin Snitchler (ColDSnit)
% Permission is hereby granted, free of charge, to any person obtaining a copy of this
% software and associated documentation files (the "Software"), to deal in the Software
% without restriction, including without limitation the rights to use, copy, modify, merge,
% publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
% to whom the Software is furnished to do so, subject to the following conditions:
% The above copyright notice and this permission notice shall be included in all copies or
% substantial portions of the Software.
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
% INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
% PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
% FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
% OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
% DEALINGS IN THE SOFTWARE.

if nargin < 2 || isempty(cams)
    cams = struct([]);
end
if nargin < 3
    opts = struct();
end
t_total = tic;
points = double(points);
points = points(all(isfinite(points), 2), :);
if size(points, 1) < 100
    error('rabbit_membrane_fit:cloud', 'The cloud has %d finite points; at least 100 are needed.', size(points, 1));
end
cfg = resolve_options(points, opts);
unit = cfg.world_units_per_mm;

% Signed distance fields of the silhouettes (once per camera)
cams = prepare_cameras(cams);

% The fit
t_fit = tic;
fit = fit_membrane(points, cams, cfg);
time_fit = toc(t_fit);

% Cut of unsupported regions, largest piece, rim smoothing
t_cut = tic;
[V, F, cut] = cut_unsupported(fit.vertices, fit.faces, points, cfg);
time_cut = toc(t_cut);

% Output density: midpoint subdivision (no new geometry) up to the cloud's point count, so
% the per-vertex projected values are about as dense as the cloud; each level has 4 x the
% faces, and the face count is kept at or below max_faces
fit_vertices = size(V, 1);
max_faces = 200000;
levels = cfg.output_subdivisions;
if ischar(levels) || isstring(levels)
    levels = min(max(ceil(log(size(points, 1) / size(V, 1)) / log(4)), 0), 3);
end
% A set number of levels keeps to the face cap too
levels = min(levels, max(floor(log(max_faces / max(size(F, 1), 1)) / log(4)), 0));
for level = 1:levels
    [V, F] = subdivide(V, F);
end
densify = struct('levels', levels, 'fit_vertices', fit_vertices, 'output_vertices', size(V, 1), ...
    'rule', 'midpoint subdivision until the vertex count reaches the cloud point count (at most 3 levels, at most 200000 faces)');

% Checks
t_checks = tic;
quality = quality_checks(V, F, points, cams, cfg);
time_checks = toc(t_checks);

report = struct();
report.method = 'membrane fit (MATLAB port of membrane_fit.py, MIT, Collin Snitchler)';
report.settings = cfg;
report.points = size(points, 1);
report.start_shape = struct('kind', 'icosphere on the cloud''s principal-axis ellipsoid', ...
    'vertices', size(fit.vertices, 1), 'faces', size(fit.faces, 1), ...
    'median_edge', fit.start_edge, 'radii', fit.start.radii, 'centre', fit.start.centre);
report.iterations = fit.log;
report.solver = fit.solver;
report.silhouette = struct('cameras', numel(cams), 'cap_used', ~isempty(cams), ...
    'edge_reference', 'mask');
report.cut = cut;
report.output_density = densify;
report.quality = quality;
report.normals = vertex_normals(V, F);
report.timings_s = struct('fit', time_fit, 'cut', time_cut, 'checks', time_checks, ...
    'total', toc(t_total));
end


%% Settings

function cfg = default_options()
% The original's defaults (membrane_fit.py SPECS), outline pull off.
cfg = struct();
cfg.template_subdivisions = 'auto';     % original: 7 (here: by cloud density, at most 7)
cfg.stage1_lambda = 3.0e4;              % stiffness at icosphere level 7
cfg.stage1_iterations = 60;
cfg.stage2_lambda = 1.0e4;              % stiffness at icosphere level 7
cfg.stage2_iterations = 30;
cfg.lambda_reference_level = 7;         % level the lambdas above are stated for
cfg.linear_solver = 'pcg';              % 'pcg' (reused Cholesky preconditioner) or 'direct'
cfg.pcg_tolerance_um = 0.001;
cfg.pcg_max_iterations = 20;
cfg.proximal_weight = 0.05;
cfg.data_quantile = 75.0;
cfg.max_assign_mm = 1.0;
cfg.min_points = 4;
cfg.step_cap_mm = 0.2;
cfg.silhouette_tolerance_px = 1.0;
cfg.mask_trust_px = 20.0;
cfg.outside_weight = 20.0;
cfg.rim_cos = 0.25;
cfg.rim_band_px = 10.0;
cfg.rim_cap_mm = 0.5;
cfg.rim_weight = 0.0;                   % original SPECS: 1.0; no-pull setting: 0
cfg.support_mm = 0.3;
cfg.cut_area_mm2 = 2.0;
cfg.rim_smooth_passes = 30;
cfg.rim_smooth_blend = 0.5;
cfg.world_units_per_mm = 'auto';        % 'auto': mean ellipsoid radius / 3.475
cfg.output_subdivisions = 'auto';       % not in the original: see the output density step
cfg.single_open_edge = 0;               % not in the original: 1 = a region near the open edge joins it (step 3)
end


function cfg = resolve_options(points, opts)
% Defaults, the user's settings over them, and the automatic scale and level.
ref_mean_radius_mm = 3.475;             % mouse1 start ellipsoid, mean of 3.19, 3.35, 3.89 mm
ref_points_per_vertex = 1082526 / 163842;   % mouse1 cloud points per level-7 vertex
cfg = default_options();
names = fieldnames(opts);
for k = 1:numel(names)
    if ~isfield(cfg, names{k})
        error('rabbit_membrane_fit:option', 'Unknown membrane-fit setting ''%s''.', names{k});
    end
    cfg.(names{k}) = opts.(names{k});
end
if islogical(cfg.single_open_edge) && isscalar(cfg.single_open_edge)
    cfg.single_open_edge = double(cfg.single_open_edge);
end
check_ranges(cfg);
radii = start_radii(points);
cfg.mean_radius = mean(radii);
if ischar(cfg.world_units_per_mm) || isstring(cfg.world_units_per_mm)
    cfg.world_units_per_mm = cfg.mean_radius / ref_mean_radius_mm;
    cfg.unit_source = 'auto: mean ellipsoid radius / 3.475 (mouse1)';
else
    cfg.unit_source = 'given';
end
if ischar(cfg.template_subdivisions) || isstring(cfg.template_subdivisions)
    levels = 2:7;
    n_vertices = 10 * 4 .^ levels + 2;
    [~, best] = min(abs(log(n_vertices * ref_points_per_vertex / size(points, 1))));
    cfg.template_subdivisions = levels(best);
    cfg.level_source = 'auto: about 6.6 cloud points per vertex (mouse1 at level 7)';
else
    cfg.level_source = 'given';
end
% Bending energy per graph step scales with the edge length^4: x 16 per level
level_factor = 16 ^ (cfg.template_subdivisions - cfg.lambda_reference_level);
cfg.stage1_lambda_effective = cfg.stage1_lambda * level_factor;
cfg.stage2_lambda_effective = cfg.stage2_lambda * level_factor;
if cfg.mask_trust_px <= cfg.silhouette_tolerance_px
    error('rabbit_membrane_fit:option', 'mask_trust_px must exceed silhouette_tolerance_px.');
end
if ~any(strcmp(cfg.linear_solver, {'pcg', 'direct'}))
    error('rabbit_membrane_fit:option', 'linear_solver must be ''pcg'' or ''direct''.');
end
end


function check_ranges(cfg)
% Range checks of the numeric settings, as the original's validate_membrane_settings: name,
% integer, lowest, lowest excluded, highest ('auto' settings are skipped)
ranges = {
    'template_subdivisions',  true,  2,   false, 8
    'stage1_lambda',          false, 0,   true,  1e10
    'stage1_iterations',      true,  1,   false, 1000
    'stage2_lambda',          false, 0,   true,  1e10
    'stage2_iterations',      true,  0,   false, 1000
    'lambda_reference_level', true,  2,   false, 8
    'pcg_tolerance_um',       false, 0,   true,  1000
    'pcg_max_iterations',     true,  1,   false, 1000
    'proximal_weight',        false, 0,   true,  1e6
    'data_quantile',          false, 0,   false, 100
    'max_assign_mm',          false, 0,   true,  1000
    'min_points',             true,  1,   false, 100000
    'step_cap_mm',            false, 0,   true,  1000
    'silhouette_tolerance_px', false, 0,  false, 1000
    'mask_trust_px',          false, 0,   true,  100000
    'outside_weight',         false, 0,   true,  1e6
    'rim_cos',                false, 0,   false, 1
    'rim_band_px',            false, 0,   true,  10000
    'rim_cap_mm',             false, 0,   true,  1000
    'rim_weight',             false, 0,   false, 1e6
    'support_mm',             false, 0,   true,  1000
    'cut_area_mm2',           false, 0,   false, 1e9
    'rim_smooth_passes',      true,  0,   false, 100000
    'rim_smooth_blend',       false, 0,   false, 1
    'world_units_per_mm',     false, 0,   true,  1e9
    'output_subdivisions',    true,  0,   false, 3
    'single_open_edge',       true,  0,   false, 1
    };
for k = 1:size(ranges, 1)
    [name, is_int, low, low_open, high] = ranges{k, :};
    value = cfg.(name);
    if (ischar(value) || isstring(value)) && strcmp(value, 'auto')
        continue;
    end
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || (is_int && value ~= round(value))
        error('rabbit_membrane_fit:option', 'The membrane-fit setting %s must be a finite number.', name);
    end
    if value < low || (low_open && value == low) || value > high
        if low_open
            low_text = sprintf('above %g', low);
        else
            low_text = sprintf('at least %g', low);
        end
        error('rabbit_membrane_fit:option', 'The membrane-fit setting %s must be %s and at most %g; got %g.', ...
            name, low_text, high, value);
    end
end
end


%% Geometry

function [vertices, faces] = icosphere(levels)
% Unit icosphere with outward (counter-clockwise) faces; same vertex order as the original
t = (1 + sqrt(5)) / 2;
vertices = [-1 t 0; 1 t 0; -1 -t 0; 1 -t 0; 0 -1 t; 0 1 t; 0 -1 -t; 0 1 -t; ...
    t 0 -1; t 0 1; -t 0 -1; -t 0 1];
faces = [0 11 5; 0 5 1; 0 1 7; 0 7 10; 0 10 11; 1 5 9; 5 11 4; 11 10 2; 10 7 6; 7 1 8; ...
    3 9 4; 3 4 2; 3 2 6; 3 6 8; 3 8 9; 4 9 5; 2 4 11; 6 2 10; 8 6 7; 9 8 1] + 1;
for level = 1:levels
    edges = sort([faces(:, [1 2]); faces(:, [2 3]); faces(:, [3 1])], 2);
    [unique_edges, ~, inverse] = unique(edges, 'rows');   % one new vertex per edge
    mid = size(vertices, 1) + reshape(inverse, [], 3);   % columns: ab, bc, ca midpoints
    vertices = [vertices; 0.5 * (vertices(unique_edges(:, 1), :) + vertices(unique_edges(:, 2), :))]; %#ok<AGROW>
    a = faces(:, 1); b = faces(:, 2); c = faces(:, 3);
    ab = mid(:, 1); bc = mid(:, 2); ca = mid(:, 3);
    faces = [a ab ca; b bc ab; c ca bc; ab bc ca];
end
vertices = vertices ./ sqrt(sum(vertices .^ 2, 2));
end


function [vertices, faces] = subdivide(vertices, faces)
% One level of midpoint subdivision: each triangle becomes four, the surface is unchanged
edges = sort([faces(:, [1 2]); faces(:, [2 3]); faces(:, [3 1])], 2);
[unique_edges, ~, inverse] = unique(edges, 'rows');
mid = size(vertices, 1) + reshape(inverse, [], 3);
vertices = [vertices; 0.5 * (vertices(unique_edges(:, 1), :) + vertices(unique_edges(:, 2), :))];
a = faces(:, 1); b = faces(:, 2); c = faces(:, 3);
ab = mid(:, 1); bc = mid(:, 2); ca = mid(:, 3);
faces = [a ab ca; b bc ab; c ca bc; ab bc ca];
end


function radii = start_radii(points)
% Radii of the principal-axis ellipsoid, sqrt(3 x variance) per axis
variances = sort(eig(cov(points)));
radii = sqrt(3 * max(variances, 0))';
end


function [vertices, faces, info] = ellipsoid_start(points, levels)
% Icosphere mapped onto the ellipsoid of the cloud's principal axes. Points spread evenly
% over an ellipsoid's surface have variance r^2 / 3 along each axis, so sqrt(3 var) gives r.
[directions, faces] = icosphere(levels);
centre = mean(points, 1);
[axes_, values] = eig(cov(points - centre));
[variances, order] = sort(diag(values));
axes_ = axes_(:, order);
if det(axes_) < 0
    axes_(:, 1) = -axes_(:, 1);         % a reflection would turn the faces inward
end
radii = sqrt(3 * max(variances, 0))';
vertices = centre + (directions .* radii) * axes_';
info = struct('centre', centre, 'radii', radii, 'axes', axes_);
end


function A = edge_adjacency(faces, n)
% Symmetric 0/1 vertex adjacency of the mesh edges
edges = unique(sort([faces(:, [1 2]); faces(:, [2 3]); faces(:, [3 1])], 2), 'rows');
A = sparse([edges(:, 1); edges(:, 2)], [edges(:, 2); edges(:, 1)], 1, n, n);
end


function normals = vertex_normals(vertices, faces)
% Unit area-weighted vertex normals, turned outward (away from the centroid on average)
v0 = vertices(faces(:, 1), :);
face_n = cross(vertices(faces(:, 2), :) - v0, vertices(faces(:, 3), :) - v0, 2);
n = size(vertices, 1);
normals = zeros(n, 3);
for k = 1:3
    for j = 1:3
        normals(:, j) = normals(:, j) + accumarray(faces(:, k), face_n(:, j), [n 1]);
    end
end
len = sqrt(sum(normals .^ 2, 2));
len(len == 0) = 1;
normals = normals ./ len;
if mean(sum(normals .* (vertices - mean(vertices, 1)), 2)) < 0
    normals = -normals;                 % inward-wound mesh: flip
end
end


function areas = face_areas(vertices, faces)
v0 = vertices(faces(:, 1), :);
cr = cross(vertices(faces(:, 2), :) - v0, vertices(faces(:, 3), :) - v0, 2);
areas = 0.5 * sqrt(sum(cr .^ 2, 2));
end


function G = face_adjacency(faces)
% Face graph: faces sharing an edge are connected
m = size(faces, 1);
edges = sort([faces(:, [1 2]); faces(:, [2 3]); faces(:, [3 1])], 2);
owner = repmat((1:m)', 3, 1);
[~, ~, edge_id] = unique(edges, 'rows');
[edge_id, order] = sort(edge_id);
owner = owner(order);
same = edge_id(2:end) == edge_id(1:end-1);
rows = owner([same; false]);
cols = owner([false; same]);
G = graph(sparse(rows, cols, 1, m, m) + sparse(cols, rows, 1, m, m));
end


%% Data targets

function [target, weight] = data_targets(X, N, points, ring, cfg, unit)
% Each point goes to its nearest vertex within max_assign; its signed offset along that
% vertex's normal counts for the vertex's whole 1-ring. A vertex with at least min_points
% such offsets targets their data_quantile percentile.
max_assign = cfg.max_assign_mm * unit;
[nearest, dist] = knnsearch(X, points);
found = dist < max_assign;
nearest = nearest(found);
offset = sum((points(found, :) - X(nearest, :)) .* N(nearest, :), 2);
keep = abs(offset) < max_assign;
nearest = nearest(keep);
offset = offset(keep);
[group, point_id] = find(ring(:, nearest));     % ring is symmetric: column = 1-ring
[target, ok] = grouped_quantile(group, offset(point_id), size(X, 1), cfg.data_quantile / 100, cfg.min_points);
weight = double(ok);
end


function [out, ok] = grouped_quantile(groups, values, n_groups, q, min_count)
% Per group: the q-quantile (linear interpolation, as numpy's default) and count >= min_count
[~, order] = sortrows([groups values]);
v = values(order);
counts = accumarray(groups, 1, [n_groups 1]);
starts = cumsum(counts) - counts;
ok = counts >= max(min_count, 1);
out = zeros(n_groups, 1);
idx = find(ok);
pos = (counts(idx) - 1) * q;
lo = floor(pos);
hi = min(lo + 1, counts(idx) - 1);
frac = pos - lo;
out(idx) = v(starts(idx) + lo + 1) .* (1 - frac) + v(starts(idx) + hi + 1) .* frac;
end


%% Silhouettes

function cams = prepare_cameras(cams)
% Signed distance field per silhouette: > 0 inside, 0 half-way between pixel centres;
% NaN in the field band (no cap, no rim target and no quality count there: a NaN sample
% is treated like a point outside the image)
for k = 1:numel(cams)
    if ~isfield(cams(k), 'scale') || isempty(cams(k).scale)
        cams(k).scale = 1;
    end
    mask = logical(cams(k).mask);
    inside = bwdist(~mask);
    outside = bwdist(mask);
    sdf = -(outside - 0.5);
    sdf(mask) = inside(mask) - 0.5;
    if isfield(cams(k), 'band') && ~isempty(cams(k).band)
        sdf(logical(cams(k).band)) = NaN;
    end
    cams(k).sdf = sdf;
    cams(k).centre = (-cams(k).R' * cams(k).t(:))';
end
end


function [uv, z] = project(cam, X)
% COLMAP pinhole projection: pixel (0, 0) has its centre at (0.5, 0.5)
Xc = X * cam.R' + cam.t(:)';
z = Xc(:, 3);
safe = z;
safe(abs(safe) < 1e-300) = 1e-300;
uv = [cam.f(1) * Xc(:, 1) ./ safe + cam.c(1), cam.f(2) * Xc(:, 2) ./ safe + cam.c(2)];
end


function value = sample_field(field, uv)
% Bilinear sample at COLMAP pixel coordinates; NaN outside the image
x = uv(:, 1) - 0.5;
y = uv(:, 2) - 0.5;
[h, w] = size(field);
inside = x >= 0 & x <= w - 1 & y >= 0 & y <= h - 1;
x0 = min(max(floor(x), 0), max(w - 2, 0));
y0 = min(max(floor(y), 0), max(h - 2, 0));
fx = min(max(x - x0, 0), 1);
fy = min(max(y - y0, 0), 1);
x1 = min(x0 + 1, w - 1);
y1 = min(y0 + 1, h - 1);
x0(~isfinite(x0)) = 0; y0(~isfinite(y0)) = 0; x1(~isfinite(x1)) = 0; y1(~isfinite(y1)) = 0;
fx(~isfinite(fx)) = 0; fy(~isfinite(fy)) = 0;
at = @(r, c) field(sub2ind([h w], r + 1, c + 1));
top = at(y0, x0) .* (1 - fx) + at(y0, x1) .* fx;
bottom = at(y1, x0) .* (1 - fx) + at(y1, x1) .* fx;
value = top .* (1 - fy) + bottom .* fy;
value(~inside) = NaN;
end


function ok = in_image(cam, uv, z)
ok = all(isfinite(uv), 2) & z > 0 & uv(:, 1) >= 0 & uv(:, 1) < cam.width & ...
    uv(:, 2) >= 0 & uv(:, 2) < cam.height;
end


function [cap, rim_sum, rim_count] = silhouette_terms(X, N, cams, cfg, unit)
% Per vertex: the hard cap on the normal offset (Inf = none) and the summed rim targets.
% A vertex projecting outside a camera's edge by tolerance..mask_trust may move at most
% (sdf + tolerance) pixels' worth along its normal, i.e. back inside. A pixel's world size is
% z / f at the vertex; image motion per unit normal motion is the normal's component across
% the view ray (at least 0.3).
gain_floor = 0.3;
n = size(X, 1);
cap = inf(n, 1);
rim_sum = zeros(n, 1);
rim_count = zeros(n, 1);
rim_cap = cfg.rim_cap_mm * unit;
for k = 1:numel(cams)
    cam = cams(k);
    tol = cfg.silhouette_tolerance_px * cam.scale;
    trust = cfg.mask_trust_px * cam.scale;
    band = cfg.rim_band_px * cam.scale;
    [uv, z] = project(cam, X);
    ok = in_image(cam, uv, z);
    sdf = nan(n, 1);
    sdf(ok) = sample_field(cam.sdf, uv(ok, :));
    ok = ok & isfinite(sdf);
    pixel = abs(z) / mean(cam.f);
    view_dir = X - cam.centre;
    view_dir = view_dir ./ sqrt(sum(view_dir .^ 2, 2));
    cos_view = sum(N .* view_dir, 2);
    gain = max(sqrt(min(max(1 - cos_view .^ 2, 0), 1)), gain_floor);
    outside = ok & sdf < -tol & sdf > -trust;   % deeper: the masks disagree there
    cap(outside) = min(cap(outside), (sdf(outside) + tol) .* pixel(outside) ./ gain(outside));
    if cfg.rim_weight > 0 && cfg.rim_cos > 0
        rim = ok & abs(cos_view) < cfg.rim_cos & ~outside & abs(sdf) < band & sdf > -trust;
        rim_sum(rim) = rim_sum(rim) + min(max(sdf(rim) .* pixel(rim) ./ gain(rim), -rim_cap), rim_cap);
        rim_count(rim) = rim_count(rim) + 1;
    end
end
end


%% The fit

function fit = fit_membrane(points, cams, cfg)
unit = cfg.world_units_per_mm;
[X, F, info] = ellipsoid_start(points, cfg.template_subdivisions);
n = size(X, 1);
edge = sqrt(sum((X(F(:, 1), :) - X(F(:, 2), :)) .^ 2, 2));
A = edge_adjacency(F, n);
L = spdiags(full(sum(A, 2)), 0, n, n) - A;   % uniform graph Laplacian
K = L' * L;                                  % bending energy |L d|^2 = d' K d
ring = A + speye(n);                         % 1-ring including the vertex itself
X0 = X;
step_cap = cfg.step_cap_mm * unit;
mu = cfg.proximal_weight;
plan = [ones(cfg.stage1_iterations, 1); 2 * ones(cfg.stage2_iterations, 1)];
lambdas = [cfg.stage1_lambda_effective, cfg.stage2_lambda_effective];
solver = struct('mode', cfg.linear_solver, 'tolerance', cfg.pcg_tolerance_um * unit / 1000, ...
    'max_iterations', cfg.pcg_max_iterations, 'factor', [], 'perm', [], ...
    'factorisations', 0, 'pcg_solves', 0, 'pcg_iterations', 0, 'pcg_fallbacks', 0);
log_ = struct('iteration', {}, 'stage', {}, 'lambda', {}, 'data_vertices', {}, ...
    'rim_vertices', {}, 'outside_vertices', {}, 'step_median', {}, 'step_max', {}, ...
    'normal_step_median', {}, 'solve', {}, 'pcg_iterations', {}, 'seconds', {});
for it = 1:numel(plan)
    tick = tic;
    stage = plan(it);
    lam = lambdas(stage);
    stage_start = it == 1 || plan(it - 1) ~= stage;
    if stage_start
        if stage == 2
            X0 = X;                      % re-anchor: stage 2 bends away from stage 1's shape
        end
        lam_K = lam * K;
        K_X0 = K * X0;
        solver.factor = [];              % a new stage: no factor to reuse
    end
    N = vertex_normals(X, F);
    [offset, w] = data_targets(X, N, points, ring, cfg, unit);
    [cap, rim_sum, rim_count] = silhouette_terms(X, N, cams, cfg, unit);
    total_w = w + cfg.rim_weight * rim_count;
    target = zeros(n, 1);
    has = total_w > 0;
    target(has) = (w(has) .* offset(has) + cfg.rim_weight * rim_sum(has)) ./ max(total_w(has), 1e-12);
    target = min(max(target, -step_cap), step_cap);     % bounded step per iteration
    violated = isfinite(cap) & target > cap;
    target(violated) = max(cap(violated), -step_cap);   % back inside, at most step_cap
    total_w(violated) = max(total_w(violated), cfg.outside_weight);
    T = X + target .* N;
    system = spdiags(total_w + mu, 0, n, n) + lam_K;    % symmetric positive definite
    rhs = total_w .* T + mu * X + lam * K_X0;           % bend the displacement x - X0
    [X_new, solver, solved, pcg_its] = solve_system(solver, system, rhs, X);
    delta = X_new - X;
    step = sqrt(sum(delta .^ 2, 2));
    normal_step = abs(sum(delta .* N, 2));
    X = X_new;
    log_(end + 1) = struct('iteration', it, 'stage', stage, 'lambda', lam, ...
        'data_vertices', sum(w > 0), 'rim_vertices', sum(rim_count > 0), ...
        'outside_vertices', sum(isfinite(cap)), 'step_median', median(step), ...
        'step_max', max(step), 'normal_step_median', median(normal_step), ...
        'solve', solved, 'pcg_iterations', pcg_its, 'seconds', toc(tick)); %#ok<AGROW>
end
fit = struct('vertices', X, 'faces', F, 'start', info, 'start_edge', median(edge), 'log', log_, ...
    'solver', rmfield(solver, {'factor', 'perm'}));
end


function [x, solver, method, iterations] = solve_system(solver, system, rhs, x0)
% direct: a fresh sparse Cholesky solve. pcg: conjugate gradients from the current shape,
% preconditioned by the Cholesky factor of an earlier system of the same stage (consecutive
% systems differ only in the data weights); a new factor at each stage start and whenever a
% solve has not converged (that solve is then done directly), as the original's linear_solver pcg.
iterations = 0;
if strcmp(solver.mode, 'pcg') && ~isempty(solver.factor)
    precondition = @(r) apply_factor(solver.factor, solver.perm, r);
    [x, iterations, converged] = pcg_solve(system, rhs, x0, precondition, ...
        solver.tolerance, solver.max_iterations, 1.0e-7);
    solver.pcg_solves = solver.pcg_solves + 1;
    solver.pcg_iterations = solver.pcg_iterations + iterations;
    if converged
        method = 'pcg';
        return;
    end
    solver.pcg_fallbacks = solver.pcg_fallbacks + 1;
    solver.factor = [];
end
method = 'factor';
[R, flag, perm] = chol(system, 'lower', 'vector');
solver.factorisations = solver.factorisations + 1;
if flag ~= 0
    x = system \ rhs;                   % not positive definite in floating point: general solve
    return;
end
x = apply_factor(R, perm, rhs);
if strcmp(solver.mode, 'pcg')
    solver.factor = R;
    solver.perm = perm;
end
end


function x = apply_factor(R, perm, rhs)
% system(perm, perm) = R * R'
x = zeros(size(rhs));
x(perm, :) = R' \ (R \ rhs(perm, :));
end


function [x, k, converged] = pcg_solve(system, rhs, x0, precondition, tolerance, max_iterations, relative_residual)
% Preconditioned conjugate gradients, every column independently. Converged when the largest
% coordinate update of an iteration is below tolerance and every column's residual is at
% most relative_residual x its right-hand side.
x = x0;
limit = relative_residual * sqrt(sum(rhs .^ 2, 1));
r = rhs - system * x;
z = precondition(r);
p = z;
rz = sum(r .* z, 1);
for k = 1:max_iterations
    ap = system * p;
    pap = sum(p .* ap, 1);
    alpha = zeros(size(rz));
    alpha(pap > 0) = rz(pap > 0) ./ pap(pap > 0);
    step = p .* alpha;
    x = x + step;
    r = r - ap .* alpha;
    if max(abs(step(:))) < tolerance && all(sqrt(sum(r .^ 2, 1)) <= limit)
        converged = true;
        return;
    end
    z = precondition(r);
    rz_new = sum(r .* z, 1);
    beta = zeros(size(rz));
    beta(rz > 0) = rz_new(rz > 0) ./ rz(rz > 0);
    p = z + p .* beta;
    rz = rz_new;
end
k = max_iterations;
converged = false;
end


%% Finish: cut, largest piece, rim smoothing

function [V, Fc, record] = cut_unsupported(X, F, points, cfg)
% A face is unsupported when no point lies within support_mm of its centroid. Connected
% unsupported regions above cut_area_mm2 are removed; smaller ones stay spanned. Then the
% largest edge-connected piece is kept and the cut rim is smoothed along its loop.
% single_open_edge: a region near the open edge is joined to it (one_open_edge).
unit = cfg.world_units_per_mm;
mm2 = unit * unit;
centroids = (X(F(:, 1), :) + X(F(:, 2), :) + X(F(:, 3), :)) / 3;
[~, dist] = knnsearch(points, centroids);
unsupported = find(dist > cfg.support_mm * unit);
areas = face_areas(X, F);
remove = false(size(F, 1), 1);
region_areas = zeros(0, 1);
region_of = zeros(size(F, 1), 1);       % large-region label per face (0 = none)
if ~isempty(unsupported)
    G = face_adjacency(F);
    labels = conncomp(subgraph(G, unsupported))';
    region_areas = accumarray(labels, areas(unsupported)) / mm2;
    big = find(region_areas > cfg.cut_area_mm2);
    remove(unsupported(ismember(labels, big))) = true;
    region_of(unsupported) = labels .* ismember(labels, big);
end
edge_record = open_edge_record();
if cfg.single_open_edge && nnz(region_areas > cfg.cut_area_mm2) > 1
    [remove, edge_record] = one_open_edge(X, F, remove, region_of, region_areas, ...
        cfg.support_mm * unit, mm2);
end
kept = find(~remove);
if isempty(kept)
    % Nothing of the fitted surface lies near the cloud (e.g. silhouette masks that
    % disagree with the cameras squeezed the surface away from the points)
    error('rabbit_membrane_fit:NoSupportedSurface', ...
        ['No part of the fitted surface lies within the support distance of the cloud, ' ...
        'so nothing is left after the cut. If silhouette masks were used, check that they ' ...
        'match the cameras, or fit without them.']);
end
F1 = F(kept, :);
labels = conncomp(face_adjacency(F1))';
piece_area = accumarray(labels, areas(kept));
[~, largest] = max(piece_area);
F2 = F1(labels == largest, :);
removed_disconnected = (sum(piece_area) - piece_area(largest)) / mm2;
used = unique(F2(:));
remap = zeros(size(X, 1), 1);
remap(used) = 1:numel(used);
V = X(used, :);
Fc = remap(F2);
if size(Fc, 2) ~= 3
    Fc = reshape(Fc, [], 3);
end
edges = sort([Fc(:, [1 2]); Fc(:, [2 3]); Fc(:, [3 1])], 2);
[unique_edges, ~, edge_id] = unique(edges, 'rows');
boundary = unique_edges(accumarray(edge_id, 1) == 1, :);   % edges with one face: the cut rim
if ~isempty(boundary) && cfg.rim_smooth_passes > 0
    nv = size(V, 1);
    nb = sparse([boundary(:, 1); boundary(:, 2)], [boundary(:, 2); boundary(:, 1)], 1, nv, nv);
    rim_vertices = unique(boundary(:));
    degree = full(sum(nb, 2));
    blend = cfg.rim_smooth_blend;
    for pass = 1:cfg.rim_smooth_passes
        mean_nb = (nb * V);
        mean_nb = mean_nb(rim_vertices, :) ./ max(degree(rim_vertices), 1);
        V(rim_vertices, :) = (1 - blend) * V(rim_vertices, :) + blend * mean_nb;
    end
end
record = struct('unsupported_regions', numel(region_areas), ...
    'removed_unsupported_mm2', sum(region_areas(region_areas > cfg.cut_area_mm2)), ...
    'spanned_unsupported_mm2', sum(region_areas(region_areas <= cfg.cut_area_mm2)), ...
    'removed_regions', sum(region_areas > cfg.cut_area_mm2), ...
    'removed_disconnected_mm2', removed_disconnected, ...
    'boundary_edges', size(boundary, 1), ...
    'area_unit', 'reference mm^2 (world_units_per_mm squared)');
if cfg.single_open_edge
    % Every large region is still cut (removed_unsupported_mm2 / removed_regions count the
    % open edge, the regions joined to it and the far ones left as holes); the supported
    % strips cut with the joined regions are counted apart
    record.removed_supported_strip_mm2 = edge_record.strip_mm2;
    record.single_open_edge = edge_record;
end
end


function rec = open_edge_record()
% The cut record of one_open_edge: regions joined to the open edge (their area and the
% supported strip cut with them) and regions cut as holes; per region its area, the gap
% along the surface, the limit and the result
rec = struct('joined_regions', 0, 'joined_mm2', 0, 'strip_mm2', 0, 'hole_regions', 0, ...
    'hole_mm2', 0, 'hole_areas_mm2', zeros(0, 1), 'gap_measure', ...
    'shortest path along the surface through supported faces (face centre to face centre)', ...
    'regions', struct('area_mm2', {}, 'gap_mm', {}, 'limit_mm', {}, 'result', {}));
end


function d = surface_distance(fa, fb, len_c, allowed, sources, m)
% Shortest path length over the face graph (face centre to face centre, faces sharing an
% edge) from any of the source faces, through allowed faces only; Inf where not reached
use = allowed(fa) & allowed(fb);
s = [fa(use); repmat(m + 1, numel(sources), 1)];        % node m + 1 joins every source at 0
t = [fb(use); sources(:)];
w = [len_c(use); zeros(numel(sources), 1)];
d = distances(graph(s, t, w, m + 1), m + 1);
d = d(1:m)';
end


function [remove, rec] = one_open_edge(X, F, remove, region_of, region_areas, support, mm2)
% A large unsupported region cut off from the open edge only by a narrow strip of support is
% joined to it. The removed regions next to the kept (largest) piece are ranked by the length
% of their border with it; the longest is the open edge. For each other one, gap = the
% shortest path along the surface from the open edge to the region through supported faces
% (face centre to face centre; surface_distance). When gap is at most the region's own size
% (the radius of a disc of its area) or twice the support distance, the region is joined to
% the open edge: the supported faces on paths at most twice the support distance longer than
% gap are cut with it (they must connect the two). Otherwise the region stays cut, as without
% this setting, and leaves a hole (M8 reports it); nothing is spanned. Repeated while a pass
% joins a region, since the grown open edge can come near another region.
rec = open_edge_record();
unit = sqrt(mm2);
m = size(F, 1);
areas = face_areas(X, F);
centroids = (X(F(:, 1), :) + X(F(:, 2), :) + X(F(:, 3), :)) / 3;
E = sort([F(:, [1 2]); F(:, [2 3]); F(:, [3 1])], 2);
owner = repmat((1:m)', 3, 1);
[~, ~, edge_id] = unique(E, 'rows');
[edge_id, order] = sort(edge_id);
owner = owner(order);
Es = E(order, :);
same = edge_id(2:end) == edge_id(1:end-1);
fa = owner([same; false]);              % the two faces of each edge (the fitted surface is closed)
fb = owner([false; same]);
Ea = Es([same; false], :);
len = sqrt(sum((X(Ea(:, 1), :) - X(Ea(:, 2), :)) .^ 2, 2));        % edge length (border length)
len_c = sqrt(sum((centroids(fa, :) - centroids(fb, :)) .^ 2, 2));   % face centre to face centre
G = face_adjacency(F);
outcome = struct('area_mm2', {}, 'gap_mm', {}, 'limit_mm', {}, 'result', {});
last = zeros(0, 1);                     % region label of each outcome entry
while true
    kept = find(~remove);
    piece = conncomp(subgraph(G, kept))';
    [~, largest] = max(accumarray(piece, areas(kept)));
    in_piece = false(m, 1);
    in_piece(kept(piece == largest)) = true;
    across = (in_piece(fa) & remove(fb)) | (in_piece(fb) & remove(fa));   % piece-to-removed edges
    other = fb;
    other(remove(fa)) = fa(remove(fa));
    sel = find(across);
    labels = region_of(other(sel));
    ok = labels > 0;
    if ~any(ok), break; end
    border = accumarray(labels(ok), len(sel(ok)));
    next_to = find(border > 0);
    if numel(next_to) <= 1, break; end
    [~, rim] = max(border);
    rim_faces = find(region_of == rim);
    d_rim = surface_distance(fa, fb, len_c, ~remove | region_of == rim, rim_faces, m);
    joined_any = false;
    for h = setdiff(next_to(:)', rim)
        h_faces = find(region_of == h);
        d_h = surface_distance(fa, fb, len_c, ~remove | region_of == h, h_faces, m);
        through = d_rim + d_h;          % length of the shortest path through each supported face
        gap = min(through(~remove));
        limit = max(2 * support, sqrt(region_areas(h) * mm2 / pi));
        joined = false;
        strip = zeros(0, 1);
        if gap <= limit
            strip = find(~remove & through <= gap + 2 * support);
            part = [rim_faces; h_faces; strip];
            comp = conncomp(subgraph(G, part))';
            joined = comp(1) == comp(numel(rim_faces) + 1);   % a rim face and an h face connect
        end
        if joined
            remove(strip) = true;
            region_of([h_faces; strip]) = rim;
            rec.joined_regions = rec.joined_regions + 1;
            rec.joined_mm2 = rec.joined_mm2 + region_areas(h);
            rec.strip_mm2 = rec.strip_mm2 + sum(areas(strip)) / mm2;
            result = 'joined to the open edge';
            joined_any = true;
        else
            result = 'cut: a hole (not near the open edge)';
        end
        entry = struct('area_mm2', region_areas(h), 'gap_mm', gap / unit, 'limit_mm', limit / unit, ...
            'result', result);
        at = find(last == h, 1);        % a region tried again after a join: its latest outcome
        if isempty(at)
            outcome(end + 1) = entry; %#ok<AGROW>
            last(end + 1, 1) = h; %#ok<AGROW>
        else
            outcome(at) = entry;
        end
        if joined
            break;                      % the open edge has grown: measure again from it
        end
    end
    if ~joined_any, break; end
end
rec.regions = outcome;
holes = ~strcmp({outcome.result}, 'joined to the open edge');
rec.hole_regions = nnz(holes);
rec.hole_areas_mm2 = reshape([outcome(holes).area_mm2], [], 1);
rec.hole_mm2 = sum(rec.hole_areas_mm2);
end



%% Checks

function dist = point_triangle_distance(p, a, b, c)
% Exact distances from points p to triangles (a, b, c), by closest-point region tests
% (Ericson 2005, Real-Time Collision Detection, section 5.1.5)
ab = b - a; ac = c - a; ap = p - a;
d1 = sum(ab .* ap, 2); d2 = sum(ac .* ap, 2);
bp = p - b;
d3 = sum(ab .* bp, 2); d4 = sum(ac .* bp, 2);
cp = p - c;
d5 = sum(ab .* cp, 2); d6 = sum(ac .* cp, 2);
va = d3 .* d6 - d5 .* d4; vb = d5 .* d2 - d1 .* d6; vc = d1 .* d4 - d3 .* d2;
denom = va + vb + vc;
q = a + ab .* (vb ./ denom) + ac .* (vc ./ denom);   % interior of the face
w_bc = (d4 - d3) ./ ((d4 - d3) + (d5 - d6));
s = va <= 0 & d4 - d3 >= 0 & d5 - d6 >= 0;
q(s, :) = b(s, :) + (c(s, :) - b(s, :)) .* w_bc(s);
s = vb <= 0 & d2 >= 0 & d6 <= 0;
q(s, :) = a(s, :) + ac(s, :) .* (d2(s) ./ (d2(s) - d6(s)));
s = d6 >= 0 & d5 <= d6;
q(s, :) = c(s, :);
s = vc <= 0 & d1 >= 0 & d3 <= 0;
q(s, :) = a(s, :) + ab(s, :) .* (d1(s) ./ (d1(s) - d3(s)));
s = d3 >= 0 & d4 <= d3;
q(s, :) = b(s, :);
s = d1 <= 0 & d2 <= 0;
q(s, :) = a(s, :);                       % vertex a wins last
dist = sqrt(sum((p - q) .^ 2, 2));
dist(~isfinite(dist)) = inf;
end


function out = point_mesh_distance(points, V, F)
% Distance from each point to the mesh: exact over the faces around its 4 nearest vertices
k = min(4, size(V, 1));
nv = size(V, 1);
[sorted_v, order] = sort(F(:));
owner = mod(order - 1, size(F, 1)) + 1;           % face of each (vertex, face) incidence
counts = accumarray(sorted_v, 1, [nv 1]);
starts = cumsum(counts) - counts;
slot = (1:numel(sorted_v))' - starts(sorted_v);
incident = zeros(nv, max(counts));
incident(sub2ind(size(incident), sorted_v, slot)) = owner;
out = zeros(size(points, 1), 1);
chunk = 20000;
for begin = 1:chunk:size(points, 1)
    rows_p = begin:min(begin + chunk - 1, size(points, 1));
    p = points(rows_p, :);
    near = knnsearch(V, p, 'K', k);
    faces = reshape(incident(near', :)', [], numel(rows_p))';  % candidate faces per point
    [r, c] = find(faces > 0);
    f = faces(sub2ind(size(faces), r, c));
    d = point_triangle_distance(p(r, :), V(F(f, 1), :), V(F(f, 2), :), V(F(f, 3), :));
    out(rows_p) = accumarray(r, d, [numel(rows_p) 1], @min, inf);
end
end


function foot = footprint_mask(cam, V, F)
% Pixels whose centres lie in the projection of any face (the union of the faces)
h = cam.height; w = cam.width;
[uv, z] = project(cam, V);
good = all(z(F) > 0, 2) & all(isfinite(uv(F(:, 1), :)) & isfinite(uv(F(:, 2), :)) & isfinite(uv(F(:, 3), :)), 2);
Fg = F(good, :);
tx = reshape(uv(Fg, 1), [], 3) - 0.5;     % array coordinates: pixel (r, c) centre at (c, r)
ty = reshape(uv(Fg, 2), [], 3) - 0.5;
lo_x = ceil(min(tx, [], 2)); hi_x = floor(max(tx, [], 2));
lo_y = ceil(min(ty, [], 2)); hi_y = floor(max(ty, [], 2));
span = max(max(hi_x - lo_x + 1, hi_y - lo_y + 1), 0);
foot = false(h, w);
max_span = min(max([span; 1]), max(h, w));
[dx, dy] = meshgrid(0:max_span - 1, 0:max_span - 1);
dx = dx(:)'; dy = dy(:)';
chunk = max(1, floor(2e7 / numel(dx)));
for begin = 1:chunk:size(Fg, 1)
    s = begin:min(begin + chunk - 1, size(Fg, 1));
    px = lo_x(s) + dx; py = lo_y(s) + dy;
    in_box = px <= hi_x(s) & py <= hi_y(s);
    x0 = tx(s, 1); y0 = ty(s, 1); x1 = tx(s, 2); y1 = ty(s, 2); x2 = tx(s, 3); y2 = ty(s, 3);
    e0 = (x1 - x0) .* (py - y0) - (y1 - y0) .* (px - x0);   % edge functions: same sign inside
    e1 = (x2 - x1) .* (py - y1) - (y2 - y1) .* (px - x1);
    e2 = (x0 - x2) .* (py - y2) - (y0 - y2) .* (px - x2);
    hit = in_box & ((e0 >= 0 & e1 >= 0 & e2 >= 0) | (e0 <= 0 & e1 <= 0 & e2 <= 0));
    hit = hit & px >= 0 & px < w & py >= 0 & py < h;
    foot(sub2ind([h w], py(hit) + 1, px(hit) + 1)) = true;
end
end


function result = quality_checks(V, F, points, cams, cfg)
% Cloud-to-mesh distance, faces outside a silhouette and silhouette IoU per camera
unit = cfg.world_units_per_mm;
dist = point_mesh_distance(points, V, F);
result = struct();
result.cloud_to_mesh = struct('median', median(dist), 'p75', prctile(dist, 75), ...
    'p90', prctile(dist, 90), 'points', numel(dist), ...
    'median_ref_um', median(dist) / unit * 1000, 'p90_ref_um', prctile(dist, 90) / unit * 1000);
centroids = (V(F(:, 1), :) + V(F(:, 2), :) + V(F(:, 3), :)) / 3;
outside_any = false(size(F, 1), 1);
deepest = -inf;
ious = zeros(numel(cams), 1);
for k = 1:numel(cams)
    cam = cams(k);
    [uv, z] = project(cam, centroids);
    ok = in_image(cam, uv, z);
    values = nan(size(F, 1), 1);
    values(ok) = sample_field(cam.sdf, uv(ok, :));
    outside_any = outside_any | values < -cfg.silhouette_tolerance_px * cam.scale;
    if any(isfinite(values))
        deepest = max(deepest, -min(values) / cam.scale);
    end
    foot = footprint_mask(cam, V, F);
    silhouette = logical(cam.mask);
    judged = true(size(silhouette));   % the field band does not count (prepare_cameras)
    if isfield(cam, 'band') && ~isempty(cam.band), judged = ~logical(cam.band); end
    ious(k) = sum(foot(:) & silhouette(:)) / max(sum((foot(:) | silhouette(:)) & judged(:)), 1);
end
result.faces_outside_a_silhouette_fraction = mean(outside_any);
if isfinite(deepest)
    result.faces_outside_max_native_px = deepest;
else
    result.faces_outside_max_native_px = [];
end
result.silhouette_iou = ious;
if isempty(ious)
    result.silhouette_iou_mean = [];
else
    result.silhouette_iou_mean = mean(ious);
end
end
