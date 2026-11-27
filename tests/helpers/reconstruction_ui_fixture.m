function report = reconstruction_ui_fixture(ui)
%% Point-edit fixture for a rabbit_reconstruction_ui object (probe_point_edit_tool_panel)
% Collin Snitchler
% 26.11.2026
% report = reconstruction_ui_fixture(app.recon) runs test_edit_fixture_check
% below: it exercises the copy-on-write edit state, preview tokens, hashes,
% containment and read-back of the tab on synthetic runs under tempname,
% without touching a real dataset or running a reconstruction algorithm.
% report has one logical field per invariant (probe_point_edit_tool_panel P9
% lists them).
% It uses only public members of rabbit_reconstruction_ui, and its three
% hidden test properties: test_edit_fixture_mode (set while the fixture
% runs), test_edit_fixture_noop and test_edit_fixture_manifest_fail (force the no-op and
% the manifest-failure paths of reconstruction_edit_fixture_apply).
% The app keeps its rabbit_reconstruction_tab private, so the read-back
% helpers make a fresh one: verify_vis_readback, write_intensity_vis and
% load_visualisation_ply read only their arguments, so the result is the
% same.
report = test_edit_fixture_check(ui);
end

function [report] = test_edit_fixture_check(obj)
    %TEST_EDIT_FIXTURE_CHECK Deterministic fixture hook. It exercises state,
    %tokens, hashes, containment and read-back without touching any
    %real dataset or invoking a reconstruction algorithm.
    fields = {'no_run_controls_disabled', 'preview_preserves_source', ...
        'preview_preserves_manifest', 'preview_token_invalidates_parameter', ...
        'preview_token_invalidates_run', 'preview_token_invalidates_source', ...
        'apply_requires_matching_preview', 'apply_readback_verified', ...
        'reset_retains_applied_output', 'unknown_commit_reported', ...
        'selection_is_run_bound', 'destination_is_contained', ...
        'input_parser_non_evaluating', 'inadmissible_ply_rejected', ...
        'unsupported_rgb_type_rejected', 'invalid_face_topology_rejected', ...
        'vis_regenerated_readback', 'vis_missing_rejected', ...
        'vis_malformed_rejected', 'vis_truncated_rejected', ...
        'vis_trailing_rejected', 'copied_manifest_rebased', ...
        'selection_cancel_no_write', 'view_identity_invalidates', 'no_op_rejected', ...
        'legacy_record_normalized'};
    report = struct();
    for k = 1:numel(fields), report.(fields{k}) = false; end
    root = tempname;
    runs_root = fullfile(root, 'dataset.matom', 'reconstruction', 'runs');
    mkdir(runs_root);
    cleaner = onCleanup(@() reconstruction_edit_fixture_cleanup(obj, root)); %#ok<NASGU>
    obj.test_edit_fixture_mode = true;
    obj.reconstruction_edit_reset_state();
    report.no_run_controls_disabled = isempty(obj.CopyOnWritePending) && ...
        strcmp(obj.CopyOnWriteState.status, 'No run selected');
    run_a = reconstruction_edit_fixture_make_run(obj, runs_root, 'run-A');
    run_b = reconstruction_edit_fixture_make_run(obj, runs_root, 'run-B');
    report.legacy_record_normalized = reconstruction_edit_fixture_legacy_records(obj, run_a);
    [preview_ok, source_before, manifest_before] = reconstruction_edit_fixture_preview(obj, run_a, 'intensity', struct('mode', 'below', 'threshold', 128));
    [~, source_after] = obj.reconstruction_edit_hash_file(fullfile(run_a, 'outputs', 'fused-geometric.ply'));
    manifest_after = obj.reconstruction_edit_manifest_hash(run_a);
    report.preview_preserves_source = preview_ok && strcmp(source_before, source_after);
    report.preview_preserves_manifest = preview_ok && strcmp(manifest_before, manifest_after);
    % Parameter edit invalidation.
    reconstruction_edit_fixture_invalidate(obj, 'intensity');
    report.preview_token_invalidates_parameter = ~reconstruction_edit_fixture_pending_valid(obj, 'intensity');
    % Run switching invalidation.
    reconstruction_edit_fixture_preview(obj, run_a, 'intensity', struct('mode', 'below', 'threshold', 128));
    obj.CopyOnWriteState.selected_run_id = 'run-B';
    reconstruction_edit_fixture_invalidate_all(obj);
    report.preview_token_invalidates_run = ~reconstruction_edit_fixture_pending_valid(obj, 'intensity');
    % Source replacement invalidation.
    reconstruction_edit_fixture_preview(obj, run_a, 'intensity', struct('mode', 'below', 'threshold', 128));
    fid = fopen(fullfile(run_a, 'outputs', 'fused-geometric.ply'), 'a', 'n', 'UTF-8');
    fprintf(fid, '\ncomment replacement\n'); fclose(fid);
    reconstruction_edit_fixture_invalidate_all(obj);
    report.preview_token_invalidates_source = ~reconstruction_edit_fixture_pending_valid(obj, 'intensity');
    % Direct Apply without Preview.
    obj.reconstruction_edit_reset_state();
    [direct_ok, ~] = reconstruction_edit_fixture_apply(obj, run_a, 'intensity', struct('mode', 'below', 'threshold', 128));
    report.apply_requires_matching_preview = ~direct_ok;
    % One successful Preview -> Apply -> Reset per operation.
    ops = {'touchup', 'intensity', 'area', 'smooth'};
    axes_area = struct('id', 'axes:area:first', 'units', 'pixels', ...
        'position', [0 0 100 100]);
    axes_smooth = struct('id', 'axes:smooth:first', 'units', 'pixels', ...
        'position', [0 0 120 120]);
    params = {struct('box', [0 1 0 1 0 1]), ...
        struct('mode', 'below', 'threshold', 128), ...
        struct('shape', 'rect', 'rect', [0 0 1 1], ...
            'camera', struct('cp', [1 1 1], 'ct', [0 0 0], 'cuv', [0 0 1]), ...
            'axes_identity', axes_area, 'projection_identity', 'pinhole-normalized-camera-v2-screen-bound'), ...
        struct('center', [0 0 0], 'radius_px', 10, 'iterations', 2, 'strength', 0.5, ...
            'camera', struct('cp', [1 1 1], 'ct', [0 0 0], 'cuv', [0 0 1]), ...
            'axes_identity', axes_smooth, 'axpos', [0 0 120 120], ...
            'projection_identity', 'pinhole-normalized-camera-v2-screen-bound')};
    % Successful and repeat Preview must publish the exact captured
    % Area/Smoothing camera, axes and projection identity into the
    % shared state and summary. Invalidation must remove it.
    reconstruction_edit_fixture_preview(obj, run_a, 'area', params{3});
    area_first = reconstruction_edit_fixture_shared_identity_matches(obj, 'area', params{3});
    params{3}.camera.cp = [2 2 2];
    params{3}.axes_identity.id = 'axes:area:repeat';
    reconstruction_edit_fixture_preview(obj, run_a, 'area', params{3});
    area_repeat = reconstruction_edit_fixture_shared_identity_matches(obj, 'area', params{3});
    reconstruction_edit_fixture_preview(obj, run_a, 'smooth', params{4});
    smooth_first = reconstruction_edit_fixture_shared_identity_matches(obj, 'smooth', params{4});
    params{4}.camera.cp = [3 3 3];
    params{4}.axes_identity.id = 'axes:smooth:repeat';
    reconstruction_edit_fixture_preview(obj, run_a, 'smooth', params{4});
    smooth_repeat = reconstruction_edit_fixture_shared_identity_matches(obj, 'smooth', params{4});
    % Reset clears the operation's shared identity.
    obj.reconstruction_edit_reset_operation('area');
    area_reset = reconstruction_edit_fixture_shared_identity_clear(obj, 'area');
    % Run switching invalidates and clears a previously captured view.
    reconstruction_edit_fixture_preview(obj, run_a, 'area', params{3});
    switched_sources = obj.CopyOnWriteState.sources;
    obj.reconstruction_edit_invalidate_changed(switched_sources, 'run-B');
    run_switch_clear = reconstruction_edit_fixture_shared_identity_clear(obj, 'area');
    % Active-manifest digest drift follows the same production
    % invalidation path and cannot leave the old identity visible.
    reconstruction_edit_fixture_preview(obj, run_a, 'area', params{3});
    drift_sources = obj.CopyOnWriteState.sources;
    drift_sources.area.admissible = true;
    drift_sources.area.run_dir = run_a;
    drift_sources.area.path = fullfile(run_a, 'outputs', 'fused-geometric.ply');
    [~, drift_sources.area.sha256] = obj.reconstruction_edit_hash_file(drift_sources.area.path);
    fid = fopen(fullfile(run_a, 'manifest.json'), 'a', 'n', 'UTF-8');
    fprintf(fid, ' '); fclose(fid);
    obj.reconstruction_edit_invalidate_changed(drift_sources, 'run-A');
    digest_drift_clear = reconstruction_edit_fixture_shared_identity_clear(obj, 'area');
    % A failed call through the real record_preview boundary also
    % invalidates the formerly successful identity.
    reconstruction_edit_fixture_preview(obj, run_a, 'area', params{3});
    obj.reconstruction_edit_record_preview('area', 'run-A', params{3}, struct());
    failed_preview_clear = reconstruction_edit_fixture_shared_identity_clear(obj, 'area');
    % Cancellation must invalidate the candidate without writing and
    % clear the shared identity.
    reconstruction_edit_fixture_preview(obj, run_a, 'area', params{3});
    cancel_before = obj.reconstruction_edit_output_snapshot(run_a);
    reconstruction_edit_fixture_cancel(obj, 'area');
    cancel_after = obj.reconstruction_edit_output_snapshot(run_a);
    report.selection_cancel_no_write = ~reconstruction_edit_fixture_pending_valid(obj, 'area') && ...
        obj.reconstruction_edit_same_snapshot(cancel_before, cancel_after) && ...
        reconstruction_edit_fixture_shared_identity_clear(obj, 'area');
    % Camera/axes identity changes invalidate a pending selection and
    % cannot leave the prior captured identity in the shared summary.
    reconstruction_edit_fixture_view_changed(obj, 'smooth');
    report.view_identity_invalidates = area_first && area_repeat && ...
        smooth_first && smooth_repeat && area_reset && run_switch_clear && ...
        digest_drift_clear && failed_preview_clear && ...
        ~reconstruction_edit_fixture_pending_valid(obj, 'smooth') && ...
        reconstruction_edit_fixture_shared_identity_clear(obj, 'smooth');
    % No-op Apply is rejected before any output is written.
    obj.test_edit_fixture_noop = true;
    reconstruction_edit_fixture_preview(obj, run_a, 'area', params{3});
    noop_before = obj.reconstruction_edit_output_snapshot(run_a);
    [noop_ok, ~] = reconstruction_edit_fixture_apply(obj, run_a, 'area', params{3});
    noop_after = obj.reconstruction_edit_output_snapshot(run_a);
    report.no_op_rejected = ~noop_ok && obj.reconstruction_edit_same_snapshot(noop_before, noop_after);
    obj.test_edit_fixture_noop = false;
    apply_ok = true; contained = true; retained = true;
    for k = 1:numel(ops)
        reconstruction_edit_fixture_preview(obj, run_a, ops{k}, params{k});
        [aok, ~] = reconstruction_edit_fixture_apply(obj, run_a, ops{k}, params{k});
        apply_ok = apply_ok && aok;
        if aok
            output = obj.reconstruction_edit_output_text(ops{k});
            output_path = obj.CopyOnWriteApplied(end).output_path;
            positive_containment = obj.reconstruction_edit_path_in_run(output_path, run_a);
            negative_containment = ~obj.reconstruction_edit_path_in_run( ...
                fullfile(root, 'run-A-escape', 'outputs', 'derived'), run_a) && ...
                ~obj.reconstruction_edit_path_in_run( ...
                fullfile(run_a, '..', 'run-B', 'outputs', 'derived'), run_a);
            contained = contained && positive_containment && negative_containment;
            before_reset = output;
            obj.reconstruction_edit_reset_operation(ops{k});
            retained = retained && strcmp(before_reset, obj.reconstruction_edit_output_text(ops{k}));
        end
    end
    report.apply_readback_verified = apply_ok;
    report.destination_is_contained = contained;
    report.reset_retains_applied_output = retained;
    % Selection/run binding is enforced by the token guard.
    reconstruction_edit_fixture_preview(obj, run_a, 'area', params{3});
    obj.CopyOnWriteState.selected_run_id = 'run-B';
    [bound_ok, ~] = reconstruction_edit_fixture_apply(obj, run_b, 'area', params{3});
    report.selection_is_run_bound = ~bound_ok;
    % Output written but manifest write fails: unknown, not Failed.
    reconstruction_edit_fixture_preview(obj, run_a, 'smooth', params{4});
    obj.test_edit_fixture_manifest_fail = true;
    [~, ~] = reconstruction_edit_fixture_apply(obj, run_a, 'smooth', params{4});
    report.unknown_commit_reported = contains(lower(obj.CopyOnWriteState.status), 'not confirmed');
    obj.test_edit_fixture_manifest_fail = false;
    % Parser must reject evaluation syntax and accept a valid box.
    [bad_ok, ~, ~] = obj.reconstruction_edit_parse_box('1+1 2 0 1 0 1');
    [good_ok, ~, ~] = obj.reconstruction_edit_parse_box('0 1 0 1 0 1');
    report.input_parser_non_evaluating = ~bad_ok && good_ok;
    % Malformed/no-RGB point source is not admissible for intensity.
    bad = fullfile(run_a, 'outputs', 'fused-geometric.ply');
    fid = fopen(bad, 'w', 'n', 'UTF-8');
    fprintf(fid, 'not a ply\n'); fclose(fid);
    d = reconstruction_edit_fixture_descriptor(obj, run_a, 'intensity');
    report.inadmissible_ply_rejected = ~d.admissible;
    float_rgb = fullfile(root, 'float-rgb.ply');
    reconstruction_edit_fixture_write_ply(obj, float_rgb, false, true, 'float_rgb');
    [float_ok, ~, ~] = reconstruction_edit_fixture_load_ply(obj, float_rgb);
    report.unsupported_rgb_type_rejected = ~float_ok;
    bad_faces = fullfile(root, 'bad-faces.ply');
    reconstruction_edit_fixture_write_ply(obj, bad_faces, true, true, 'out_of_range_face');
    [bad_face_ok, ~, bad_face_info] = reconstruction_edit_fixture_load_ply(obj, bad_faces);
    bad_face_admissible = bad_face_ok && bad_face_info.has_faces && ...
        all(double(bad_face_info.faces(:)) >= 1) && ...
        all(double(bad_face_info.faces(:)) <= double(bad_face_info.n_vertices)) && ...
        all(double(bad_face_info.faces(:)) == floor(double(bad_face_info.faces(:))));
    report.invalid_face_topology_rejected = ~bad_face_admissible;
    vis_root = fullfile(root, 'vis-cases');
    mkdir(vis_root);
    % Valid ASCII and legacy-binary inputs traverse the production
    % write_intensity_vis boundary and production semantic read-back.
    valid_vis = fullfile(vis_root, 'valid-ascii.vis');
    reconstruction_edit_fixture_write_vis(obj, valid_vis, 4, 'ascii', 'valid');
    regenerated_vis = fullfile(vis_root, 'regenerated-ascii.vis');
    [ascii_write_ok, ~, ~] = reconstruction_edit_fixture_regenerate_vis(obj, ...
        regenerated_vis, valid_vis, [1 3], 4);
    [ascii_read_ok, ~, ~] = reconstruction_edit_fixture_verify_vis_readback(obj, regenerated_vis, 2);
    valid_binary = fullfile(vis_root, 'valid-binary.vis');
    reconstruction_edit_fixture_write_vis(obj, valid_binary, 4, 'binary', 'valid');
    regenerated_binary = fullfile(vis_root, 'regenerated-binary.vis');
    [binary_write_ok, ~, ~] = reconstruction_edit_fixture_regenerate_vis(obj, ...
        regenerated_binary, valid_binary, [2 4], 4);
    [binary_read_ok, ~, ~] = reconstruction_edit_fixture_verify_vis_readback(obj, regenerated_binary, 2);
    missing_vis = fullfile(vis_root, 'missing.vis');
    [missing_vis_ok, ~, ~] = reconstruction_edit_fixture_verify_vis_readback(obj, missing_vis, 4);

    source_cases = {'malformed', 'truncated', 'trailing', 'count_mismatch'};
    ascii_source_rejected = false(1, numel(source_cases));
    binary_source_rejected = false(1, numel(source_cases));
    for k = 1:numel(source_cases)
        variant = source_cases{k};
        source = fullfile(vis_root, ['source-ascii-' variant '.vis']);
        output = fullfile(vis_root, ['output-ascii-' variant '.vis']);
        reconstruction_edit_fixture_write_vis(obj, source, 4, 'ascii', variant);
        [case_ok, ~, ~] = reconstruction_edit_fixture_regenerate_vis(obj, output, source, [1 3], 4);
        ascii_source_rejected(k) = ~case_ok && exist(output, 'file') ~= 2;
        source = fullfile(vis_root, ['source-binary-' variant '.vis']);
        output = fullfile(vis_root, ['output-binary-' variant '.vis']);
        reconstruction_edit_fixture_write_vis(obj, source, 4, 'binary', variant);
        [case_ok, ~, ~] = reconstruction_edit_fixture_regenerate_vis(obj, output, source, [1 3], 4);
        binary_source_rejected(k) = ~case_ok && exist(output, 'file') ~= 2;
    end

    generated_cases = {'malformed', 'truncated', 'trailing', 'count_mismatch'};
    ascii_generated_rejected = false(1, numel(generated_cases));
    binary_generated_rejected = false(1, numel(generated_cases));
    for k = 1:numel(generated_cases)
        variant = generated_cases{k};
        generated = fullfile(vis_root, ['generated-ascii-' variant '.vis']);
        reconstruction_edit_fixture_write_vis(obj, generated, 4, 'ascii', variant);
        [case_ok, ~, ~] = reconstruction_edit_fixture_verify_vis_readback(obj, generated, 4);
        ascii_generated_rejected(k) = ~case_ok;
        generated = fullfile(vis_root, ['generated-binary-' variant '.vis']);
        reconstruction_edit_fixture_write_vis(obj, generated, 4, 'binary', variant);
        [case_ok, ~, ~] = reconstruction_edit_fixture_verify_vis_readback(obj, generated, 4);
        binary_generated_rejected(k) = ~case_ok;
    end
    report.vis_regenerated_readback = ascii_write_ok && ascii_read_ok && ...
        binary_write_ok && binary_read_ok;
    report.vis_missing_rejected = ~missing_vis_ok;
    report.vis_malformed_rejected = all([ascii_source_rejected([1 4]) ...
        binary_source_rejected([1 4]) ascii_generated_rejected([1 4]) ...
        binary_generated_rejected([1 4])]);
    report.vis_truncated_rejected = all([ascii_source_rejected(2) ...
        binary_source_rejected(2) ascii_generated_rejected(2) ...
        binary_generated_rejected(2)]);
    report.vis_trailing_rejected = all([ascii_source_rejected(3) ...
        binary_source_rejected(3) ascii_generated_rejected(3) ...
        binary_generated_rejected(3)]);
    copy_root = fullfile(root, 'copied', 'dataset.matom', 'reconstruction', 'runs');
    mkdir(copy_root);
    copied_run = fullfile(copy_root, 'run-A');
    copyfile(run_a, copied_run, 'f');
    copied_manifest = obj.reconstruction_edit_rebase_path(fullfile(run_a, 'manifest.json'), copied_run);
    report.copied_manifest_rebased = obj.reconstruction_edit_same_path( ...
        copied_manifest, fullfile(copied_run, 'manifest.json'));
    % This hook is state/read-back evidence only; it makes no
    % biological, physiological, activation, calibration, or full
    % production-callback equivalence claim.
