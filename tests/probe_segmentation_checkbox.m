function probe_segmentation_checkbox
%% Probe: the assisted area segmentation window's reconstruction checkbox
% Collin Snitchler
% 20.11.2026
% The user: keep the window as it was, with one checkbox for
% applying the same segmentation settings to the reconstruction images.
%   S1  no reconstruction preview or COLMAP mask button; the checkbox sits
%       in row 2, columns 7-9; no other control shares a cell with
%       Confirm polygon changes (the hidden-button regression)
%   S2  ticked, Confirm area records apply, threshold and smoothen
%   S3  the window opens again with the last choice; unticked is recorded
%   S4  a Run's masks are written from the recorded settings into the
%       reconstruction images' own cut, without a picker
% Usage: matlab -batch "addpath('<repo>'); addpath('<repo>/tests/helpers'); probe_segmentation_checkbox"
pass = 0; fail = 0;
main = seg_main_double();
main.opticalmappingUIFigure = uifigure('Visible', 'off');
c1 = onCleanup(@() delete(main.opticalmappingUIFigure));
H = 40; W = 60;
st = zeros(H, W, 5);
st(10:30, 15:45, :) = 1;                                   % a bright "heart" on a dark background
main.processed_data = struct('image_stack', {{st}}, 'height', H, 'width', W, 'keep_area_poly', []);

s = segmentationAssist(main);
cb = s.ApplyToReconstructionCheckBox;
ctl = findall(s.GridLayout.Children, 'flat');
txt = arrayfun(@(c) string(get_text(c)), ctl);
cp = s.ConfirmpolygonchangesButton.Layout;
share = false;
for k = 1:numel(ctl)
    if ctl(k) == s.ConfirmpolygonchangesButton, continue; end
    L = ctl(k).Layout;
    share = share || (any(ismember(L.Row(1):L.Row(end), cp.Row(1):cp.Row(end))) && ...
        any(ismember(L.Column(1):L.Column(end), cp.Column(1):cp.Column(end))));
end
record('S1 window: checkbox in row 2, columns 7-9; no reconstruction buttons; Confirm polygon changes uncovered', ...
    isequal(cb.Layout.Row, 2) && isequal(cb.Layout.Column, [7 9]) && ~cb.Value && ~share && ...
    ~any(contains(txt, ["Preview on reconstruction", "COLMAP"])), strjoin(txt, ' | '));
cb.Value = true;
feval(s.ConfirmareaButton.ButtonPushedFcn, s.ConfirmareaButton, []);
rs = main.processed_data.reconstruction_segmentation;
record('S2 ticked: Confirm area records apply, threshold 0.83, smoothen 4', ...
    rs.apply && rs.threshold == 0.83 && rs.sigma_gauss == 4, jsonencode(rs));

s = segmentationAssist(main);
was = s.ApplyToReconstructionCheckBox.Value;
s.ApplyToReconstructionCheckBox.Value = false;
feval(s.ConfirmareaButton.ButtonPushedFcn, s.ConfirmareaButton, []);
record('S3 opens with the last choice; unticked is recorded', was && ~main.processed_data.reconstruction_segmentation.apply, '');

% S4: a cut of the reconstruction images (four views) and an ROI file
root = tempname; mkdir(root);
c2 = onCleanup(@() rmdir(root, 's'));
cut = fullfile(root, 'cut_tiffs_reconstruction_rec');
mkdir(cut);
b4 = [1 1 20 15; 1 16 20 30; 21 1 40 15; 21 16 40 30];
for v = 1:4
    im = zeros(20, 15, 'uint16'); im(5:15, 4:12) = 1000;
    imwrite(im, fullfile(cut, sprintf('rec_f001_view%d.tiff', v)));
end
js = fullfile(root, 'roi.json');
rabbit_stack_io.save_roi_json(js, struct('schema_version', 1, 'region_bounds_src', b4, 'regions', 4, ...
    'rotation', 3, 'rabbit_panoramic', true, 'source_dims', struct('height', H, 'width', W), ...
    'coordinate_origin', 'top-left', 'unmirrored_coordinates', true, 'reconstruction_path', fullfile(root, 'rec.fits')));
app = om_app_double();
app.file_info = struct('file', fullfile(root, 'om.fits'), 'name', 'om.fits', 'path', root, 'type', '.fits');
app.processed_data = struct('keep_area_poly', []);
n_dlg = numel(getappdata(groot, 'om_headless_dialogs'));   % every file or folder picker is recorded there
[ok, mroot, msg] = rabbit_segmentation_masks.write_for_run(app, js, cut, struct('threshold', 0.5, 'sigma_gauss', 1));
pngs = dir(fullfile(mroot, '*.png'));
m1 = [];
if numel(pngs) == 4, m1 = imread(fullfile(mroot, 'rec_f001_view1.tiff.png')); end
record('S4 Run masks: four COLMAP masks from the recorded settings, no picker', ok && numel(pngs) == 4 && ...
    endsWith(mroot, 'masks_reconstruction_rec') && ~isempty(m1) && m1(10, 8) == 255 && m1(1, 1) == 0 && ...
    numel(getappdata(groot, 'om_headless_dialogs')) == n_dlg, sprintf('%d, %s %s', ok, mroot, msg));
d = rabbit_sfm_build.find_mask(mroot, 'rec_f001_view2.tiff');
record('S4b the sparse build finds each image''s mask by its name', ~isempty(d), d);

fprintf('\nPROBE_SEGMENTATION_CHECKBOX RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('%d check(s) failed.', fail);
end

    function record(name, ok, detail)
        if ok
            fprintf('PASS %s\n', name); pass = pass + 1;
        else
            fprintf('FAIL %s: %s\n', name, detail); fail = fail + 1;
        end
    end
end

function t = get_text(c)
% A control's text, or its type when it has none
if isprop(c, 'Text'), t = char(c.Text); else, t = class(c); end
end
