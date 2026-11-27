function probe_cv_arrow_gradient
%% Probe gate: the 3-D CV arrows agree with the gradient of the projected activation
% Collin Snitchler
% 25.11.2026
% A check only, no app change. A plane wave across the OM canvas is the
% activation map; its CV map is the app's own Bayly fit of it; both are
% projected (Redo projection, headless, on a copy of a completed run). On
% the mesh, each face's activation gradient (from the vertex means of the
% projected activation, in the face's plane) points where the wave goes; the
% CV direction lifted onto the face (cv_direction.mat, F6) must point the
% same way.
%   A1  DIRECT faces with both: the median angle between the CV arrow and the
%       activation gradient is below 30 degrees and at least 75 % are within
%       45 degrees (the gate); the numbers are printed for the record
% Needs OM_APP_HEADLESS=1, MATLAB_PREFDIR, and OM_REDO_DS, OM_REDO_STEM and
% OM_REDO_RUN as probe_reproject_redo.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_cv_arrow_gradient" -noFigureWindows
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
assert(~isempty(getenv('MATLAB_PREFDIR')), 'Set MATLAB_PREFDIR to a throw-away folder.');
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
addpath(fullfile(repo, 'tests', 'helpers'));
addpath(fullfile(repo, 'tests', 'helpers', 'headless'));
stem = getenv('OM_REDO_STEM');
run_id = getenv('OM_REDO_RUN');
[root, cleanup] = om_redo_copy('probe_cv_arrow_gradient', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
if isempty(root), return; end                      % SKIP printed
run_dir = fullfile(root, [stem '.matom'], 'reconstruction', 'runs', run_id);
setappdata(groot, 'om_headless_queue', struct());
setappdata(groot, 'om_headless_dialogs', []);
warning('off', 'MATLAB:singularMatrix'); warning('off', 'MATLAB:nearlySingularMatrix');

%% A plane wave on the canvas and its Bayly CV map
saved = load(fullfile(run_dir, 'stages', 'reprojection', 'om_frame_image.mat'), 'om_image');
om_image = double(saved.om_image);
fin = isfinite(om_image);
om_image(~fin) = min(om_image(fin));
[H, W] = size(om_image);
[cc, rr] = meshgrid(1:W, 1:H);
map = 20 + 0.25 * rr + 0.15 * cc;              % ms: a wave down and to the right on the canvas
S = 258 * ones(H, W);
cv = rabbit_cv_map.bayly(map, S, ones(H, W), 3, 100);
tab = rabbit_reconstruction_tab();
[ok, err] = tab.load_state(root, stem);
assert(ok, err);
app = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
app.bind_reconstruction_tab_for_test(tab);
app.recon.ReconstructionDatasetField.Value = fullfile(root, stem);
recording = rabbit_reconstruction_tab.recording_stem(root, stem);
app.file_info.path = root;
app.file_info.name = [recording '.fits'];
app.file_info.type = '.fits';
app.processed_data.activation_map = map;
app.processed_data.image_stack = {repmat(om_image, 1, 1, 3)};
app.display.normalisation = 1;
app.first_processed_frame = om_image;
app.data.fps = 500;
app.processed_data.CV_map = cv;
app.CV_method.Value = app.CV_method.Items{1};
app.recon.reconstruction_update_run_list();
items = app.recon.ReconstructionRunList.Items;
app.recon.ReconstructionRunList.Value = items{find(contains(items, run_id), 1)};
headless_push('uiconfirm', 'Redo projection');
headless_push('uiconfirm', 'Map only');
app.recon.ReconstructionReprojectButtonPushed();

%% A1
rp = fullfile(run_dir, 'outputs', 'reprojection');
mesh = rabbit_rhythm_reproject.read_ply_mesh(fullfile(rp, 'activation_projected.ply'));
fa = read_cdf_values(fullfile(rp, 'activation_projected.cdf'));
w = load(fullfile(rp, 'cv_direction.mat'), 'direction');
F = mesh.faces; P = mesh.pts;
use = isfinite(fa) & fa ~= 0;
nV = size(P, 1);
sv = accumarray(reshape(F(use, :), [], 1), repmat(fa(use), 3, 1), [nV 1]);
cn = accumarray(reshape(F(use, :), [], 1), 1, [nV 1]);
tv = sv ./ cn; tv(cn == 0) = NaN;
% Per face: the gradient of the linear activation over the triangle, in its plane
p1 = P(F(:, 1), :); p2 = P(F(:, 2), :); p3 = P(F(:, 3), :);
e1 = p2 - p1; e2 = p3 - p1;
d1 = tv(F(:, 2)) - tv(F(:, 1)); d2 = tv(F(:, 3)) - tv(F(:, 1));
n = cross(e1, e2, 2);
a2 = sum(n .^ 2, 2);
g = (d1 .* cross(e2, n, 2) + d2 .* cross(n, e1, 2)) ./ a2;   % grad t = (dt1 (e2 x n) + dt2 (n x e1)) / |n|^2
D = w.direction;
% DIRECT faces only: the canvas wave runs another way in each view's tile,
% so faces that average views have no single direction to agree with
cls = load(fullfile(rp, 'activation_confidence.mat'), 'face_class');
both = all(isfinite(D), 2) & all(isfinite(g), 2) & vecnorm(g, 2, 2) > 0 & use & cls.face_class(:) == 1;
ang = acosd(max(-1, min(1, sum(D(both, :) .* g(both, :), 2) ./ (vecnorm(D(both, :), 2, 2) .* vecnorm(g(both, :), 2, 2)))));
med = median(ang);
within = 100 * mean(ang <= 45);
ok1 = nnz(both) > 1000 && med < 30 && within >= 75;
fprintf('%s A1 CV arrows against the activation gradient on the mesh: %d faces, median %.1f deg, %.1f %% within 45 deg, %.1f %% within 90 deg\n', ...
    ternary(ok1, 'PASS', 'FAIL'), nnz(both), med, within, 100 * mean(ang <= 90));
fprintf('\nPROBE_CV_ARROW_GRADIENT RESULT: %d passed, %d failed\n', ok1, ~ok1);
if ~ok1
    error('probe_cv_arrow_gradient:Failed', 'The CV arrows and the activation gradient disagree.');
end
fprintf('PROBE_OK probe_cv_arrow_gradient 1/0\n');
end


function v = read_cdf_values(p)
fid = fopen(p, 'rb');
c = onCleanup(@() fclose(fid));
for k = 1:8, fgetl(fid); end
v = double(fread(fid, Inf, 'float32'));
end


function t = ternary(c, a, b)
if c, t = a; else, t = b; end
end