end

function run_dir = reconstruction_edit_fixture_make_run(obj, root, run_id)
    run_dir = fullfile(root, run_id);
    mkdir(fullfile(run_dir, 'outputs'));
    fused = fullfile(run_dir, 'outputs', 'fused-geometric.ply');
    mesh = fullfile(run_dir, 'outputs', 'mesh.ply');
    reconstruction_edit_fixture_write_ply(obj, fused, false, true);
    reconstruction_edit_fixture_write_ply(obj, mesh, true, true);
    reconstruction_edit_fixture_write_vis(obj, [fused '.vis'], 4);
    reconstruction_edit_fixture_write_vis(obj, [mesh '.vis'], 4);
    touchup = struct('id', 'legacy-touchup', ...
        'source_ply', 'outputs/mesh.ply', 'source_sha256', 'touch-source-sha', ...
        'output_ply', 'outputs/legacy-touchup.ply', 'output_sha256', 'touch-output-sha', ...
        'operations', struct('kind', 'remove_box'), ...
        'counts', struct('n_vertices_after', 3), 'created_at', 'legacy-touch-created');
    intensity = struct('id', 'legacy-intensity', ...
        'source_ply', 'outputs/fused-geometric.ply', 'source_sha256', 'intensity-source-sha', ...
        'output_ply', 'outputs/legacy-intensity.ply', 'output_sha256', 'intensity-output-sha', ...
        'operation', struct('mode', 'below', 'threshold', 128), ...
        'counts', struct('n_vertices_after', 2), 'luminance', struct('mean', 64), ...
        'created_at', 'legacy-intensity-created');
    area = struct('id', 'legacy-area', ...
        'source_ply', 'outputs/fused-geometric.ply', 'source_sha256', 'area-source-sha', ...
        'output_ply', 'outputs/legacy-area.ply', 'output_sha256', 'area-output-sha', ...
        'operation', struct('shape', 'rect'), 'counts', struct('n_vertices_after', 2), ...
        'vis', struct('regenerated', true), 'created_at', 'legacy-area-created');
    smoothing = struct('id', 'legacy-smoothing', ...
        'source_ply', 'outputs/mesh.ply', 'source_sha256', 'smooth-source-sha', ...
        'output_ply', 'outputs/legacy-smoothing.ply', 'output_sha256', 'smooth-output-sha', ...
        'operation', struct('iterations', 2), 'counts', struct('n_vertices_after', 4), ...
        'vis', struct('regenerated', true), 'created_at', 'legacy-smooth-created');
    manifest = struct('run_id', run_id, 'records', struct([]), ...
        'touchups', touchup, 'intensity_filters', intensity, ...
        'area_removals', area, 'smoothings', smoothing);
    fid = fopen(fullfile(run_dir, 'manifest.json'), 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(manifest));
    fclose(fid);
