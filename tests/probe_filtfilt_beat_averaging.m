function probe_filtfilt_beat_averaging
%% Probe: temporal filtering (FiltFiltM) and beat averaging with the path a user has
% Collin Snitchler
% 20.11.2026
% The user's saved MATLAB path named FilterM_20Jul2011 inside the repository
% folder, where it no longer is, so FiltFiltM was not found: Temporal filter
% stopped with 'Missing function'. Undo after that emptied the image stack
% (no earlier step was kept) and stopped with an error, so beat averaging had
% no data. This probe runs with the path MATLAB starts with (no MATLABPATH,
% no addpath of File Exchange folders), on a small synthetic recording
% (20 x 20 pixels, 1200 frames at 500 fps, 8 beats), pressing the buttons
% the user presses:
%   B1  File > Load file (a .mat stack), Continue, Select ROI: one signal
%   B2  Undo with no step to undo: no error, the stack is kept, an alert
%       says there is nothing to undo
%   B3  Temporal filter, Butterworth 40 Hz order 4: no alert, the history
%       names the filter, the stack equals a zero-phase reference (filtfilt
%       of the Signal Processing Toolbox along time, relative difference
%       below 1e-9)
%   B4  Undo, then Temporal filter, FIR 40 Hz order 30: the same checks
%   B5  Temporal filter, FIR order 450 (longer than the recording allows):
%       no error, an alert names the reason, the stack and history are kept
%   B6  Average beats (OK, then Average in the beat averaging window): no
%       error, the history says so, the stack is one beat long and equals
%       the mean of the beats the window cut
%   B7  FiltFiltM comes from third_party/FilterM, or from the user's own
%       copy when one was on the path before the app started
% Usage: OM_APP_HEADLESS=1, MATLAB_PREFDIR set to a throw-away folder, and
%   MATLABPATH not set (the path a user has):
%   matlab -batch "addpath('<repo>/tests'); probe_filtfilt_beat_averaging"
assert(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'Run with OM_APP_HEADLESS=1.');   % the app must stay hidden
repo_dir = fileparts(fileparts(mfilename('fullpath')));   % the repository folder (this file is in tests/)
addpath(repo_dir);                                         % the app and its helpers
addpath(fullfile(repo_dir, 'tests', 'helpers', 'headless'));   % dialog stand-ins
own_copy = which('FiltFiltM');                             % a copy the user installed, if any
fprintf('MATLABPATH: "%s"; FiltFiltM before the app starts: "%s"\n', getenv('MATLABPATH'), own_copy);
pass = 0; fail = 0;                                        % check counters
root = tempname;                                           % throw-away folder for the recording
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>    % removed when the probe ends
setappdata(groot, 'om_headless_dialogs', []);              % no dialogs recorded yet

%% Synthetic recording: 8 action potentials on a 20 x 20 field
fps = 500;                                                  % frames per second
n_frames = 1200;                                            % 2.4 s
t = (0:n_frames - 1) / fps;                                 % time of each frame in s
rng(7, 'twister');                                          % repeatable noise
[col, row] = meshgrid(1:20, 1:20);                          % pixel coordinates
delay = 0.0005 * (col + row);                               % activation spreads across the field (s)
stack = zeros(20, 20, n_frames);                            % the recording
for k = 1:8
    t0 = 0.15 + 0.28 * (k - 1);                             % start of beat k (s)
    s = reshape(t, 1, 1, []) - t0 - delay;                  % time since activation, per pixel
    up = 1 ./ (1 + exp(-s / 0.002));                        % fast upstroke
    down = 1 ./ (1 + exp((s - 0.09) / 0.015));              % repolarisation after about 90 ms
    stack = stack + 800 * up .* down;                       % add the action potential
end
stack = 1000 + stack + 40 * randn(size(stack)) + ...
    60 * sin(2 * pi * 120 * reshape(t, 1, 1, []));          % baseline, noise and 120 Hz interference
rec = fullfile(root, 'synthetic_recording.mat');
save(rec, 'stack');                                         % the app loads the variable 'stack'

a = analyse_optical_mapping;                                % start the app (hidden)
app_cleanup = onCleanup(@() delete(a)); %#ok<NASGU>

