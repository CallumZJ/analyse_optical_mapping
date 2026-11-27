function probe_cut_progress
%% Probe: the TIFF cut shows one progress dialog on the app's window, with Cancel
% Collin Snitchler
% 20.11.2026
% The user: the cut ran in the background while the app looked usable but
% no button worked. The cut now shows one progress dialog on the app's
% window for the whole cut (which keeps the app from being clicked), with a
% message per phase and Cancel.
%   P1  a cut of the optical mapping and reconstruction images: one dialog,
%       Cancelable, the bar ends full, the reading, writing and regions file
%       messages were shown, the dialog is closed before "TIFF copies made"
%   P2  Cancel during the writing: the folder being written is removed, no
%       later dataset is cut, no regions file, the dialog is closed and an
%       alert says the cut was cancelled
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder:
%   matlab -batch "addpath('<repo>/tests'); probe_cut_progress"
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');   % dialogs answered by the stand-ins
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));
addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));
pass = 0; fail = 0;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
fig = uifigure('Visible', 'off');
fig_cleanup = onCleanup(@() delete(fig)); %#ok<NASGU>
setappdata(groot, 'om_headless_cancel_after', []);

rec = fullfile(root, 'rec.tif');
for k = 1:30
    imwrite(uint16(k * ones(40, 60)), rec, 'WriteMode', pick(k == 1, 'overwrite', 'append'));
end
bounds = [1 1 40 10; 1 12 40 22; 1 24 40 34; 1 36 40 46];

%% P1 a whole cut
[app, out] = make_app(fullfile(root, 'p1'), rec, bounds, fig);
setappdata(groot, 'om_headless_dialogs', []);
headless_push('uigetdir', out);
ok = rabbit_cut_tiffs.cut_inline(app);
dlg = getappdata(groot, 'om_headless_last_progress');
msgs = string(dlg.MessageHistory);
d = getappdata(groot, 'om_headless_dialogs');
titles = arrayfun(@(x) string(x.title), d);
record('P1 one Cancelable dialog, full at the end, closed before TIFF copies made', ok && isa(dlg, 'headless_progress') && ...
    strcmp(dlg.Title, 'Cutting TIFF copies') && strcmp(dlg.Cancelable, 'on') && dlg.closed && abs(dlg.Value - 1) < 1e-9 && ...
    any(titles == "TIFF copies made") && ~isempty(app.data.cut_roi_json), ...
    sprintf('ok %d, value %g, closed %d, dialogs: %s', ok, dlg.Value, dlg.closed, strjoin(titles, ', ')));
record('P1b messages: reading, writing per view and frame, the regions file', ...
    any(contains(msgs, 'Reading the reconstruction images')) && ...
    any(contains(msgs, 'Writing the optical mapping copies: view 4 of 4, frame 30 of 30')) && ...
    any(contains(msgs, 'Writing the reconstruction copies: view 1 of 4')) && any(contains(msgs, 'Writing the regions file')), ...
    strjoin(unique(msgs), ' | '));

%% P2 Cancel during the optical mapping copies
[app, out] = make_app(fullfile(root, 'p2'), rec, bounds, fig);
setappdata(groot, 'om_headless_dialogs', []);
setappdata(groot, 'om_headless_cancel_after', 3);          % the third Cancel check: view 1, frame 20
headless_push('uigetdir', out);
ok = rabbit_cut_tiffs.cut_inline(app);
setappdata(groot, 'om_headless_cancel_after', []);
dlg = getappdata(groot, 'om_headless_last_progress');
d = getappdata(groot, 'om_headless_dialogs');
msg = '';
if ~isempty(d), msg = d(end).message; end
left = dir(fullfile(out, 'cut_tiffs_*'));
record('P2 Cancel: the folder removed, nothing more cut, no regions file, an alert', ~ok && dlg.closed && ...
    isempty(left) && isempty(app.data.cut_roi_json) && contains(msg, 'cancelled') && ...
    isempty(dir(fullfile(out, 'regions_*.json'))), sprintf('ok %d; %d folders left; "%s"', ok, numel(left), msg));

fprintf('\nPROBE_CUT_PROGRESS RESULT: %d passed, %d failed\n', pass, fail);
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

function [app, out] = make_app(out, rec, bounds, fig)
% An app double with a 40 x 60 x 30 optical mapping stack and a
% reconstruction recording of the same size
mkdir(out);
app = cut_app_double();
app.opticalmappingUIFigure = fig;
app.file_info = struct('file', 'om.fits', 'name', 'om.fits', 'path', out, 'type', '.fits');
app.data = struct('image_stack', uint16(reshape(1:40 * 60 * 30, 40, 60, 30)), 'height', 40, 'width', 60, ...
    'rabbit_panoramic', 1, 'region_bounds_src', bounds, 'reconstruction_path', rec);
end

function v = pick(c, a, b)
if c, v = a; else, v = b; end
end