end

function tf = reconstruction_edit_fixture_legacy_records(obj, run_dir)
    %EDIT_FIXTURE_LEGACY_RECORDS Exercise the real backend read_manifest
    %normaliser for every non-empty older operation collection.
    tf = false;
    [runs_dir, run_id] = fileparts(run_dir);
    [recon_dir, runs_name] = fileparts(runs_dir); %#ok<ASGLU>
    [matom_dir, recon_name] = fileparts(recon_dir); %#ok<ASGLU>
    [dataset_root, dataset_stem, matom_ext] = fileparts(matom_dir);
    if ~strcmp(matom_ext, '.matom'), return; end
    tab = rabbit_reconstruction_tab();
    [loaded, ~] = tab.load_state(dataset_root, dataset_stem);
    if ~loaded, return; end
    [touch_ok, ~, touch] = tab.touchup_history(run_id);
    [intensity_ok, ~, intensity] = tab.intensity_history(run_id);
    [area_ok, ~, area] = tab.area_history(run_id);
    [smooth_ok, ~, smooth] = tab.smooth_history(run_id);
    if ~all([touch_ok intensity_ok area_ok smooth_ok]) || ...
            any(cellfun(@isempty, {touch, intensity, area, smooth})) || ...
            any(cellfun(@numel, {touch, intensity, area, smooth}) ~= 1)
        return;
    end
    schemas = {{'id', 'run_id', 'source_ply', 'source_sha256', ...
            'output_ply', 'output_sha256', 'manifest_path', 'operations', ...
            'counts', 'created_at'}, ...
        {'id', 'run_id', 'source_ply', 'source_sha256', ...
            'output_ply', 'output_sha256', 'manifest_path', 'operation', ...
            'counts', 'luminance', 'vis', 'created_at'}, ...
        {'id', 'run_id', 'source_ply', 'source_sha256', ...
            'output_ply', 'output_sha256', 'manifest_path', 'operation', ...
            'counts', 'vis', 'created_at'}, ...
        {'id', 'run_id', 'source_ply', 'source_sha256', ...
            'output_ply', 'output_sha256', 'manifest_path', 'operation', ...
            'counts', 'vis', 'created_at'}};
    records = {touch, intensity, area, smooth};
    expected_ids = {'legacy-touchup', 'legacy-intensity', 'legacy-area', 'legacy-smoothing'};
    expected_sources = {'touch-source-sha', 'intensity-source-sha', 'area-source-sha', 'smooth-source-sha'};
    expected_created = {'legacy-touch-created', 'legacy-intensity-created', 'legacy-area-created', 'legacy-smooth-created'};
    expected_operations = {struct('kind', 'remove_box'), ...
        struct('mode', 'below', 'threshold', 128), struct('shape', 'rect'), ...
        struct('iterations', 2)};
    operation_fields = {'operations', 'operation', 'operation', 'operation'};
    expected_manifest = fullfile(run_dir, 'manifest.json');
    tf = true;
    for r = 1:numel(records)
        record = records{r};
        for k = 1:numel(schemas{r})
            tf = tf && isfield(record, schemas{r}{k});
        end
        tf = tf && strcmp(char(record.id), expected_ids{r}) && ...
            strcmp(char(record.source_sha256), expected_sources{r}) && ...
            strcmp(char(record.created_at), expected_created{r}) && ...
            isequaln(record.(operation_fields{r}), expected_operations{r}) && ...
            strcmp(char(record.run_id), run_id) && ...
            tab.edit_same_path(record.manifest_path, expected_manifest);
    end
