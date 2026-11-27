function smoke_manifest_empty_runs()
%SMOKE_MANIFEST_EMPTY_RUNS Regression for JSON "runs": [] state.
% jsondecode represents an empty JSON array as a double empty array; the
% backend must normalise it before appending a run struct.
root = fullfile(tempdir, ['cd2_manifest_empty_runs_' datestr(now, 'yyyymmddHHMMSSFFF')]);
cleanup = onCleanup(@() cleanup_root(root)); %#ok<NASGU>
recon_dir = fullfile(root, 'dataset.matom', 'reconstruction');
mkdir(recon_dir);
state_file = fullfile(recon_dir, 'tab-state.json');

fid = fopen(state_file, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Could not create the regression state file.');
fprintf(fid, '{"state_schema_version":1,"recipe_version":1,"runs":[]}');
fclose(fid);

tab = rabbit_reconstruction_tab();
[ok, err] = tab.load_state(root, 'dataset');
assert(ok, 'load_state failed: %s', err);
[ok, err] = tab.record_run('run-empty-runs', 'COMPLETED');
assert(ok, 'record_run failed: %s', err);
state = tab.get_state();
assert(isstruct(state.runs) && numel(state.runs) == 1, ...
    'Expected one normalised run struct after record_run.');
assert(strcmp(state.runs(1).id, 'run-empty-runs'), 'Run id was not recorded.');
fprintf('smoke_manifest_empty_runs PASS\n');
end

function cleanup_root(root)
if exist(root, 'dir')
    rmdir(root, 's');
end
end