%% B1 load, Continue, Select ROI
headless_push('uigetfile', rec);                            % File selector
headless_push('inputdlg', {num2str(fps)});                  % Enter fps
headless_push('uiconfirm', 'Continue');                     % no regions
threw = '';
try
    feval(a.LoadfileMenu.MenuSelectedFcn, a.LoadfileMenu, []);
    a.signalregiontype.Value = 'Rectangle';
    headless_push('drawrectangle', [6 6 8 8]);              % ROI in the middle of the field
    feval(a.signalregion.ButtonPushedFcn, a.signalregion, []);
catch ME
    threw = getReport(ME, 'basic');
end
record('B1 load, Continue, Select ROI: one signal', isempty(threw) && ...
    size(a.processed_data.signals, 1) == 1 && a.processed_data.n_frames == n_frames, threw);
raw = a.processed_data.image_stack{1};                      % the stack before filtering

%% B2 Undo with nothing to undo
n_dlg = numel(getappdata(groot, 'om_headless_dialogs'));
threw = '';
try
    feval(a.undolast.ButtonPushedFcn, a.undolast, []);      % Undo last
catch ME
    threw = ME.message;
end
new = dialogs_since(n_dlg);
record('B2 Undo with nothing to undo: stack kept, an alert says so', isempty(threw) && ...
    isequal(a.processed_data.image_stack{1}, raw) && any(strcmp({new.title}, 'Undo')), ...
    sprintf('threw "%s" | stack %s | dialogs: %s', threw, mat2str(size(a.processed_data.image_stack{1})), joined(new)));
if ~isequal(a.processed_data.image_stack{1}, raw)
    a.processed_data.image_stack{1} = raw;                  % put the data back so later checks still say something
end

%% B3 Butterworth
[ok, detail] = run_filter('1', 40, 4, 'BUTTERWORTH(cutoff40, order=4)');
record('B3 Temporal filter, Butterworth: no alert, history, zero-phase result', ok, detail);

%% B4 FIR (after Undo)
threw = '';
try
    feval(a.undolast.ButtonPushedFcn, a.undolast, []);      % Undo last: back to the unfiltered stack
catch ME
    threw = ME.message;
end
undone = isempty(threw) && isequal(a.processed_data.image_stack{1}, raw);
[ok, detail] = run_filter('2', 40, 30, 'FIR(cutoff40, order=30)');
record('B4 Undo, Temporal filter, FIR: no alert, history, zero-phase result', undone && ok, ...
    sprintf('undo: %d %s | %s', undone, threw, detail));
filtered = a.processed_data.image_stack{1};                 % the stack beat averaging starts from

%% B5 a filter too long for the recording
hist_before = a.history.current;
lines_before = numel(a.history_field.Value);
n_dlg = numel(getappdata(groot, 'om_headless_dialogs'));
a.TemporalFilterType.Value = '2';                           % FIR
a.cutofffrequency.Value = 40;
a.filterorder.Value = 450;                                  % 3 x 450 edge frames > 1200 frames
threw = '';
try
    feval(a.temporalfilter.ButtonPushedFcn, a.temporalfilter, []);
catch ME
    threw = ME.message;
end
new = dialogs_since(n_dlg);
record('B5 a filter too long: an alert says why, stack and history kept', isempty(threw) && ...
    isequal(a.processed_data.image_stack{1}, filtered) && strcmp(a.history.current, hist_before) && ...
    numel(a.history_field.Value) == lines_before && any(strcmp({new.title}, 'Temporal filter')), ...
    sprintf('threw "%s" | dialogs: %s', threw, joined(new)));
if ~isequal(a.processed_data.image_stack{1}, filtered)
    a.processed_data.image_stack{1} = filtered;             % put the data back for B6
end

%% B6 Average beats
n_dlg = numel(getappdata(groot, 'om_headless_dialogs'));
setappdata(groot, 'probe_beat_log', {});
setappdata(groot, 'probe_beat_cut', []);
setappdata(groot, 'probe_beat_t0', []);                    % the driver's 60 s limit starts with the window
tmr = timer('Period', 0.2, 'ExecutionMode', 'fixedSpacing', 'BusyMode', 'drop', ...
    'TasksToExecute', 600, 'TimerFcn', @(~, ~) drive_beat_window());   % presses OK, then Average
start(tmr);
threw = '';
try
    feval(a.averagebeats.ButtonPushedFcn, a.averagebeats, []);