end

function reconstruction_edit_fixture_write_ply(obj, path, has_faces, has_rgb, variant) %#ok<INUSD>
    if nargin < 5, variant = ''; end
    fid = fopen(path, 'w', 'n', 'UTF-8');
    fprintf(fid, 'ply\nformat ascii 1.0\n');
    fprintf(fid, 'element vertex 4\nproperty float x\nproperty float y\nproperty float z\n');
    if has_rgb
        rgb_type = 'uchar';
        if strcmp(variant, 'float_rgb'), rgb_type = 'float'; end
        fprintf(fid, 'property %s red\nproperty %s green\nproperty %s blue\n', rgb_type, rgb_type, rgb_type);
        if strcmp(variant, 'alpha'), fprintf(fid, 'property uchar alpha\n'); end
    end
    if has_faces, fprintf(fid, 'element face 2\nproperty list uchar int vertex_indices\n'); end
    fprintf(fid, 'end_header\n');
    if has_rgb
        if strcmp(variant, 'float_rgb')
            fprintf(fid, '0 0 0 0.1 0.2 0.3\n1 0 0 0.4 0.5 0.6\n0 1 0 0.7 0.8 0.9\n0 0 1 1 1 1\n');
        elseif strcmp(variant, 'alpha')
            fprintf(fid, '0 0 0 10 20 30 255\n1 0 0 120 120 120 255\n0 1 0 220 220 220 255\n0 0 1 240 240 240 255\n');
        else
            fprintf(fid, '0 0 0 10 20 30\n1 0 0 120 120 120\n0 1 0 220 220 220\n0 0 1 240 240 240\n');
        end
    else
        fprintf(fid, '0 0 0\n1 0 0\n0 1 0\n0 0 1\n');
    end
    if has_faces
        if strcmp(variant, 'out_of_range_face')
            fprintf(fid, '3 0 1 8\n3 0 1 3\n');
        else
            fprintf(fid, '3 0 1 2\n3 0 1 3\n');
        end
    end
    fclose(fid);
