function probe_point_edit_tool_panel
%% Shared tool panel layout and state
% Collin Snitchler
% 13.09.2026
% Checks the panel layout in the app source and archive, and the test-only
% state and side-effect interface of the shared tools panel.
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
addpath(fullfile(repo_dir, 'tests', 'helpers'));   % reconstruction_ui_fixture

app = analyse_optical_mapping;
cleanup = onCleanup(@() close_app(app)); %#ok<NASGU>

pass = 0;
fail = 0;

record('P1', has_all_properties(app, { ...
    'CopyOnWritePanel', 'CopyOnWriteContractLabel', ...
    'CopyOnWriteSummaryLabel', 'CopyOnWriteStatusLabel'}), ...
    'shared panel, banner, summary, and status properties exist');

has_shared_parent = false;
if isprop(app.recon, 'CopyOnWritePanel') && isprop(app.recon, 'ToolsPanel') && ...
        isprop(app.recon, 'ToolsPanelLayout')
    children = {'TouchupPanel', 'IntensityPanel', 'AreaPanel', 'SmoothPanel'};
    has_shared_parent = true;
    try
        % ToolsPanelLayout is the only layout parent; there is no hidden
        % intermediate grid between it and the panel controls.
        has_shared_parent = isequal(app.recon.CopyOnWritePanel.Parent, app.recon.ToolsPanelLayout) && ...
            isequal(app.recon.ToolsPanelLayout.Parent, app.recon.ToolsPanel) && ...
            strcmp(char(app.recon.ToolsPanelLayout.Visible), 'on');
        for k = 1:numel(children)
            if ~isprop(app.recon, children{k}) || ...
                    ~isequal(app.recon.(children{k}).Parent, app.recon.CopyOnWritePanel)
                has_shared_parent = false;
            end
        end
    catch
        has_shared_parent = false;
    end
end
record('P2', has_shared_parent, ...
    'visible ToolsPanelLayout owns the shared panel, which owns all four operation sections');

contract = component_text(app, 'CopyOnWriteContractLabel');
contract_lower = lower(contract);
record('P3', contains(contract, 'Preview') && ...
    contains(contract_lower, 'on screen only') && ...
    contains(contract, 'Apply to copy') && ...
    (contains(contract_lower, 'does not undo') || ...
     contains(contract_lower, 'does not delete')) && ...
    ~contains(contract_lower, 'biological validity') && ...
    ~contains(contract_lower, 'calibration validity'), ...
    'banner states on-screen-only Preview, copy Apply, retained Reset, and neutral scope');

summary = component_text(app, 'CopyOnWriteSummaryLabel');
summary_lower = lower(summary);
% With no run selected there is no source class or path yet; each tool's
% line says that no source is available instead
record('P4', contains(summary, 'Selected run') && ...
    contains(summary_lower, 'no source available') && ...
    contains(summary_lower, 'touch-up') && ...
    contains(summary_lower, 'intensity') && ...
    contains(summary_lower, 'area') && ...
    contains(summary_lower, 'smoothing') && ...
    ~contains(summary_lower, 'biological validity') && ...
    ~contains(summary_lower, 'calibration validation'), ...
    'summary exposes run and operation-specific source descriptors');

status = component_text(app, 'CopyOnWriteStatusLabel');
record('P5', contains(status, 'No run selected') && ...
    ~contains(status, 'Ready'), ...
    'initial state is exactly the no-run vocabulary, not a false-green Ready');

record('P6', all_read_only(app, { ...
    'TouchupSourceField', 'IntensitySourceField', ...
    'AreaSourceField', 'SmoothSourceField'}), ...
    'operation source fields remain read-only');

no_run_controls = { ...
    'TouchupOpDropDown', 'TouchupBoxField', 'TouchupMinFacesField', ...
    'IntensityModeDropDown', 'IntensityThresholdField', ...
    'AreaShapeDropDown', ...
    'SmoothRadiusField', 'SmoothIterationsField', 'SmoothStrengthField', ...
    'TouchupPreviewButton', 'TouchupApplyButton', ...
    'IntensityPreviewButton', 'IntensityApplyButton', ...
    'AreaSelectButton', 'AreaPreviewButton', 'AreaApplyButton', ...
    'SmoothSelectButton', 'SmoothPreviewButton', 'SmoothApplyButton'};
