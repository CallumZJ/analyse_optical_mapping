function probe_binning_keeps_rois
%% Probe: binning keeps the ROIs and the segmentation area, and Undo restores them
% Collin Snitchler
% 20.11.2026
% The user: binning after selecting an ROI in the Processing tab removed
% that ROI. Binning now rescales the ROIs and the segmentation area to the
% binned image, and Undo puts the earlier ones back. On a synthetic
% recording (20 x 20 pixels, 200 frames), pressing the buttons a user
% presses:
%   N1  2x2 binning keeps the rectangle ROI, at half the size (pixel
%       centres: x_new = (x - 0.5) / 2 + 0.5), with a 10 x 10 mask, its
%       trace and the dropdowns; the history says the ROI was rescaled
%   N2  the ROI trace is the mean of the binned stack over the ROI's pixels
%   N3  the segmentation area is 10 x 10 too (NaN = excluded, the same
%       part of the image) and multiplies the binned stack without error
%   N4  Undo: the 20 x 20 stack, the ROI at its first position and size,
%       a 20 x 20 mask and the first segmentation area
%   N5  seven rectangles and a freehand ROI survive binning, redrawn by
%       createROI (the 7th in colour row 7); an ellipse, which the app
%       does not make (drawellipse ignores a Position), is left out
%   N6  Undo puts the binning back to 1, a second Undo (the binned image
%       again) to 2, and a third to 1 with the first ROI
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -batch "addpath('<repo>/tests'); probe_binning_keeps_rois"
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');   % the app must stay hidden
repo_dir = fileparts(fileparts(mfilename('fullpath')));    % the repository folder (this file is in tests/)
addpath(repo_dir);                                          % the app and its helpers
addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));   % dialog stand-ins
pass = 0; fail = 0;                                         % check counters
root = tempname;                                            % throw-away folder for the recording
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>     % removed when the probe ends

rng(3, 'twister');                                          % repeatable values
stack = 1000 + 100 * rand(20, 20, 200);                     % a small recording
rec = fullfile(root, 'synthetic_recording.mat');
save(rec, 'stack');                                         % the app loads the variable 'stack'
a = analyse_optical_mapping;                                % start the app (hidden)
app_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>
headless_push('uigetfile', rec);                            % File selector
headless_push('inputdlg', {'500'});                         % Enter fps
headless_push('uiconfirm', 'Continue');                     % no regions
feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
a.signalregiontype.Value = 'Rectangle';
headless_push('drawrectangle', [6 6 8 8]);                  % ROI in the middle of the field
feval(a.signalregion.ButtonPushedFcn, a.signalregion, []);
keep = ones(20, 20); keep(:, 1:4) = NaN;                    % a segmentation area: the left 4 columns excluded
a.processed_data.keep_area_poly = keep;
a.processed_data.keep_area_poly_vertices = {[4.5 0.5; 20.5 0.5; 20.5 20.5; 4.5 20.5]};

threw = '';
try
    a.BinSpinner.Value = 2;
    feval(a.binning.ButtonPushedFcn, a.binning, []);
catch ME
    threw = getReport(ME, 'basic');
end
pd = a.processed_data;
h = a.display.ROI_handle;
hist = a.history_field.Value;
record('N1 binning keeps the ROI at half size with its mask, trace and dropdowns', isempty(threw) && ...
    numel(h) == 1 && max(abs(h{1}.Position - [3.25 3.25 4 4])) < 1e-9 && isequal(size(a.display.ROI_mask{1}), [10 10]) && ...
    size(pd.signals, 1) == 1 && numel(a.ROIdropdown.Items) == 1 && contains(hist{end}, '1 ROI rescaled'), ...
    sprintf('%s | %s', threw, hist{end}));
m = a.display.ROI_mask{1};
binned = pd.image_stack{1};
ref = squeeze(mean(binned .* m, [1 2], 'omitnan'));
record('N2 the ROI trace is the mean of the binned stack over the ROI', ...
    numel(pd.signals{1, 2}) == numel(ref) && max(abs(pd.signals{1, 2}(:) - ref(:))) < 1e-6 * max(abs(ref)), '');