end

function reconstruction_edit_fixture_write_vis(obj, path, n_points, format, variant) %#ok<INUSD>
    % Construct valid and intentionally invalid reference inputs only;
    % parsing/regeneration remains exclusively in production methods.
    if nargin < 4 || isempty(format), format = 'ascii'; end
    if nargin < 5 || isempty(variant), variant = 'valid'; end
    if strcmp(format, 'binary')
        fid = fopen(path, 'wb');
        count = n_points;
        if strcmp(variant, 'count_mismatch'), count = n_points + 1; end
        fwrite(fid, count, 'uint64');
        if strcmp(variant, 'malformed')
            fwrite(fid, 1, 'uint16');
            fclose(fid);
            return;
        end
        for k = 1:n_points
            fwrite(fid, 1, 'uint32');
            if ~(strcmp(variant, 'truncated') && k == n_points)
                fwrite(fid, k - 1, 'int32');
            end
        end
        if strcmp(variant, 'trailing')
            fwrite(fid, 255, 'uint8');
        end
        fclose(fid);
        return;
    end
    fid = fopen(path, 'w', 'n', 'UTF-8');
    count = n_points;
    if strcmp(variant, 'count_mismatch'), count = n_points + 1; end
    fprintf(fid, '%d\n', count);
    rows = n_points;
    if strcmp(variant, 'truncated'), rows = n_points - 1; end
    for k = 1:rows
        if strcmp(variant, 'malformed') && k == 1
            fprintf(fid, '0 trailing-text\n');
        else
            fprintf(fid, '0\n');
        end
    end
    if strcmp(variant, 'trailing'), fprintf(fid, '0\n'); end
    fclose(fid);