record('P7', all_disabled(app, no_run_controls), ...
    'all source-dependent controls are disabled without a selected run');

[archive_ok, xml, archive_detail] = inspect_archive(repo_dir);
% The tab's code is in rabbit_reconstruction_ui.m; check it with the .mlapp's
xml = [xml newline fileread(fullfile(repo_dir, 'rabbit_reconstruction_ui.m'))];
backend = fileread(fullfile(repo_dir, 'rabbit_reconstruction_tab.m'));
static_ok = archive_ok && ...
    contains(xml, 'CopyOnWritePanel') && ...
    contains(xml, 'CopyOnWriteContractLabel') && ...
    contains(xml, 'CopyOnWriteSummaryLabel') && ...
    contains(xml, 'CopyOnWriteStatusLabel') && ...
    contains(xml, 'obj.ReconstructionTouchupPreviewButtonPushed') && ...
    contains(xml, 'obj.ReconstructionTouchupApplyButtonPushed') && ...
    contains(xml, 'obj.ReconstructionIntensityPreviewButtonPushed') && ...
    contains(xml, 'obj.ReconstructionIntensityApplyButtonPushed') && ...
    contains(xml, 'obj.ReconstructionAreaPreviewButtonPushed') && ...
    contains(xml, 'obj.ReconstructionAreaApplyButtonPushed') && ...
    contains(xml, 'obj.ReconstructionSmoothPreviewButtonPushed') && ...
    contains(xml, 'obj.ReconstructionSmoothApplyButtonPushed') && ...
    contains(xml, 'edit_manifest_sha256') && ...
    contains(xml, 'pinhole-normalized-camera-v2-screen-bound') && ...
    contains(backend, 'verify_vis_readback') && contains(backend, 'semantic_verified') && ...
    contains(backend, 'zero vertex displacement') && ...
    contains(xml, 'reconstruction_edit_path_in_run') && ...
    ~contains(xml, 'obj.TouchupPanel = uipanel(obj.GridLayoutS5)') && ...
    ~contains(xml, 'obj.IntensityPanel = uipanel(obj.GridLayoutS5)') && ...
    ~contains(xml, 'obj.AreaPanel = uipanel(obj.GridLayoutS5)') && ...
    ~contains(xml, 'obj.SmoothPanel = uipanel(obj.GridLayoutS5)') && ...
    ~contains(lower(function_span(xml, ...
        'function ReconstructionTouchupPreviewButtonPushed', ...
        'function ReconstructionTouchupResetButtonPushed')), 'str2num') && ...
    (contains(lower(xml), 'scrollable') || ...
     ~contains(xml, 'RowHeight = [264 242 242 286]'));
record('P8', static_ok, ...
    ['saved MLAPP archive, ownership, callbacks, parser, and layout gate (' ...
     archive_detail ')']);

% The fixture (tests/helpers/reconstruction_ui_fixture.m) reports 25
% invariants of the app's edit state plus the legacy record normalisation
% invariant. Keep this list complete: a subset could let a failing
% invariant go unnoticed.
fixture_fields = { ...
    'no_run_controls_disabled', 'preview_preserves_source', ...
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
    'selection_cancel_no_write', 'view_identity_invalidates', ...
    'no_op_rejected', 'legacy_record_normalized'};
[fixture_ok, fixture_detail] = run_fixture_contract(app, fixture_fields);
record('P9', fixture_ok, ['deterministic C2.3 state/read-back seam (fixture only; no biological/calibration or full-callback claim) (' ...
    fixture_detail ')']);

fprintf('PROBE_POINT_EDIT_TOOL_PANEL RESULT: %d passed, %d failed\n', pass, fail);
if fail ~= 0
    fprintf('PROBE_FAIL probe_point_edit_tool_panel\n');
    error('PROBE_FAIL probe_point_edit_tool_panel');
end
fprintf('PROBE_OK probe_point_edit_tool_panel %d/%d\n', pass, pass + fail);

    function record(name, condition, detail)
        condition = logical(condition);
        if condition
            pass = pass + 1;
            result = 'PASS';
        else
            fail = fail + 1;
            result = 'FAIL';
        end
        fprintf('  %s %s %s\n', name, result, detail);
    end
