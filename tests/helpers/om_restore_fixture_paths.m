function [golden_root, scratch] = om_restore_fixture_paths(probe_name)
%% Golden run and scratch folder for the probes that restore the golden run
% Collin Snitchler
% 14.10.2026
% The golden run is test data that lives on the tester's machine, so its
% location comes from the environment variable OM_TEST_RESTORE_GOLDEN_ROOT
% (the folder holding subset.matom), else from the untracked copy under
% tests/fixtures/reproj-recon/staging/r1_4. When neither holds the golden
% run, golden_root is '' and a SKIP line naming the variable is printed; the
% probe then returns without checking anything. Scratch copies go in a
% folder under tempdir named after the probe, never next to the fixture.
golden_run = '20260909T110043_d091bb44';
golden_root = om_test_getenv('OM_TEST_RESTORE_GOLDEN_ROOT');
if isempty(golden_root)
    repo_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    golden_root = fullfile(repo_dir, 'tests', 'fixtures', 'reproj-recon', 'staging', 'r1_4');
end
if ~isfolder(fullfile(golden_root, 'subset.matom', 'reconstruction', 'runs', golden_run))
    fprintf(['SKIP %s: the golden run %s was not found. Set OM_TEST_RESTORE_GOLDEN_ROOT ' ...
        'to the folder holding subset.matom.\n'], probe_name, golden_run);
    golden_root = '';
end
scratch = fullfile(tempdir, ['om_test_' probe_name]);
end