end

function [ok, err, info] = reconstruction_edit_fixture_verify_vis_readback(obj, path, expected_count)
    tab = rabbit_reconstruction_tab();   % a fresh tab: see the file header
    [ok, err, info] = tab.verify_vis_readback(path, expected_count);
end

function [ok, err, diag] = reconstruction_edit_fixture_regenerate_vis( ...
        obj, output_path, source_path, retained, n_before)
    tab = rabbit_reconstruction_tab();   % a fresh tab: see the file header
    [ok, err, diag] = tab.write_intensity_vis( ...
        output_path, source_path, retained, n_before);
end

function [ok, err, info] = reconstruction_edit_fixture_load_ply(obj, path)
    tab = rabbit_reconstruction_tab();   % a fresh tab: see the file header
    [ok, err, info] = tab.load_visualisation_ply(path);
end

function id = reconstruction_edit_fixture_id(obj, run_dir) %#ok<INUSD>
    [~, id] = fileparts(run_dir);
end

function name = reconstruction_edit_fixture_filename(obj, path) %#ok<INUSD>
    [~, name, ext] = fileparts(path);
    name = [name ext];
end

function d = reconstruction_edit_fixture_descriptor(obj, run_dir, operation)
    if any(strcmp(operation, {'touchup', 'smooth'}))
        p = fullfile(run_dir, 'outputs', 'mesh.ply'); cls = 'mesh';
    else
        p = fullfile(run_dir, 'outputs', 'fused-geometric.ply'); cls = 'dense point cloud';
    end
    d = obj.reconstruction_edit_empty_descriptor(operation);
    d.run_id = ''; d.run_dir = run_dir; d.source_class = cls;
    d.path = p; d.relative_path = ['outputs/' reconstruction_edit_fixture_filename(obj, p)];
    d.exists = exist(p, 'file') == 2;
    d.n_vertices = 0; d.has_faces = false;
    if d.exists
        [d.parseable, parse_err, info] = reconstruction_edit_fixture_load_ply(obj, p);
        if d.parseable
            d.n_vertices = info.n_vertices;
            d.has_faces = info.has_faces;
            if any(strcmp(operation, {'touchup', 'smooth'}))
                faces = double(info.faces(:));
                d.admissible = info.has_faces && ~isempty(faces) && ...
                    all(isfinite(faces)) && all(faces >= 1) && ...
                    all(faces <= double(info.n_vertices)) && all(faces == floor(faces));
            elseif strcmp(operation, 'intensity')
                d.admissible = ~info.has_faces && isfield(info, 'rgb') && ...
                    ~isempty(info.rgb) && size(info.rgb, 2) == 3;
            else
                d.admissible = ~info.has_faces && info.n_vertices >= 1;
            end
        else
            d.reason = ['Source is not parseable: ' parse_err];
        end
        [hash_ok, d.sha256] = obj.reconstruction_edit_hash_file(p);
        d.sha256 = char(d.sha256);
        if ~hash_ok, d.sha256 = ''; end
    end
    if ~d.admissible && isempty(d.reason)
        d.reason = 'Source is not admissible: malformed or operation-incompatible PLY.';
    end
end

function [ok, source_hash, manifest_hash] = reconstruction_edit_fixture_preview(obj, run_dir, operation, parameters)
    d = reconstruction_edit_fixture_descriptor(obj, run_dir, operation);
    source_hash = d.sha256; manifest_hash = obj.reconstruction_edit_manifest_hash(run_dir);
    ok = d.admissible;
    if ~ok, return; end
    token = struct('operation', operation, 'run_id', reconstruction_edit_fixture_id(obj, run_dir), ...
        'source_path', d.path, 'source_sha256', d.sha256, 'parameters', parameters, ...
        'parameters_sha256', obj.reconstruction_edit_digest_text(jsonencode(parameters)), ...
        'view_identity', obj.reconstruction_edit_view_identity(operation, parameters), ...
        'manifest_sha256', manifest_hash, 'output_snapshot', obj.reconstruction_edit_output_snapshot(run_dir), 'valid', true);
    obj.reconstruction_edit_upsert_pending(token);
    obj.CopyOnWriteState.selected_run_id = reconstruction_edit_fixture_id(obj, run_dir);
    obj.reconstruction_edit_publish_preview_identity(token);
    obj.CopyOnWriteState.run_root = run_dir;
    obj.CopyOnWriteState.status = 'Preview available (not written).';