catch ME
    threw = ME.message;
end
stop(tmr); delete(tmr);
close_beat_window();                                        % in case it is still open
blog = getappdata(groot, 'probe_beat_log');
new = dialogs_since(n_dlg);
cut = getappdata(groot, 'probe_beat_cut');                  % beat starts and length the window used
avg_ok = false; detail = '';
if isempty(threw) && ~isempty(cut)
    ref = zeros(size(filtered, 1), size(filtered, 2), cut.len);   % mean of the cut beats
    for k = 1:numel(cut.starts)
        ref = ref + filtered(:, :, cut.starts(k):cut.starts(k) + cut.len - 1) / numel(cut.starts);
    end
    got = a.processed_data.image_stack{1};
    avg_ok = isequal(size(got), size(ref)) && max(abs(got(:) - ref(:))) < 1e-9 * max(abs(ref(:))) && ...
        numel(cut.starts) >= 6 && strcmp(a.history_field.Value{end}, 'Applied average beats');
    detail = sprintf('%d beats of %d frames; stack %s', numel(cut.starts), cut.len, mat2str(size(got)));
end
record('B6 Average beats: no error, one averaged beat', avg_ok && isempty(new) && ...
    ~any(startsWith(blog, 'error')), sprintf('threw "%s" | %s | window: %s | dialogs: %s', ...
    threw, detail, strjoin(blog, '; '), joined(new)));

%% B8 one beat only: Average beats says so and opens no window
sig_t = (0:249)' / 500;                                     % 0.5 s at 500 fps
one = exp(-((sig_t - 0.2) / 0.01) .^ 2);                    % a single upstroke
a.processed_data.signals{1, 1} = sig_t;                     % the ROI's time axis
a.processed_data.signals{1, a.display.normalisation + 1} = one;   % and its one-beat signal
n_b8 = numel(getappdata(groot, 'om_headless_dialogs'));
threw8 = '';
try
    feval(a.averagebeats.ButtonPushedFcn, a.averagebeats, []);
catch ME8
    threw8 = ME8.message;
end
d8 = getappdata(groot, 'om_headless_dialogs');
d8 = d8(n_b8 + 1:end);
said8 = ~isempty(d8) && strcmp(d8(end).title, 'Average beats') && contains(d8(end).message, '1 beat found');
open8 = ~isempty(findall(groot, 'Type', 'figure', 'Name', 'Beat averaging'));
close_beat_window();
record('B8 one beat: an alert says there is nothing to average, no window opens', isempty(threw8) && said8 && ~open8, ...
    sprintf('threw "%s" | window open %d | dialogs: %s', threw8, open8, joined(d8)));

%% B7 where FiltFiltM came from
w = which('FiltFiltM');
if isempty(own_copy)
    want = fullfile(repo_dir, 'third_party', 'FilterM');    % the shipped copy
else
    want = fileparts(own_copy);                             % the user's own copy wins
end
record('B7 FiltFiltM from third_party/FilterM, or the copy already on the path', ...
    ~isempty(w) && startsWith(w, want, 'IgnoreCase', ispc), sprintf('"%s", wanted under "%s"', w, want));

