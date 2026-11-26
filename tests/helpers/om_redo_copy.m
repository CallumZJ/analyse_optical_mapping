function [root, cleanup] = om_redo_copy(probe_name, ds_var, stem, run_id, mode)
%% A scratch copy of a test dataset under tempdir, or the shared copy itself for a probe that only reads
% Collin Snitchler
% 26.11.2026
% ds_var names the variable that holds the dataset folder (OM_REDO_DS or
% OM_TEST_SPREAD_DS); that folder is itself a copy of <stem>.matom with a COMPLETED
% run, made for the tests. When the variables are not set, or the run is
% not there, a SKIP line naming them is printed and root is ''.
%   mode 'copy' (the default): <stem>.matom is copied to a new folder
%       under tempdir, which is removed when the caller's cleanup variable
%       goes away, also after an error or a half-finished copy.
%   mode 'read': root is the given folder itself, for a probe that only
%       reads it, so there is no copy to make. When cleanup goes away the
%       run's files are compared with a listing taken now; a file added,
%       removed or changed is named in a SHARED_COPY_CHANGED line and a
%       warning (the probe should have used 'copy').
% Usage:
%   [root, cleanup] = om_redo_copy('probe_x', 'OM_REDO_DS', stem, run_id); %#ok<ASGLU>
%   if isempty(root), return; end                      % SKIP printed
if nargin < 5, mode = 'copy'; end
root = '';
cleanup = [];
src = getenv(ds_var);
if isempty(src) || isempty(stem) || isempty(run_id) || ...
        ~isfolder(fullfile(src, [stem '.matom'], 'reconstruction', 'runs', run_id))
    fprintf(['SKIP %s: set %s, OM_REDO_STEM and OM_REDO_RUN to a copy of ' ...
        '<stem>.matom with a COMPLETED run.\n'], probe_name, ds_var);
    return;
end
switch mode
    case 'read'
        root = src;
        before = listing(fullfile(src, [stem '.matom']));
        cleanup = onCleanup(@() check_unchanged(probe_name, fullfile(src, [stem '.matom']), before));
    case 'copy'
        root = [tempname '_' probe_name];              % unique folder under tempdir, named after the probe
        cleanup = onCleanup(@() remove_scratch(root)); % before the copy, so a partial copy goes too
        % Kept for tests/run_probes_worker.m, which removes a copy that
        % could not be removed here (a file still open) after the probe's
        % windows are closed
        setappdata(groot, 'om_redo_copies', [getappdata(groot, 'om_redo_copies'), {root}]);
        mkdir(root);
        copyfile(fullfile(src, [stem '.matom']), fullfile(root, [stem '.matom']));
    otherwise
        error('om_redo_copy:Mode', 'Unknown mode %s (copy or read).', mode);
end
end


function remove_scratch(p)
if ~isfolder(p), return; end
try
    rmdir(p, 's');
catch ME
    warning('om_redo_copy:Cleanup', 'Could not remove %s: %s', p, ME.message);
end
end


function L = listing(p)
% Every file under p: relative name, size and modification time
d = dir(fullfile(p, '**', '*'));
d = d(~[d.isdir]);
names = strcat({d.folder}, filesep, {d.name});
L = struct('name', {strrep(names, [p filesep], '')}, 'bytes', [d.bytes], 'datenum', [d.datenum]);
end


function check_unchanged(probe_name, p, before)
% The shared copy is as it was when the probe started
now_l = listing(p);
gone = setdiff(before.name, now_l.name);
added = setdiff(now_l.name, before.name);
[common, ib, ic] = intersect(before.name, now_l.name);
changed = common(before.bytes(ib) ~= now_l.bytes(ic) | before.datenum(ib) ~= now_l.datenum(ic));
diffs = [strcat({'added '}, added(:)'), strcat({'removed '}, gone(:)'), strcat({'changed '}, changed(:)')];
if isempty(diffs), return; end
msg = sprintf('%s changed the shared copy %s: %s', probe_name, p, strjoin(diffs(1:min(end, 20)), ', '));
fprintf('SHARED_COPY_CHANGED %s\n', msg);
warning('om_redo_copy:SharedCopyChanged', '%s', msg);
end