end

function tf = reconstruction_edit_fixture_shared_identity_matches(obj, operation, parameters)
    tf = false;
    if ~isfield(obj.CopyOnWriteState, 'sources') || ...
            ~isfield(obj.CopyOnWriteState.sources, operation)
        return;
    end
    d = obj.CopyOnWriteState.sources.(operation);
    expected = obj.reconstruction_edit_view_identity(operation, parameters);
    summary_line = reconstruction_edit_fixture_summary_line(obj, operation);
    tf = isfield(d, 'view_identity') && isequaln(d.view_identity, expected) && ...
        isfield(expected, 'camera_bound') && expected.camera_bound && ...
        ~isempty(expected.axes_id) && ...
        strcmp(expected.projection_identity, 'pinhole-normalized-camera-v2-screen-bound') && ...
        contains(summary_line, 'used for the selection is remembered');
end

function tf = reconstruction_edit_fixture_shared_identity_clear(obj, operation)
    tf = true;
    if isfield(obj.CopyOnWriteState, 'sources') && ...
            isfield(obj.CopyOnWriteState.sources, operation)
        d = obj.CopyOnWriteState.sources.(operation);
        tf = ~isfield(d, 'view_identity') || isempty(d.view_identity) || ...
            ~isfield(d.view_identity, 'camera_bound') || ~d.view_identity.camera_bound;
    end
    tf = tf && contains(reconstruction_edit_fixture_summary_line(obj, operation), ...
        'remembered when you make the selection');
end

function line = reconstruction_edit_fixture_summary_line(obj, operation)
    label = 'Area';
    if strcmp(operation, 'smooth'), label = 'Smoothing'; end
    lines = splitlines(string(obj.CopyOnWriteSummaryLabel.Text));
    idx = find(startsWith(lines, [label ' - ']), 1, 'first');
    line = '';
    if ~isempty(idx), line = char(lines(idx)); end
end