fprintf('\nPROBE_FILTFILT_BEAT_AVERAGING RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('%d check(s) failed.', fail);
end

    function [ok, detail] = run_filter(type, fc, order, label)
        %% Press Temporal filter with the given settings and check the result
        before = a.processed_data.image_stack{1};
        n0 = numel(getappdata(groot, 'om_headless_dialogs'));
        a.TemporalFilterType.Value = type;                  % '1' Butterworth, '2' FIR
        feval(a.TemporalFilterType.ValueChangedFcn, a.TemporalFilterType, []);
        a.cutofffrequency.Value = fc;
        a.filterorder.Value = order;
        err = '';
        try
            feval(a.temporalfilter.ButtonPushedFcn, a.temporalfilter, []);
        catch ME2
            err = ME2.message;
        end
        shown = dialogs_since(n0);                          % dialogs this press showed
        if type == '1'
            [bb, aa] = butter(order, fc / (fps / 2), 'low');   % the app's Butterworth design
        else
            bb = firpm(order, [0, fc, fc * 1.25, fps / 2] ./ (fps / 2), [1, 1, 0, 0]);   % the app's FIR design
            aa = 1;
        end
        ref = filtfilt(bb, aa, reshape(permute(before, [3 1 2]), size(before, 3), []));   % time down the columns
        ref = permute(reshape(ref, size(before, 3), size(before, 1), size(before, 2)), [2 3 1]);   % back to rows x columns x time
        got = a.processed_data.image_stack{1};
        rel = max(abs(got(:) - ref(:))) / max(abs(ref(:)));   % relative difference to filtfilt
        ok = isempty(err) && isempty(shown) && contains(a.history.current, label) && rel < 1e-9;
        detail = sprintf('threw "%s" | rel. diff to filtfilt %.3g | dialogs: %s', err, rel, joined(shown));
    end

    function drive_beat_window()
        %% Press OK, then Average, in the beat averaging window
        figs = findall(groot, 'Type', 'figure', 'Name', 'Beat averaging');
        if isempty(figs), return; end
        if isempty(getappdata(groot, 'probe_beat_t0'))
            setappdata(groot, 'probe_beat_t0', tic);        % when the window was first seen
        end
        if toc(getappdata(groot, 'probe_beat_t0')) > 60     % never finished: fail, do not hang
            beat_log('error: the window was not done within 60 s');
            close_beat_window();
            return;
        end
        try
            okb = findall(figs(1), 'Type', 'uibutton', 'Text', 'OK');
            avb = findall(figs(1), 'Type', 'uibutton', 'Text', 'Average');
            if isempty(okb) || isempty(avb), return; end    % window not complete yet
            % The window is shown before its startupFcn has run, and the
            % timer can fire in between: wait for startupFcn's last step
            % (the beat-period plot's y label), so the probe presses OK only
            % once the window is set up, as a user would see it (OK's
            % plot then relabels the axes, so this is checked before OK only)
            if strcmp(okb.Enable, 'on')
                ax = findall(figs(1), 'Type', 'axes');
                % RunningAppInstance exists only once registerApp has run
                if ~isprop(figs(1), 'RunningAppInstance') || isempty(figs(1).RunningAppInstance) || isempty(ax) || ...
                        ~any(arrayfun(@(h) strcmp(char(h.YLabel.String), 'Time (ms)'), ax))
                    return;                                 % start-up not finished: try on the next tick
                end
                feval(okb.ButtonPushedFcn, okb, []);          % accept beats first to last
                beat_log('OK pressed');
                return;
            end
            ba = figs(1).RunningAppInstance;                % the beat averaging app
            first = ba.firstbeatfield.Value; last = ba.lastbeatfield.Value;
            loc = a.averaging.beat_locations;               % beat starts the window uses
            setappdata(groot, 'probe_beat_cut', struct('starts', loc(first:last), ...
                'len', min(diff(loc(first:last)))));
            beat_log(sprintf('Average pressed (beats %d-%d)', first, last));
            feval(avb.ButtonPushedFcn, avb, []);
        catch ME3
            beat_log(['error: ' ME3.message]);
            close_beat_window();                            % otherwise the app waits for it for ever
        end
    end

    function close_beat_window()
        %% Delete a beat averaging window that is still open (ends the app's wait)
        figs = findall(groot, 'Type', 'figure', 'Name', 'Beat averaging');
        delete(figs);
    end

    function beat_log(msg)
        %% Keep what the timer did, for the probe's output
        setappdata(groot, 'probe_beat_log', [getappdata(groot, 'probe_beat_log'), {msg}]);
    end

    function new = dialogs_since(n0)
        %% The dialogs recorded after the first n0
        dd = getappdata(groot, 'om_headless_dialogs');
        if isempty(dd)
            new = struct('kind', {}, 'title', {}, 'message', {}, 'answer', {});
        else
            new = dd(n0 + 1:end);
        end
    end

    function s = joined(dlgs)
        %% One line naming each dialog's title and message
        s = strjoin(arrayfun(@(x) [x.title ': ' x.message], dlgs, 'UniformOutput', false), ' | ');
    end

    function record(name, ok, detail)
        %% Print and count one check
        if ok
            fprintf('PASS %s\n', name);
            pass = pass + 1;
        else
            fprintf('FAIL %s: %s\n', name, detail);
            fail = fail + 1;
        end
    end
end