end

function tf = has_all_properties(app, names)
tf = true;
for k = 1:numel(names)
    tf = tf && isprop(app.recon, names{k});
end
end

function tf = all_read_only(app, names)
tf = true;
for k = 1:numel(names)
    if ~isprop(app.recon, names{k})
        tf = false;
        continue;
    end
    try
        tf = tf && strcmp(char(app.recon.(names{k}).Editable), 'off');
    catch
        tf = false;
    end
end
end

function tf = all_disabled(app, names)
tf = true;
for k = 1:numel(names)
    if ~isprop(app.recon, names{k})
        tf = false;
        continue;
    end
    try
        tf = tf && strcmp(char(app.recon.(names{k}).Enable), 'off');
    catch
        tf = false;
    end
end
end

function txt = component_text(app, name)
txt = '';
if ~isprop(app.recon, name)
    return;
end
try
    value = app.recon.(name).Text;
    if iscell(value)
        value = strjoin(value, ' ');
    end
    txt = char(value);
catch
    txt = '';
end
end

function [ok, detail] = run_fixture_contract(app, fields)
ok = false;
detail = 'seam absent or fixture report incomplete';
if exist('reconstruction_ui_fixture', 'file') ~= 2
    return;
end
try
    report = reconstruction_ui_fixture(app.recon);
    values = false(1, numel(fields));
    for k = 1:numel(fields)
        values(k) = isfield(report, fields{k}) && ...
            isscalar(report.(fields{k})) && logical(report.(fields{k}));
    end
    ok = all(values);
    detail = sprintf('%d/%d required invariants reported true', ...
        sum(values), numel(values));
catch ME
    detail = ['seam error: ' ME.identifier];
end
end

function [ok, xml, detail] = inspect_archive(repo_dir)
ok = false;
xml = '';
detail = 'archive unavailable';
archive_path = fullfile(repo_dir, 'analyse_optical_mapping.mlapp');
tmp = tempname;
try
    mkdir(tmp);
    unzip(archive_path, tmp);
    expected = { ...
        '[Content_Types].xml', '_rels/.rels', ...
        'appdesigner/appModel.mat', 'matlab/document.xml', ...
        'metadata/appMetadata.xml', 'metadata/coreProperties.xml', ...
        'metadata/mwcoreProperties.xml', ...
        'metadata/mwcorePropertiesExtension.xml', ...
        'metadata/mwcorePropertiesReleaseInfo.xml', ...
        'metadata/appScreenshot.png'};
    files = dir(fullfile(tmp, '**', '*'));
    actual = {};
    for k = 1:numel(files)
        if ~files(k).isdir
            full_name = fullfile(files(k).folder, files(k).name);
            rel = strrep(full_name, [tmp filesep], '');
            actual{end + 1} = strrep(rel, filesep, '/'); %#ok<AGROW>
        end
    end
    actual = sort(actual);
    expected = sort(expected);
    doc_path = fullfile(tmp, 'matlab', 'document.xml');
    if exist(doc_path, 'file') == 2
        xml = fileread(doc_path);
    end
    ok = isequal(actual, expected) && ~isempty(xml);
    detail = sprintf('%d archive members, document.xml=%s', ...
        numel(actual), yesno(~isempty(xml)));
catch ME
    detail = ['archive error: ' ME.identifier];
end
safe_remove(tmp);
end

function out = function_span(text, start_marker, end_marker)
out = '';
start_at = strfind(text, start_marker);
if isempty(start_at)
    return;
end
start_at = start_at(1);
end_at = strfind(text(start_at + numel(start_marker):end), end_marker);
if isempty(end_at)
    out = text(start_at:end);
else
    out = text(start_at:start_at + numel(start_marker) + end_at(1) - 2);
end
end

function out = yesno(tf)
if tf
    out = 'yes';
else
    out = 'no';
end
end

function safe_remove(path_name)
try
    if exist(path_name, 'dir') == 7
        rmdir(path_name, 's');
    end
catch
end
end

function close_app(app)
try
    if isvalid(app)
        delete(app);
    end
catch
end
end