function [ok, err] = reconstruction_edit_fixture_apply(obj, run_dir, operation, parameters)
    ok = false; err = 'Preview required.';
    idx = 0;
    for k = 1:numel(obj.CopyOnWritePending)
        if strcmp(obj.CopyOnWritePending(k).operation, operation), idx = k; end
    end
    if idx == 0 || ~obj.CopyOnWritePending(idx).valid, return; end
    p = obj.CopyOnWritePending(idx);
    if ~strcmp(p.run_id, reconstruction_edit_fixture_id(obj, run_dir)) || ...
            ~strcmp(p.parameters_sha256, obj.reconstruction_edit_digest_text(jsonencode(parameters)))
        obj.CopyOnWritePending(idx).valid = false;
        err = 'Settings changed since Preview. Preview again.';
        obj.CopyOnWriteState.status = err;
        return;
    end
    d = reconstruction_edit_fixture_descriptor(obj, run_dir, operation);
    if ~d.admissible || ~strcmp(d.sha256, p.source_sha256)
        obj.CopyOnWritePending(idx).valid = false;
        err = 'The source file changed since Preview. Preview again.';
        obj.CopyOnWriteState.status = err;
        return;
    end
    if isprop(obj, 'test_edit_fixture_noop') && obj.test_edit_fixture_noop
        obj.CopyOnWritePending(idx).valid = false;
        err = 'No-op operation rejected - nothing to apply.';
        obj.CopyOnWriteState.status = err;
        return;
    end
    out_dir = fullfile(run_dir, 'outputs', 'derived');
    if exist(out_dir, 'dir') ~= 7, mkdir(out_dir); end
    out = fullfile(out_dir, sprintf('%s-%d.ply', operation, numel(obj.CopyOnWriteApplied) + 1));
    if ~copyfile(d.path, out, 'f')
        err = 'Save not confirmed: the copy could not be written. Look in the run folder before trying again.';
        return;
    end
    [~, out_hash] = obj.reconstruction_edit_hash_file(out);
    vis_rec = struct('output_vis', '', 'source_vis', '', 'regenerated', false, ...
        'semantic_verified', false, 'source_sha256', '', 'output_sha256', '', ...
        'diagnostics', '');
    if strcmp(operation, 'touchup')
        vis_rec.diagnostics = 'touch-up fixture does not regenerate a visibility file';
    else
        vis_rec.output_vis = [out '.vis'];
        vis_rec.source_vis = [d.path '.vis'];
        if exist(vis_rec.source_vis, 'file') == 2
            if ~copyfile(vis_rec.source_vis, vis_rec.output_vis, 'f')
                vis_rec.diagnostics = 'could not copy source .vis';
            else
                [vis_ok, vis_err, vis_info] = reconstruction_edit_fixture_verify_vis_readback(obj, ...
                    vis_rec.output_vis, d.n_vertices);
                if vis_ok
                    vis_rec.regenerated = true;
                    vis_rec.semantic_verified = true;
                    [~, vis_rec.source_sha256] = obj.reconstruction_edit_hash_file(vis_rec.source_vis);
                    [~, vis_rec.output_sha256] = obj.reconstruction_edit_hash_file(vis_rec.output_vis);
                    vis_rec.diagnostics = ['read-back verified (' vis_info.format ')'];
                else
                    vis_rec.diagnostics = ['.vis read-back failed: ' vis_err];
                    if exist(vis_rec.output_vis, 'file') == 2, delete(vis_rec.output_vis); end
                end
            end
        else
            vis_rec.diagnostics = 'source .vis is missing; no derived .vis written';
        end
    end
    if isprop(obj, 'test_edit_fixture_manifest_fail') && obj.test_edit_fixture_manifest_fail
        obj.CopyOnWriteState.status = 'Save not confirmed: the saved copy could not be checked. Look in the run folder before trying again.';
        return;
    end
    mp = fullfile(run_dir, 'manifest.json');
    m = jsondecode(fileread(mp));
    if ~isfield(m, 'records') || isempty(m.records), m.records = struct('operation', {}, 'run_id', {}, 'source_ply', {}, 'source_sha256', {}, 'output_ply', {}, 'output_sha256', {}, 'manifest_path', {}, 'vis', {}, 'id', {}); end
    rec = struct('operation', operation, 'run_id', reconstruction_edit_fixture_id(obj, run_dir), 'source_ply', d.path, ...
        'source_sha256', d.sha256, 'output_ply', out, 'output_sha256', out_hash, ...
        'manifest_path', mp, 'vis', vis_rec, ...
        'id', sprintf('%s-%d', operation, numel(m.records) + 1));
    m.records(end+1) = rec;
    fid = fopen(mp, 'w', 'n', 'UTF-8'); fprintf(fid, '%s', jsonencode(m)); fclose(fid);
    % Read back the manifest record, output PLY and source digest.
    try
        m2 = jsondecode(fileread(mp));
        read_ok = false;
        if isfield(m2, 'records') && ~isempty(m2.records)
            for rk = numel(m2.records):-1:1
                rr = m2.records(rk);
                fixture_operation_ok = isfield(rr, 'operation') && ...
                    strcmp(char(rr.operation), char(operation));
                fixture_run_ok = isfield(rr, 'run_id') && ...
                    strcmp(char(rr.run_id), char(reconstruction_edit_fixture_id(obj, run_dir)));
                fixture_source_ok = isfield(rr, 'source_ply') && ...
                    obj.reconstruction_edit_same_path(rr.source_ply, d.path) && ...
                    isfield(rr, 'source_sha256') && strcmpi(char(rr.source_sha256), char(d.sha256));
                fixture_manifest_ok = isfield(rr, 'manifest_path') && ...
                    obj.reconstruction_edit_same_path(rr.manifest_path, mp);
                fixture_vis_ok = isfield(rr, 'vis') && isequaln(rr.vis, rec.vis);
                if fixture_operation_ok && fixture_run_ok && fixture_source_ok && ...
                        fixture_manifest_ok && fixture_vis_ok && ...
                        isfield(rr, 'id') && strcmp(char(rr.id), char(rec.id)) && ...
                        isfield(rr, 'output_ply') && obj.reconstruction_edit_same_path(rr.output_ply, out) && ...
                        isfield(rr, 'output_sha256') && strcmpi(char(rr.output_sha256), char(out_hash))
                    read_ok = true;
                    break;
                end
            end
        end
        [output_ok, ~, ~] = reconstruction_edit_fixture_ply_readback(obj, out);
        [source_ok, source_hash_after] = obj.reconstruction_edit_hash_file(d.path);
        read_ok = read_ok && output_ok && strcmpi(source_hash_after, d.sha256);
    catch
        read_ok = false;
    end
    if ~read_ok
        obj.CopyOnWriteState.status = 'Save not confirmed: the saved copy or the run record could not be read back. Look in the run folder before trying again.';
        return;
    end
    obj.CopyOnWriteApplied(end+1) = struct('operation', operation, 'run_id', reconstruction_edit_fixture_id(obj, run_dir), ...
        'selected_run_id', reconstruction_edit_fixture_id(obj, run_dir), ...
        'output_path', out, 'output_sha256', out_hash, 'manifest_path', mp, 'record_id', rec.id, 'source_sha256', d.sha256);
    obj.CopyOnWritePending(idx).valid = false;
    obj.CopyOnWriteState.status = sprintf('Saved as a copy - %s; the new file and the run record were checked after saving.', operation);
    ok = true;
end

function reconstruction_edit_fixture_invalidate(obj, operation)
    obj.reconstruction_edit_invalidate_preview_identity(operation);
end

function reconstruction_edit_fixture_invalidate_all(obj)
    for k = 1:numel(obj.CopyOnWritePending)
        obj.reconstruction_edit_invalidate_preview_identity( ...
            obj.CopyOnWritePending(k).operation);
    end
end

function reconstruction_edit_fixture_cancel(obj, operation)
    reconstruction_edit_fixture_invalidate(obj, operation);
    obj.CopyOnWriteState.status = 'Selection cancelled - no output written.';
end

function reconstruction_edit_fixture_view_changed(obj, operation)
    reconstruction_edit_fixture_invalidate(obj, operation);
    obj.CopyOnWriteState.status = 'The view changed since Preview. Preview again.';
end

function [ok, err, info] = reconstruction_edit_fixture_ply_readback(obj, path) %#ok<INUSD>
    ok = false; err = ''; info = struct();
    try
        raw = fileread(path);
        ok = contains(raw, 'ply') && contains(raw, 'end_header');
        if ~ok, err = 'output is not a readable PLY'; end
    catch ME
        err = ME.identifier;
    end
end

function tf = reconstruction_edit_fixture_pending_valid(obj, operation)
    tf = false;
    for k = 1:numel(obj.CopyOnWritePending)
        if strcmp(obj.CopyOnWritePending(k).operation, operation), tf = obj.CopyOnWritePending(k).valid; end
    end
end

function reconstruction_edit_fixture_cleanup(obj, root)
    obj.test_edit_fixture_mode = false;
    if exist(root, 'dir') == 7
        try, rmdir(root, 's'); catch, end
    end
end
