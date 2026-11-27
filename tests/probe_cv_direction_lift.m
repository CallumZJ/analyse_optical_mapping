function probe_cv_direction_lift
%% Probe: the CV direction lifted onto a tilted plane points where the wave goes
% Collin Snitchler
% 25.11.2026
% the image CV vector of the Bayly method is along the
% gradient of the activation time in the image, and a gradient pulls back
% onto the surface with the transpose of the projection's Jacobian (A'),
% not its inverse. A synthetic wave on a plane tilted to the camera, with a
% known direction on the plane, is made into an activation map, its CV
% computed by the app's own Bayly fit (rabbit_cv_map.bayly), and the vector
% at the centre lifted with rabbit_rhythm_reproject.lift_direction.
%   D1  the Bayly vector is along the image gradient of the activation time
%   D2  untilted plane: the lifted direction is the wave's direction
%   D3  plane tilted 60 degrees (A = diag(1, 0.5)), wave at 45 degrees on
%       the plane (a worked example): the lifted direction is within 2
%       degrees of 45; the inverse gives about 76
%   D4  the same with the plane also turned about the camera axis and the
%       wave at 120 degrees
%   D5  the tilt-corrected surface speed
%       (rabbit_rhythm_reproject.lift_speed, 1/|A'g| with the same Jacobian)
%       gives back the wave's true speed on the plane, 0.5 m/s, within
%       0.5 % in D2-D4, while the image-plane speed of the tilted planes
%       does not
% No dataset needed. Usage: matlab -batch "addpath('<repo>/tests'); probe_cv_direction_lift" -noFigureWindows
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
results = struct('id', {}, 'ok', {}, 'detail', {});
cases = {'D2 untilted, wave at 30 degrees', 0, 0, 30; ...
    'D3 tilted 60 degrees, wave at 45 degrees (A = diag(1, 0.5))', 60, 0, 45; ...
    'D4 tilted 50 degrees and turned 35 degrees, wave at 120 degrees', 50, 35, 120};
d1_ok = true;
d1_txt = {};
d5_ok = true;
d5_txt = {};
for k = 1:size(cases, 1)
    [err_lift, err_inv, err_t, along, s_surf, s_img] = one_case(cases{k, 2}, cases{k, 3}, cases{k, 4});
    d1_ok = d1_ok && along < 1;
    d5_ok = d5_ok && abs(s_surf / 0.5 - 1) < 0.005 && (cases{k, 2} == 0 || abs(s_img / 0.5 - 1) > 0.05);
    d5_txt{end + 1} = sprintf('%s: surface %.5f, image plane %.4f m/s', strtok(cases{k, 1}), s_surf, s_img); %#ok<AGROW>
    d1_txt{end + 1} = sprintf('%.2f', along); %#ok<AGROW>
    results = add(results, cases{k, 1}, err_lift < 2, sprintf(['lift_direction off by %.2f deg; with the inverse ' ...
        'of A %.2f deg, with A'' %.2f deg'], err_lift, err_inv, err_t));
end
results = [add(struct('id', {}, 'ok', {}, 'detail', {}), 'D1 the Bayly vector is along the image gradient', d1_ok, ...
    ['angle to the gradient (deg): ' strjoin(d1_txt, ', ')]), results];
results = add(results, 'D5 the tilt-corrected surface speed is the true 0.5 m/s within 0.5 %', d5_ok, strjoin(d5_txt, '; '));
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_CV_DIRECTION_LIFT RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_cv_direction_lift:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_cv_direction_lift %d/0\n', n_pass);
end


function [err_lift, err_inv, err_t, along, s_surf, s_img] = one_case(tilt_deg, turn_deg, wave_deg)
% An orthographic camera looking along -z; image x = world x, image y =
% world y (0.1 mm pixels, rows = y). The plane: tilted about x by tilt_deg,
% then turned about z by turn_deg. The wave runs along wave_deg in the
% plane's own basis (u1, u2) at 0.5 mm/ms.
px_mm = 0.1;
c = 0.5;
Rz = [cosd(turn_deg) -sind(turn_deg) 0; sind(turn_deg) cosd(turn_deg) 0; 0 0 1];
u1 = (Rz * [1; 0; 0])';
u2 = (Rz * [0; cosd(tilt_deg); sind(tilt_deg)])';
n = cross(u1, u2);
d_true = cosd(wave_deg) * u1 + sind(wave_deg) * u2;
% Image point (x, y) mm -> plane coordinates (a, b): [x; y] = P * [a; b]
P = [u1(1:2)', u2(1:2)'];
H = 81; W = 81;
[cols, rows] = meshgrid(1:W, 1:H);
x = (cols - 41) * px_mm;
y = (rows - 41) * px_mm;
ab = P \ [x(:)'; y(:)'];
t = (cosd(wave_deg) * ab(1, :) + sind(wave_deg) * ab(2, :)) / c + 50;
act = reshape(t, H, W);
S = 1000 * px_mm * ones(H, W);   % um per pixel
V = ones(H, W);
cv = rabbit_cv_map.bayly(act, S, V, 1.5, 100, false);
% Layer 1 the row (down = +y) component, layer 2 the column (+x) one
v = [cv(41, 41, 2), cv(41, 41, 1)];
% The image gradient of the activation time (ms per pixel), analytic
g = ([cosd(wave_deg), sind(wave_deg)] / (P)) * px_mm;   % row vector d t / d [x y] in pixels
along = acosd(abs(dot(v, g)) / (norm(v) * norm(g)));
% The Jacobian of the image pixel with respect to the 3D point
Jx = [1 0 0] / px_mm;
Jy = [0 1 0] / px_mm;
d = rabbit_rhythm_reproject.lift_direction(Jx, Jy, n, v);
err_lift = acosd(max(-1, min(1, dot(d, d_true))));
% The two pull-backs, in the plane's basis (u1, u2)
A = [Jx * u1', Jx * u2'; Jy * u1', Jy * u2'];
di = A \ v(:);
dt = A' * v(:);
err_inv = angle_to(di(1) * u1 + di(2) * u2, d_true);
err_t = angle_to(dt(1) * u1 + dt(2) * u2, d_true);
% The speed on the plane: v is in mm/ms, the pixel 0.1 mm
s_surf = rabbit_rhythm_reproject.lift_speed(Jx, Jy, n, v, px_mm);
s_img = cv(41, 41, 3);
end


function a = angle_to(d, d_true)
a = acosd(max(-1, min(1, dot(d / norm(d), d_true))));
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
