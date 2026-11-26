function run_probes_worker(jobs, log_dir)
%% Runs probes one after another in this MATLAB, with a full reset between them
% Collin Snitchler
% 26.11.2026
% The MATLAB side of tests/run_probes.py, which starts one MATLAB per
% worker and gives each one probe at a time. It can also be used alone:
%   run_probes_worker({'probe_a', 'probe_b'}, '<log folder>')
% runs the probes here in turn and writes <log folder>/<name>.log for
% each. With one
% argument, run_probes_worker('<queue folder>'), it serves the jobs that
% run_probes.py writes to <queue folder>/next.txt until it gets STOP.
%
% Each probe gets the state a newly started MATLAB would give it, and the
% state is put back after it, also after an error:
%   - timers stopped and deleted; every figure closed (force) and deleted;
%   - files the probe left open closed; scratch copies of tests/helpers/
%     om_redo_copy.m that were still open when the probe ended removed;
%   - the path and the current folder as at start (this removes the test
%     stand-ins of tests/helpers/headless that the probes add);
%   - environment variables the probe set, changed or removed;
%   - the root object's appdata (the headless queue, recorded dialogs and
%     other probe keys) and its factory defaults (DefaultFigure...);
%   - MATLAB preferences (setpref), the warning states, the random number
%     generator and the number of computational threads;
%   - persistent variables and class definitions (clear classes; a class
%     whose deleted objects are still referenced somewhere stays loaded,
%     which the probe's log notes, and clear functions clears the rest).
% After the reset the state is compared with the start once more. What is
% still different is printed as RESET_INCOMPLETE and run_probes.py starts
% a new MATLAB for the next probe.
% Needs OM_APP_HEADLESS=1 and MATLAB_PREFDIR, as every probe.
tests_dir = fileparts(mfilename('fullpath'));
repo = fileparts(tests_dir);
start = snapshot();                                % the state every probe starts from
if iscell(jobs) || isstring(jobs)
    jobs = cellstr(jobs);
    if ~isfolder(log_dir), mkdir(log_dir); end
    for k = 1:numel(jobs)
        r = run_one(jobs{k}, fullfile(log_dir, [jobs{k} '.log']), repo, tests_dir, start);
        fprintf('%s %s %.0f s%s\n', upper(r.status), jobs{k}, r.seconds, ternary(r.recycle, ' (state not reset)', ''));
    end
    return;
end
serve(char(jobs), repo, tests_dir, start);
end


function serve(queue, repo, tests_dir, start)
% The job file holds "<seq><tab><job><tab><log file>" or STOP. The result
% goes to result_<seq>.json, written under another name and then renamed,
% so run_probes.py never reads half a file.
next = fullfile(queue, 'next.txt');
while true
    if ~isfile(next)
        pause(0.2);
        continue;
    end
    line = strtrim(fileread(next));
    delete(next);
    if strcmp(line, 'STOP')
        return;
    end
    f = strsplit(line, sprintf('\t'));
    r = run_one(f{2}, f{3}, repo, tests_dir, start);
    tmp = fullfile(queue, ['result_' f{1} '.tmp']);
    fid = fopen(tmp, 'w', 'n', 'UTF-8');
    fwrite(fid, jsonencode(r), 'char');
    fclose(fid);
    movefile(tmp, fullfile(queue, ['result_' f{1} '.json']));
    if r.recycle
        return;                                    % run_probes.py starts a new MATLAB
    end
end
end


function r = run_one(job, log_file, repo, tests_dir, start)
% One probe with its output in log_file; never lets an error out
name = job;
r = struct('job', job, 'status', 'ok', 'seconds', 0, 'error', '', 'recycle', false, 'reset', '');
if isfile(log_file), delete(log_file); end
diary(log_file);
t0 = tic;
try
    % The folders the one-MATLAB-per-probe runner put on the path
    addpath(repo); addpath(tests_dir); addpath(fullfile(tests_dir, 'helpers'));
    addpath(fullfile(tests_dir, 'helpers', 'headless'));
    src = fullfile(tests_dir, [name '.m']);
    if isfile(src) && ~isempty(regexp(fileread(src), '^classdef', 'once', 'lineanchors'))
        % A matlab.unittest class: run it and print a RESULT line, as the old runner
        t = runtests(name);
        fprintf('RESULT: %d passed, %d failed, %d incomplete\n', sum([t.Passed]), sum([t.Failed]), sum([t.Incomplete]));
        assert(~any([t.Failed]), 'run_probes_worker:TestsFailed', '%d test(s) failed.', sum([t.Failed]));
    else
        feval(name);
    end
catch ME
    r.status = 'error';
    r.error = ME.message;
    fprintf('%s\n', ME.getReport('extended', 'hyperlinks', 'off'));
end
r.seconds = toc(t0);
try
    notes = reset_to(start);
    left = differences(start, snapshot());
catch ME
    notes = {};
    left = {['the reset itself failed: ' ME.message]};
end
if ~isempty(notes)
    r.reset = strjoin(notes, '; ');
    fprintf('RESET: %s\n', r.reset);
end
if ~isempty(left)
    r.recycle = true;
    fprintf('RESET_INCOMPLETE: %s\n', strjoin(left, '; '));
end
if ~strcmp(get(0, 'Diary'), 'on'), diary(log_file); end   % a probe may have turned it off
fprintf('PROBE_END %s %s %.0f s\n', job, r.status, r.seconds);
diary('off');
end


function s = snapshot()
% Everything reset_to puts back
s.path = path;
s.pwd = pwd;
s.env = getenv();                                  % a dictionary of every variable (R2023a and later)
s.prefs = prefs_now();
s.defaults = get(groot, 'default');
s.appdata = getappdata(groot);
s.warning = warning;
s.rng = rng;
s.threads = maxNumCompThreads;
s.timers = timerfindall;
s.files = openedFiles();
s.n_figures = numel(findall(groot, 'Type', 'figure'));
end


function notes = reset_to(s)
% Put back what a probe changed; the notes say what there was to do
notes = {};
t = timerfindall;
if ~isempty(t) && ~isempty(s.timers)
    t = t(~arrayfun(@(x) any(x == s.timers), t));  % only the probe's timers
end
if ~isempty(t)
    stop(t);
    delete(t);
    notes{end + 1} = sprintf('%d timer(s) deleted', numel(t));
end
figs = findall(groot, 'Type', 'figure');           % hidden ones too (apps, uifigures)
if ~isempty(figs)
    % An App Designer app outlives its deleted window (and then its class
    % cannot be cleared): delete the apps first, as the probes' own clean-up does
    for k = 1:numel(figs)
        try
            app = figs(k).RunningAppInstance;      % hidden property of an app's window
            if ~isempty(app) && isvalid(app), delete(app); end
        catch
        end
    end
    figs = figs(isgraphics(figs));
    close(figs, 'force');                          % without asking their CloseRequestFcn
    delete(figs(isgraphics(figs)));                % what close left
    notes{end + 1} = sprintf('%d figure(s) closed', numel(figs));
end
% Scratch copies that om_redo_copy could not remove while the probe's app
% still had a file open in them
copies = getappdata(groot, 'om_redo_copies');
if ~iscell(copies), copies = {}; end
copies = copies(cellfun(@isfolder, copies));
for k = 1:numel(copies)
    try
        rmdir(copies{k}, 's');
        notes{end + 1} = ['scratch copy removed: ' copies{k}]; %#ok<AGROW>
    catch ME
        notes{end + 1} = sprintf('scratch copy %s not removed: %s', copies{k}, ME.message); %#ok<AGROW>
    end
end
open = setdiff(openedFiles(), s.files);
for k = 1:numel(open)
    fclose(open(k));
end
if ~isempty(open), notes{end + 1} = sprintf('%d open file(s) closed', numel(open)); end
if ~strcmp(path, s.path)
    path(s.path);
    notes{end + 1} = 'path';
end
if ~strcmp(pwd, s.pwd)
    cd(s.pwd);
    notes{end + 1} = 'current folder';
end
notes = [notes, reset_env(s.env)];
now_appdata = getappdata(groot);
names = fieldnames(now_appdata);
for k = 1:numel(names)
    if ~isfield(s.appdata, names{k})
        rmappdata(groot, names{k});
    end
end
names = fieldnames(s.appdata);
for k = 1:numel(names)
    setappdata(groot, names{k}, s.appdata.(names{k}));
end
if ~isequal(fieldnames(now_appdata), fieldnames(s.appdata))
    notes{end + 1} = 'root appdata';
end
now_defaults = get(groot, 'default');
names = fieldnames(now_defaults);
for k = 1:numel(names)
    if ~isfield(s.defaults, names{k})
        set(groot, names{k}, 'remove');            % back to the factory value
        notes{end + 1} = ['root ' names{k}]; %#ok<AGROW>
    elseif ~isequal(now_defaults.(names{k}), s.defaults.(names{k}))
        set(groot, names{k}, s.defaults.(names{k}));
        notes{end + 1} = ['root ' names{k}]; %#ok<AGROW>
    end
end
if ~isequal(prefs_now(), s.prefs)
    reset_prefs(s.prefs);
    notes{end + 1} = 'preferences';
end
warning(s.warning);
rng(s.rng);
maxNumCompThreads(s.threads);
format;                                            % the default display format
% Persistent variables (rabbit_memo, the stand-ins' cache) and class
% definitions. The probe's objects are gone with its figures and timers;
% one that is not gives a warning, kept in the notes
msg = clear_classes();
if ~isempty(msg), notes{end + 1} = ['clear classes: ' msg]; end
lastwarn('');
end


function msg = clear_classes()
% In a function of its own: clear classes also clears the variables of the
% workspace it is called from
lastwarn('');
clear('classes'); %#ok<CLCLS>
msg = lastwarn;
if ~isempty(msg)
    % A deleted app object still referenced (its window and timers are
    % gone) keeps its class loaded; the functions' persistent variables
    % are cleared all the same
    clear('functions'); %#ok<CLFUNC>
end
end


function notes = reset_env(env0)
% Variables the probe added are removed; changed or removed ones put back.
% Not touched: Windows' own '=C:' variables, and QT_QPA_PLATFORM, which
% MATLAB sets itself the first time some of its graphics start (a new
% MATLAB has it from then on too)
notes = {};
now_env = getenv();
k_now = keys(now_env);
for k = 1:numel(k_now)
    if ~isKey(env0, k_now(k)) && ~matlab_own(k_now(k))
        unsetenv(k_now(k));
        notes{end + 1} = sprintf('env %s removed', k_now(k)); %#ok<AGROW>
    end
end
k0 = keys(env0);
for k = 1:numel(k0)
    if (~isKey(now_env, k0(k)) || ~strcmp(now_env(k0(k)), env0(k0(k)))) && ~matlab_own(k0(k))
        setenv(k0(k), env0(k0(k)));
        notes{end + 1} = sprintf('env %s restored', k0(k)); %#ok<AGROW>
    end
end
end


function p = prefs_now()
% Every preference group, in name order; [] when there is none (getpref
% gives [] before the first setpref and an empty struct after rmpref)
p = getpref();
if ~isstruct(p) || isempty(fieldnames(p))
    p = [];
else
    p = orderfields(p);
end
end


function reset_prefs(p0)
% Every group removed, then the start's groups written back
now_p = prefs_now();
if isstruct(now_p)
    groups = fieldnames(now_p);
    for k = 1:numel(groups)
        rmpref(groups{k});
    end
end
if isstruct(p0)
    groups = fieldnames(p0);
    for k = 1:numel(groups)
        names = fieldnames(p0.(groups{k}));
        for j = 1:numel(names)
            setpref(groups{k}, names{j}, p0.(groups{k}).(names{j}));
        end
    end
end
end


function left = differences(s, now_s)
% What the reset could not put back
left = {};
if now_s.n_figures > s.n_figures, left{end + 1} = sprintf('%d figure(s)', now_s.n_figures - s.n_figures); end
if numel(now_s.timers) > numel(s.timers), left{end + 1} = 'timers'; end
if ~strcmp(now_s.path, s.path), left{end + 1} = 'path'; end
if ~strcmp(now_s.pwd, s.pwd), left{end + 1} = 'current folder'; end
if ~same_env(now_s.env, s.env), left{end + 1} = 'environment'; end
if ~isequal(now_s.prefs, s.prefs), left{end + 1} = 'preferences'; end
if ~isequal(fieldnames(now_s.appdata), fieldnames(s.appdata)), left{end + 1} = 'root appdata'; end
if ~isequal(now_s.defaults, s.defaults), left{end + 1} = 'root defaults'; end
if ~isempty(setdiff(now_s.files, s.files)), left{end + 1} = 'open files'; end
end


function tf = matlab_own(name)
% Variables the reset leaves alone (see reset_env)
tf = startsWith(name, '=') || strcmpi(name, 'QT_QPA_PLATFORM');
end


function same = same_env(a, b)
% The two dictionaries hold the same variables, those of matlab_own aside
ka = keys(a); ka = ka(~arrayfun(@matlab_own, ka));
kb = keys(b); kb = kb(~arrayfun(@matlab_own, kb));
same = isequal(sort(ka), sort(kb)) && all(arrayfun(@(k) strcmp(a(k), b(k)), ka));
end


function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end
