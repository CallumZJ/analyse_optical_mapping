function probe_load_failure
%% Probe: a load that stops says why; Load regions Cancel leaves the app as it was
% Collin Snitchler
% 19.11.2026
% An out-of-memory File > Load file
% left a blank app with the error only in the command window (F33), and
% the Reconstruction tab was never told (F35); Cancel in Load regions'
% file selector threw an error (F34).
%   L1  File > Load file on an unreadable FITS file: an alert in the app
%       names the file, the app holds no file afterwards and the
%       Reconstruction tab has no dataset bound.
%   L2  Regions > Load regions, file selector cancelled: no error, the
%       regions are unchanged.
%   L3  Load regions on a .mat file without saved regions: an alert says
%       so and points to the ROI editor for ROI files.
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder;
%   matlab -batch "addpath('<repo>/tests'); probe_load_failure"
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));
pass = 0; fail = 0;
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
setappdata(groot, 'om_headless_dialogs', []);

a = analyse_optical_mapping;
app_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>

%% L1 an unreadable FITS file
bad = fullfile(root, 'broken_recording.fits');
fid = fopen(bad, 'w');
fwrite(fid, uint8(mod(1:5000, 251)), 'uint8');   % not a FITS header
fclose(fid);
headless_push('uigetfile', bad);
threw = '';
try
    feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
catch ME
    threw = ME.message;
end
d = getappdata(groot, 'om_headless_dialogs');
alerts = d(strcmp({d.kind}, 'uialert'));
said = ~isempty(alerts) && strcmp(alerts(end).title, 'Load file') && contains(alerts(end).message, 'broken_recording.fits');
record('L1 an unreadable file: an alert in the app names it; no file held; no dataset bound', ...
    isempty(threw) && said && isempty(a.data.image_stack) && isempty(a.file_info.name) && ...
    isempty(a.recon.ReconstructionDatasetField.Value), ...
    sprintf('threw "%s" | %s', threw, strjoin(arrayfun(@(x) x.message, alerts, 'UniformOutput', false), ' | ')));

%% L2 Load regions, file selector cancelled
before = a.data.region_bounds;
threw = '';
try
    feval(a.LoadRegionsMenu.MenuSelectedFcn, a.LoadRegionsMenu, []);   % nothing queued: Cancel
catch ME
    threw = ME.message;
end
record('L2 Load regions cancelled: no error, regions unchanged', ...
    isempty(threw) && isequal(a.data.region_bounds, before), threw);

%% L3 a .mat file without saved regions
other = fullfile(root, 'not_regions.mat');
x = 1; save(other, 'x'); %#ok<NASGU>
headless_push('uigetfile', other);
threw = '';
try
    feval(a.LoadRegionsMenu.MenuSelectedFcn, a.LoadRegionsMenu, []);
catch ME
    threw = ME.message;
end
d = getappdata(groot, 'om_headless_dialogs');
alerts = d(strcmp({d.kind}, 'uialert'));
record('L3 a .mat without regions: an alert says so and points to the ROI editor', ...
    isempty(threw) && ~isempty(alerts) && strcmp(alerts(end).title, 'Load regions') && ...
    contains(alerts(end).message, 'Load ROI JSON') && isequal(a.data.region_bounds, before), threw);

fprintf('\nPROBE_LOAD_FAILURE RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('%d check(s) failed.', fail);
end

    function record(name, ok, detail)
        if ok
            fprintf('PASS %s\n', name);
            pass = pass + 1;
        else
            fprintf('FAIL %s: %s\n', name, detail);
            fail = fail + 1;
        end
    end
end