ok3 = isequal(size(pd.keep_area_poly), [10 10]) && all(isnan(pd.keep_area_poly(:, 1:2)), 'all') && ...
    all(pd.keep_area_poly(:, 3:end) == 1, 'all');
try
    x = pd.image_stack{1} .* pd.keep_area_poly; %#ok<NASGU>
catch ME
    ok3 = false; threw = ME.message;
end
record('N3 the segmentation area is 10 x 10 and multiplies the binned stack', ok3, threw);

threw = '';
try
    feval(a.undolast.ButtonPushedFcn, a.undolast, []);
catch ME
    threw = getReport(ME, 'basic');
end
pd = a.processed_data;
h = a.display.ROI_handle;
record('N4 Undo: the first stack, ROI and segmentation area', isempty(threw) && pd.height == 20 && ...
    numel(h) == 1 && max(abs(h{1}.Position - [6 6 8 8])) < 1e-9 && isequal(size(a.display.ROI_mask{1}), [20 20]) && ...
    isequaln(pd.keep_area_poly, keep), threw);

% N6: the binning follows Undo both ways (the pixel size of the
% Conduction Velocity tab follows it, rabbit_calibration_scale)
threw = '';
b = nan(1, 3); hh = nan(1, 3);
try
    b(1) = a.processed_data.binning; hh(1) = a.processed_data.height;
    feval(a.undolast.ButtonPushedFcn, a.undolast, []);
    b(2) = a.processed_data.binning; hh(2) = a.processed_data.height;
    feval(a.undolast.ButtonPushedFcn, a.undolast, []);
    b(3) = a.processed_data.binning; hh(3) = a.processed_data.height;
catch ME
    threw = getReport(ME, 'basic');
end
h = a.display.ROI_handle;
record('N6 Undo restores the binning; a second Undo the binned one; a third the first again', isempty(threw) && ...
    isequal(b, [1 2 1]) && isequal(hh, [20 10 20]) && numel(h) == 1 && max(abs(h{1}.Position - [6 6 8 8])) < 1e-9, ...
    sprintf('%s | binning %s, height %s', threw, mat2str(b), mat2str(hh)));

% N5: seven ROIs (the 7th took colour row 0 in createROI before), a
% freehand ROI and an ellipse; binning redraws them through createROI
for k = 2:7
    headless_push('drawrectangle', [1 + k, 2, 2, 2]);
    feval(a.signalregion.ButtonPushedFcn, a.signalregion, []);
end
fh_pos = [12 12; 16 12; 16 16; 12 16];
fh = drawfreehand(a.display.ROI_handle{1}.Parent, 'Position', fh_pos);
a.display.ROI_handle{end + 1} = fh;
a.display.ROI_mask{end + 1} = double(createMask(fh, 20, 20));
a.display.ROI_handle{end + 1} = drawellipse(a.display.ROI_handle{1}.Parent, 'Center', [15 5], 'SemiAxes', [2 1]);
threw = '';
try
    a.BinSpinner.Value = 2;
    feval(a.binning.ButtonPushedFcn, a.binning, []);
catch ME
    threw = getReport(ME, 'basic');
end
h = a.display.ROI_handle;
types = cellfun(@class, h, 'UniformOutput', false);
ok5 = isempty(threw) && numel(h) == 8 && sum(strcmp(types, 'images.roi.Rectangle')) == 7 && ...
    strcmp(types{8}, 'images.roi.Freehand') && max(abs(h{8}.Position - ((fh_pos - 0.5) / 2 + 0.5)), [], 'all') < 1e-9 && ...
    max(abs(h{7}.Color - [0.6350 0.0780 0.1840])) < 1e-9;
record('N5 seven rectangles and a freehand ROI survive binning through createROI; the ellipse is left out', ok5, ...
    sprintf('%s | %d ROI: %s', threw, numel(h), strjoin(types, ', ')));

fprintf('\nPROBE_BINNING_KEEPS_ROIS RESULT: %d passed, %d failed\n', pass, fail);
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
