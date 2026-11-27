function probe_visualise_captions
%% Self-describing reconstruction viewer
% Collin Snitchler
% 13.09.2026
% Checks the linked reconstruction viewer (sparse | dense | APDe | mesh |
% sparse | dense | APDe | mesh | activation | video; the dense cloud, mesh
% and activation panels carry the checks below):
% 1. Scientific descriptors, roles, titles, subtitles, and panel tags.
% 2. Exact axis title matching for legacy probe compatibility.
% 3. Text objects rendered with Interpreter='none'.
% 4. Comma-formatted geometry and vertex counts.
% 5. Canonical zero and NaN are told apart ([0; NaN; 2]).
% 6. Zeros in a legacy PLY are reported as ambiguous.
% 7. Neutral grey shading for all-zero activation scalar.
% 8. Safe placeholders on missing panels without camera limit poisoning.
% 9. Fail-closed handling for incompatible/malformed PLYs.
% 10. Face-free point cloud and face-free mesh rendering.
% 11. Security and containment boundary enforcement.
% 12. Strict byte immutability of inputs and manifests across open/close.
% 13. Camera linkprop across all panels; one-line header.
% 14. Machine-readable figure appdata metadata.
% 15. Portable rendered fixtures, plus checks on trusted inputs, manual entry and camera restore.
% Check 14 reads the fixtures under OM_TEST_VISUALISE_FIXTURE_ROOT (default
% tests/fixtures/reproj-recon/staging).

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);

pass = 0; fail = 0; skip = 0;
tf = @(b) char(70 + 14*logical(b));

root = tempname(tempdir);
run_id = '20260913T120000_c31ae101';
run_dir = fullfile(root, 'test.matom', 'reconstruction', 'runs', run_id);
out_dir = fullfile(run_dir, 'outputs');
reproj_dir = fullfile(out_dir, 'reprojection');
mkdir(reproj_dir);
cleanup = onCleanup(@() cleanup_case(root)); %#ok<NASGU>

tab = rabbit_reconstruction_tab();
tab.load_state(root, 'test');

% -------------------------------------------------------------------------
% Check 1: Number formatting helper format_count
% -------------------------------------------------------------------------
f0 = strcmp(tab.format_count(0), '0');
f1 = strcmp(tab.format_count(924), '924');
f2 = strcmp(tab.format_count(16781), '16,781');
f3 = strcmp(tab.format_count(1000000), '1,000,000');
record('C1 format_count comma formatting', f0 && f1 && f2 && f3, ...
    sprintf('0=%s, 924=%s, 16781=%s', tab.format_count(0), tab.format_count(924), tab.format_count(16781)));

% -------------------------------------------------------------------------
% Generate clean synthetic files
% -------------------------------------------------------------------------
fused_path = fullfile(out_dir, 'fused-geometric.ply');
rebuilt_path = fullfile(out_dir, 'alignment-rebuilt-mesh.ply');
projected_path = fullfile(reproj_dir, 'activation_projected.ply');
write_text_utf8(fused_path, point_cloud_ply());
write_text_utf8(rebuilt_path, mesh_ply(false, [10 0 0; 11 0 0; 10 1 0], [1 2 3]));
write_text_utf8(projected_path, mesh_with_scalar_ply([20 0 0; 21 0 0; 20 1 0], [1 2 3], [10; 20; 30]));

v1_path = fullfile(run_dir, 'manifest.json');
v1 = valid_v1(run_id, root, 'RUNNING');
v1_bytes = jsonencode(v1, 'PrettyPrint', true);
write_text_utf8(v1_path, v1_bytes);
[v2_bytes, ~] = tab.convert_v1_to_v2(v1_path, run_dir);
v2_path = fullfile(run_dir, 'manifest.v2.json');
tab.load_state(root, 'test');

vis_base = struct('run_id', run_id, 'run_dir', run_dir, ...
    'fused_ply', fused_path, 'rebuilt_ply', rebuilt_path, ...
    'projected_ply', projected_path, 'camera_state', [], ...
    'camera_origin_sha256', '', 'camera_origin_revision', '', ...
    'projected_output', [], 'active_manifest', v1);

% -------------------------------------------------------------------------
% Check 2: Scientific descriptors, titles, subtitles, tags, geometry counts
% -------------------------------------------------------------------------
[ok_vis, err_vis, fig] = tab.visualise_artifacts(vis_base);
assert(ok_vis, ['visualise_artifacts failed: ' err_vis]);

ax_fused = findobj(fig, 'Tag', 'panel_fused');
ax_rebuilt = findobj(fig, 'Tag', 'panel_rebuilt');
ax_projected = findobj(fig, 'Tag', 'panel_projected');

has_tags = ~isempty(ax_fused) && ~isempty(ax_rebuilt) && ~isempty(ax_projected);
% Titles name what the panel shows, in words (the file is in the (i)
% tooltip); the mesh title names how the mesh was made (here the alignment
% stage's rebuilt mesh, as there is no mesh-cleanup.ply). The captions are
% read with Panel details ticked (subtitle_text), which adds the full text
em = char(8212);
title_fused_ok = strcmp(get(get(ax_fused, 'Title'), 'String'), ['Dense cloud ' em ' COLMAP']);
title_rebuilt_ok = strcmp(get(get(ax_rebuilt, 'Title'), 'String'), ['Mesh ' em ' rebuilt by the alignment']);
title_projected_ok = strcmp(get(get(ax_projected, 'Title'), 'String'), 'Activation time (ms)');
info_tip = get(findobj(fig, 'Tag', 'ReconstructionPanelInfo_fused'), 'TooltipString');
title_fused_ok = title_fused_ok && contains(info_tip, 'fused-geometric.ply');

sub_fused = subtitle_text(ax_fused);
sub_rebuilt = subtitle_text(ax_rebuilt);
sub_projected = subtitle_text(ax_projected);

desc_ok = contains(sub_fused, 'Pre-cleanup stereo fusion point cloud') && ...
    contains(sub_rebuilt, 'Surface mesh rebuilt by the alignment stage') && ~contains(sub_rebuilt, 'Poisson') && ...
    contains(sub_projected, 'Optical mapping activation times reprojected onto 3D geometry');

geom_ok = contains(sub_fused, '3 vertices, 0 faces (point cloud)') && ...
    contains(sub_rebuilt, '3 vertices, 1 face');

record('C2 Titles, subtitles, tags, and geometry counts', ...
    has_tags && title_fused_ok && title_rebuilt_ok && title_projected_ok && desc_ok && geom_ok, ...
    sprintf('tags=%s titles=%s desc=%s geom=%s', tf(has_tags), ...
    tf(title_fused_ok && title_rebuilt_ok && title_projected_ok), tf(desc_ok), tf(geom_ok)));

% -------------------------------------------------------------------------
% Check 3: Interpreter = 'none' on titles, subtitles, and the header
% -------------------------------------------------------------------------
interp_titles = strcmp(get(get(ax_fused, 'Title'), 'Interpreter'), 'none') && ...
    strcmp(get(get(ax_rebuilt, 'Title'), 'Interpreter'), 'none') && ...
    strcmp(get(get(ax_projected, 'Title'), 'Interpreter'), 'none');
interp_subs = strcmp(get(get(ax_fused, 'Subtitle'), 'Interpreter'), 'none') && ...
    strcmp(get(get(ax_rebuilt, 'Subtitle'), 'Interpreter'), 'none') && ...
    strcmp(get(get(ax_projected, 'Subtitle'), 'Interpreter'), 'none');

hint_obj = findall(fig, 'Tag', 'ReconstructionHeader');
interp_hint = isscalar(hint_obj) && strcmp(get(hint_obj, 'Interpreter'), 'none') && ...
    contains(get(hint_obj, 'String'), run_id) && ~contains(get(hint_obj, 'String'), newline);

record('C3 Interpreter none on text elements', interp_titles && interp_subs && interp_hint, ...
    sprintf('titles=%s subs=%s hint=%s', tf(interp_titles), tf(interp_subs), tf(interp_hint)));

% -------------------------------------------------------------------------
% Check 4: Camera linkprop across all panels (the sparse and video panels
% are placeholders here but still follow the shared camera)
% -------------------------------------------------------------------------
set(ax_fused, 'CameraPosition', [15 25 35]);
drawnow;
p_rebuilt = get(ax_rebuilt, 'CameraPosition');
p_projected = get(ax_projected, 'CameraPosition');
all_ax = getappdata(fig, 'reconstruction_all_axes');
p_all = cell2mat(get(all_ax(:), 'CameraPosition'));
cam_linked = all(abs(p_rebuilt - [15 25 35]) < 1e-6) && all(abs(p_projected - [15 25 35]) < 1e-6) && ...
    numel(all_ax) >= 5 && all(abs(p_all - [15 25 35]) < 1e-6, 'all') && ...
    ~isempty(findobj(fig, 'Tag', 'panel_sparse')) && ~isempty(findobj(fig, 'Tag', 'panel_video'));
record('C4 Camera linkprop propagation', cam_linked, ...
    sprintf('rebuilt=[%.1f %.1f %.1f] projected=[%.1f %.1f %.1f] panels=%d', p_rebuilt, p_projected, numel(all_ax)));

% -------------------------------------------------------------------------
% Check 5: Machine-readable appdata metadata
% -------------------------------------------------------------------------
meta = getappdata(fig, 'reconstruction_panel_metadata');
appdata_ok = isstruct(meta) && numel(meta) == 3 && ...
    strcmp(meta(1).role_id, 'fused') && strcmp(meta(1).render_status, 'READY') && meta(1).stats.n_vertices == 3 && meta(1).stats.n_faces == 0 && ...
    strcmp(meta(2).role_id, 'rebuilt') && strcmp(meta(2).render_status, 'READY') && meta(2).stats.n_faces == 1 && ...
    strcmp(meta(3).role_id, 'projected') && strcmp(meta(3).render_status, 'READY') && meta(3).stats.n_nonzero == 3;
record('C5 Figure appdata metadata structure', appdata_ok, ...
    sprintf('isstruct=%s count=%d role3=%s', tf(isstruct(meta)), numel(meta), meta(3).role_id));

if isgraphics(fig), close(fig); end

% -------------------------------------------------------------------------
% Check 6: Manifest-bound canonical face-domain semantics
% -------------------------------------------------------------------------
write_text_utf8(v2_path, v2_bytes);
tab = rabbit_reconstruction_tab();
tab.load_state(root, 'test');
[fixture_active_path, fixture_active_schema, fixture_active_warning, fixture_active_fail, fixture_active_kind] = ...
    tab.active_manifest_path(run_dir);
assert(~fixture_active_fail && strcmp(fixture_active_kind, 'VALID_V2') && ...
    strcmp(fixture_active_schema, 'cd2.reconstruction.manifest.v2') && ...
    strcmp(fixture_active_path, v2_path), fixture_active_warning);
canon_pts = [10 0 0; 11 0 0; 10 1 0; 11 1 0; 10.5 2 0];
canon_faces = [1 2 3; 2 4 3; 3 4 5];
write_text_utf8(rebuilt_path, mesh_ply(false, canon_pts, canon_faces));
write_text_utf8(projected_path, mesh_with_scalar_ply(canon_pts, canon_faces, 100 + (1:5)'));
[mesh_hash_ok, target_digest, mesh_hash_err] = tab.manifest_bytes_sha256(rebuilt_path);
assert(mesh_hash_ok, mesh_hash_err);
[wire, werr] = activation_state_with_projection(tab, [0; NaN; 2], target_digest);
assert(isempty(werr), ['activation_state_with_projection failed: ' werr]);

canon_manifest = jsondecode(v2_bytes);
canon_manifest.phase1_revision = '0';
canon_manifest.field_revisions = struct();
canon_manifest.restore.activation_map = wire;
[wire_write_ok, wire_write_err] = tab.write_active_manifest(run_dir, ...
    @(m) set_activation_restore(m, wire));
assert(wire_write_ok, wire_write_err);
vis_canon = vis_base;
vis_canon.active_manifest_path = v2_path;

[ok_c, err_c, fig_c] = tab.visualise_artifacts(vis_canon);
assert(ok_c, ['visualise_artifacts with canonical wire failed: ' err_c]);

meta_c = getappdata(fig_c, 'reconstruction_panel_metadata');
ax_c3 = findobj(fig_c, 'Tag', 'panel_projected');
sub_c3 = subtitle_text(ax_c3);
canon_meta_ok = strcmp(meta_c(3).stats.activation_domain, 'faces') && ...
    meta_c(3).stats.n_activation_elements == 3 && ...
    meta_c(3).stats.n_assigned == 2 && meta_c(3).stats.n_unassigned == 1 && ...
    meta_c(3).stats.n_zero == 1 && meta_c(3).stats.n_nonzero == 1;
canon_sub_ok = contains(sub_c3, 'Coverage: 2 / 3 faces assigned (1 at 0 ms)');   % R3-9: the zero count only
cb_c = findobj(fig_c, 'Type', 'ColorBar');
cb_c_ok = ~isempty(cb_c) && norm(double(cb_c.Limits) - [0 2]) < 1e-6;
record('C6 Canonical face-domain zero vs NaN semantics', canon_meta_ok && canon_sub_ok && cb_c_ok, ...
    sprintf('assigned=%d unassigned=%d zero=%d nonzero=%d sub_ok=%s cb_clim=%s', ...
    meta_c(3).stats.n_assigned, meta_c(3).stats.n_unassigned, meta_c(3).stats.n_zero, meta_c(3).stats.n_nonzero, tf(canon_sub_ok), tf(cb_c_ok)));
if isgraphics(fig_c), close(fig_c); end

% All-unassigned and valid-all-zero are distinct scientific states.
[wire_unassigned, wu_err] = activation_state_with_projection(tab, [NaN; NaN; NaN], target_digest);
assert(isempty(wu_err), wu_err);
canon_manifest.restore.activation_map = wire_unassigned;
[wire_write_ok, wire_write_err] = tab.write_active_manifest(run_dir, ...
    @(m) set_activation_restore(m, wire_unassigned));
assert(wire_write_ok, wire_write_err);
vis_unassigned = vis_canon;
[ok_u, err_u, fig_u] = tab.visualise_artifacts(vis_unassigned);
assert(ok_u, err_u);
meta_u = getappdata(fig_u, 'reconstruction_panel_metadata');
sub_u = subtitle_text(findobj(fig_u, 'Tag', 'panel_projected'));
unassigned_ok = meta_u(3).stats.n_assigned == 0 && meta_u(3).stats.n_unassigned == 3 && ...
    contains(sub_u, 'all 3 faces are unassigned') && contains(sub_u, 'no activation values available') && ...
    isempty(findobj(fig_u, 'Type', 'ColorBar'));
record('C6b All-unassigned is explicit and not collapsed to zero', unassigned_ok, sub_u);
if isgraphics(fig_u), close(fig_u); end

[wire_zero, wz_err] = activation_state_with_projection(tab, [0; 0; 0], target_digest);
assert(isempty(wz_err), wz_err);
canon_manifest.restore.activation_map = wire_zero;
[wire_write_ok, wire_write_err] = tab.write_active_manifest(run_dir, ...
    @(m) set_activation_restore(m, wire_zero));
assert(wire_write_ok, wire_write_err);
vis_canon_zero = vis_canon;
[ok_cz, err_cz, fig_cz] = tab.visualise_artifacts(vis_canon_zero);
assert(ok_cz, err_cz);
meta_cz = getappdata(fig_cz, 'reconstruction_panel_metadata');
sub_cz = subtitle_text(findobj(fig_cz, 'Tag', 'panel_projected'));
canon_zero_ok = meta_cz(3).stats.n_assigned == 3 && meta_cz(3).stats.n_zero == 3 && ...
    contains(sub_cz, 'all 3 assigned face values are 0') && ~contains(sub_cz, 'unassigned');
record('C6c Valid-all-zero remains assigned and distinct', canon_zero_ok, sub_cz);
if isgraphics(fig_cz), close(fig_cz); end

% Restore the selected sidecar before testing that an unbound direct wire
% cannot override it.
write_text_utf8(v2_path, v2_bytes);

% Direct caller injection is not authoritative: without a manifest restore
% record the same wire must not upgrade legacy PLY semantics to CANONICAL.
vis_injected = vis_base;
vis_injected.projected_output = wire_zero;
[pm_inject_ok, ~, panels_inject] = tab.visualisation_panel_model(vis_injected);
record('C6d Direct projected_output injection cannot claim canonical', ...
    pm_inject_ok && ~strcmp(panels_inject(3).activation_semantics, 'CANONICAL'), ...
    panels_inject(3).activation_semantics);

% A same-mesh AVAILABLE wire from another run cannot be injected either as
% a caller manifest struct or through an unselected manifest path.
foreign_manifest = canon_manifest;
foreign_manifest.run_id = '20260913T000001_foreign';
vis_spoof = vis_base;
vis_spoof.active_manifest = foreign_manifest;
[spoof_ok, ~, spoof_panels] = tab.visualisation_panel_model(vis_spoof);
foreign_path = fullfile(run_dir, 'manifest.foreign.json');
write_text_utf8(foreign_path, jsonencode(foreign_manifest, 'PrettyPrint', true));
vis_foreign_path = vis_canon;
vis_foreign_path.active_manifest_path = foreign_path;
[foreign_ok, foreign_err] = tab.visualisation_panel_model(vis_foreign_path);

duplicate_dir = fullfile(root, 'duplicate.matom', 'reconstruction', 'runs', run_id);
duplicate_out = fullfile(duplicate_dir, 'outputs');
mkdir(fullfile(duplicate_out, 'reprojection'));
copyfile(fused_path, fullfile(duplicate_out, 'fused-geometric.ply'));
copyfile(rebuilt_path, fullfile(duplicate_out, 'alignment-rebuilt-mesh.ply'));
copyfile(projected_path, fullfile(duplicate_out, 'reprojection', 'activation_projected.ply'));
duplicate_v1 = fullfile(duplicate_dir, 'manifest.json');
duplicate_v2 = fullfile(duplicate_dir, 'manifest.v2.json');
write_text_utf8(duplicate_v1, v1_bytes);
duplicate_builder = rabbit_reconstruction_tab();
[duplicate_v2_bytes, ~] = duplicate_builder.convert_v1_to_v2(duplicate_v1, duplicate_dir);
write_text_utf8(duplicate_v2, duplicate_v2_bytes);
duplicate_builder.load_state(root, 'duplicate');
[duplicate_write_ok, duplicate_write_err] = duplicate_builder.write_active_manifest(duplicate_dir, ...
    @(m) set_activation_restore(m, wire_zero));
assert(duplicate_write_ok, duplicate_write_err);
vis_duplicate = vis_canon;
vis_duplicate.run_dir = duplicate_dir;
vis_duplicate.fused_ply = fullfile(duplicate_out, 'fused-geometric.ply');
vis_duplicate.rebuilt_ply = fullfile(duplicate_out, 'alignment-rebuilt-mesh.ply');
vis_duplicate.projected_ply = fullfile(duplicate_out, 'reprojection', 'activation_projected.ply');
vis_duplicate.active_manifest_path = duplicate_v2;
[duplicate_ok, duplicate_err] = tab.visualisation_panel_model(vis_duplicate);

record('C6e Same-mesh foreign-run manifest cannot claim canonical', ...
    spoof_ok && ~strcmp(spoof_panels(3).activation_semantics, 'CANONICAL') && ...
    ~foreign_ok && contains(foreign_err, 'not the selected active manifest') && ...
    ~duplicate_ok && contains(duplicate_err, 'run directory does not match'), ...
    sprintf('struct_semantics=%s path_ok=%s duplicate_ok=%s path_err=%s duplicate_err=%s', ...
    spoof_panels(3).activation_semantics, tf(foreign_ok), tf(duplicate_ok), foreign_err, duplicate_err));

% Return to a v1-only run with a fresh resolver for explicit legacy tests.
delete(v2_path);
tab = rabbit_reconstruction_tab();
tab.load_state(root, 'test');

% Restore the compact legacy fixture used by subsequent checks.
write_text_utf8(rebuilt_path, mesh_ply(false, [10 0 0; 11 0 0; 10 1 0], [1 2 3]));
write_text_utf8(projected_path, mesh_with_scalar_ply([20 0 0; 21 0 0; 20 1 0], [1 2 3], [10; 20; 30]));

% -------------------------------------------------------------------------
% Check 7: Legacy ambiguous zero semantics ([0; 0; 5] without canonical wire)
% -------------------------------------------------------------------------
write_text_utf8(projected_path, mesh_with_scalar_ply([20 0 0; 21 0 0; 20 1 0], [1 2 3], [0; 0; 5]));
vis_leg = vis_base;
vis_leg.projected_output = [];

[ok_leg, err_leg, fig_leg] = tab.visualise_artifacts(vis_leg);
assert(ok_leg, ['visualise_artifacts legacy failed: ' err_leg]);

meta_leg = getappdata(fig_leg, 'reconstruction_panel_metadata');
ax_leg3 = findobj(fig_leg, 'Tag', 'panel_projected');
sub_leg3 = subtitle_text(ax_leg3);

leg_stats_shape_ok = isfield(meta_leg(3).stats, 'assignment_coverage_known') && ...
    isfield(meta_leg(3).stats, 'n_assigned') && isfield(meta_leg(3).stats, 'n_unassigned');
leg_meta_ok = leg_stats_shape_ok && ~meta_leg(3).stats.assignment_coverage_known && ...
    isnan(meta_leg(3).stats.n_assigned) && isnan(meta_leg(3).stats.n_unassigned) && ...
    meta_leg(3).stats.n_zero == 2 && meta_leg(3).stats.n_nonzero == 1;
leg_sub_ok = contains(sub_leg3, 'Activation coverage unknown (legacy format)') && ...
    contains(sub_leg3, '1 / 3 non-zero (2 at 0)');

cb_leg = findobj(fig_leg, 'Type', 'ColorBar');
cb_leg_ok = ~isempty(cb_leg) && norm(double(cb_leg.Limits) - [0 5]) < 1e-6;

record('C7 Legacy ambiguous zero semantics', leg_meta_ok && leg_sub_ok && cb_leg_ok, ...
    sprintf('status=%s semantics=%s coverage_known=%s n_zero=%s n_nonzero=%s sub_ok=%s cb_clim=%s detail=%s', ...
    meta_leg(3).render_status, meta_leg(3).activation_semantics, tf(leg_stats_shape_ok && meta_leg(3).stats.assignment_coverage_known), ...
    numeric_field(meta_leg(3).stats, 'n_zero'), numeric_field(meta_leg(3).stats, 'n_nonzero'), ...
    tf(leg_sub_ok), tf(cb_leg_ok), meta_leg(3).render_detail));

if isgraphics(fig_leg), close(fig_leg); end

% -------------------------------------------------------------------------
% Check 8: All-zero neutral shading
% -------------------------------------------------------------------------
write_text_utf8(projected_path, mesh_with_scalar_ply([20 0 0; 21 0 0; 20 1 0], [1 2 3], [0; 0; 0]));
vis_zero = vis_base;
vis_zero.projected_output = [];

[ok_z, err_z, fig_z] = tab.visualise_artifacts(vis_zero);
assert(ok_z, ['visualise_artifacts all-zero failed: ' err_z]);

ax_z3 = findobj(fig_z, 'Tag', 'panel_projected');
sub_z3 = subtitle_text(ax_z3);

zero_sub_ok = contains(sub_z3, 'all 3 scalar values are 0 (neutral shading)') && ...
    contains(sub_z3, '0 / 3 non-zero');

p_obj = findobj(ax_z3, 'Type', 'patch');
zero_patch_ok = false;
if ~isempty(p_obj)
    p1 = p_obj(1);
    fc = p1.FaceColor;
    if isnumeric(fc) && numel(fc) == 3
        zero_patch_ok = (fc(1) == fc(2) && fc(2) == fc(3));
    elseif ischar(fc) && (strcmp(fc, 'flat') || strcmp(fc, 'interp'))
        cdata = p1.FaceVertexCData;
        zero_patch_ok = all(cdata == cdata(1));
    end
end

record('C8 All-zero neutral shading', zero_sub_ok && zero_patch_ok, ...
    sprintf('sub_ok=%s patch_neutral=%s', tf(zero_sub_ok), tf(zero_patch_ok)));

if isgraphics(fig_z), close(fig_z); end

% -------------------------------------------------------------------------
% Check 9: Missing panel placeholders and spatial bounds safety
% -------------------------------------------------------------------------
vis_miss = vis_base;
vis_miss.fused_ply = fullfile(out_dir, 'missing-file.ply');
vis_miss.rebuilt_ply = ''; % Not yet produced

[ok_m, err_m, fig_m] = tab.visualise_artifacts(vis_miss);
assert(ok_m, ['visualise_artifacts missing panels failed: ' err_m]);

meta_m = getappdata(fig_m, 'reconstruction_panel_metadata');
ax_mf = findobj(fig_m, 'Tag', 'panel_fused');
ax_mr = findobj(fig_m, 'Tag', 'panel_rebuilt');
ax_mp = findobj(fig_m, 'Tag', 'panel_projected');

status_m_ok = strcmp(meta_m(1).render_status, 'MISSING') && ...
    strcmp(meta_m(2).render_status, 'NOT_YET_PRODUCED') && ...
    strcmp(meta_m(3).render_status, 'READY');

% Verify placeholder text
txt_f = findobj(ax_mf, 'Type', 'text');
txt_r = findobj(ax_mr, 'Type', 'text');
placeholders_ok = ~isempty(txt_f) && any(contains(string(get(txt_f(1), 'String')), 'MISSING')) && ...
    ~isempty(txt_r) && any(contains(string(get(txt_r(1), 'String')), 'NOT YET PRODUCED'));

% Verify 3D view on placeholder axes
[az_f, el_f] = view(ax_mf);
view_3d_ok = (az_f == -37.5 && el_f == 30);

% Verify spatial limits match between placeholder and valid projected panel
xlim_match = isequal(xlim(ax_mf), xlim(ax_mp));
ylim_match = isequal(ylim(ax_mf), ylim(ax_mp));
zlim_match = isequal(zlim(ax_mf), zlim(ax_mp));
limits_ok = xlim_match && ylim_match && zlim_match;

% Verify non-READY subtitles include role_description
sub_mf = subtitle_text(ax_mf);
sub_mr = subtitle_text(ax_mr);
sub_role_ok = contains(sub_mf, 'Pre-cleanup stereo fusion point cloud') && ...
    contains(sub_mr, 'Surface mesh made from the dense cloud');

record('C9 Missing panel placeholders and bounds sharing', ...
    status_m_ok && placeholders_ok && view_3d_ok && limits_ok && sub_role_ok, ...
    sprintf('status=%s placeholders=%s view3d=%s limits_match=%s sub_role=%s', ...
    tf(status_m_ok), tf(placeholders_ok), tf(view_3d_ok), tf(limits_ok), tf(sub_role_ok)));

if isgraphics(fig_m), close(fig_m); end

% A valid run with no renderable artefact still yields three diagnostic
% placeholders, with no unsupported physical-unit claim.
vis_none = vis_base;
vis_none.fused_ply = fullfile(out_dir, 'missing-fused.ply');
vis_none.rebuilt_ply = fullfile(out_dir, 'missing-rebuilt.ply');
vis_none.projected_ply = fullfile(reproj_dir, 'missing-projected.ply');
[ok_none, err_none, fig_none] = tab.visualise_artifacts(vis_none);
assert(ok_none, ['all-placeholder visualisation failed: ' err_none]);
meta_none = getappdata(fig_none, 'reconstruction_panel_metadata');
axes_none = [findobj(fig_none, 'Tag', 'panel_fused'), ...
    findobj(fig_none, 'Tag', 'panel_rebuilt'), findobj(fig_none, 'Tag', 'panel_projected')];
placeholder_count = 0;
units_ok = true;
for ai = 1:numel(axes_none)
    placeholder_count = placeholder_count + ~strcmp(meta_none(ai).render_status, 'READY');
    units_ok = units_ok && contains(axes_none(ai).XLabel.String, 'model units') && ...
        contains(axes_none(ai).YLabel.String, 'model units') && ...
        contains(axes_none(ai).ZLabel.String, 'model units');
end
record('C9b All-non-ready run renders three truthful placeholders', ...
    numel(axes_none) == 3 && placeholder_count == 3 && units_ok, ...
    sprintf('axes=%d placeholders=%d model_units=%s', numel(axes_none), placeholder_count, tf(units_ok)));
if isgraphics(fig_none), close(fig_none); end

% -------------------------------------------------------------------------
% Check 10: Incompatible / malformed PLY fail-closed
% -------------------------------------------------------------------------
bad_path = fullfile(out_dir, 'corrupt.ply');
write_text_utf8(bad_path, sprintf('ply\nformat ascii 1.0\nelement vertex 100\nproperty float x\nend_header\n0\n'));
vis_bad = vis_base;
vis_bad.fused_ply = bad_path;

[ok_b, err_b, fig_b] = tab.visualise_artifacts(vis_bad);
assert(ok_b, ['visualise_artifacts bad PLY failed: ' err_b]);

meta_b = getappdata(fig_b, 'reconstruction_panel_metadata');
ax_bf = findobj(fig_b, 'Tag', 'panel_fused');
txt_bf = findobj(ax_bf, 'Type', 'text');

bad_ok = strcmp(meta_b(1).render_status, 'INCOMPATIBLE') && ...
    ~isempty(txt_bf) && any(contains(string(get(txt_bf(1), 'String')), 'INCOMPATIBLE')) && ...
    strcmp(meta_b(2).render_status, 'READY') && strcmp(meta_b(3).render_status, 'READY');

record('C10 Incompatible PLY fail-closed handling', bad_ok, ...
    sprintf('status1=%s status2=%s status3=%s', meta_b(1).render_status, meta_b(2).render_status, meta_b(3).render_status));

if isgraphics(fig_b), close(fig_b); end

% -------------------------------------------------------------------------
% Check 11: Face-free mesh handling
% -------------------------------------------------------------------------
ff_rebuilt = fullfile(out_dir, 'ff-rebuilt.ply');
write_text_utf8(ff_rebuilt, sprintf(['ply\nformat ascii 1.0\nelement vertex 3\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face 0\nproperty list uchar int vertex_indices\nend_header\n' ...
    '10 0 0\n11 0 0\n10 1 0\n']));
vis_ff = vis_base;
vis_ff.rebuilt_ply = ff_rebuilt;

[ok_ff, err_ff, fig_ff] = tab.visualise_artifacts(vis_ff);
assert(ok_ff, ['visualise_artifacts face-free rebuilt failed: ' err_ff]);

meta_ff = getappdata(fig_ff, 'reconstruction_panel_metadata');
ax_ff2 = findobj(fig_ff, 'Tag', 'panel_rebuilt');
sub_ff2 = subtitle_text(ax_ff2);

ff_ok = strcmp(meta_ff(2).render_status, 'READY') && meta_ff(2).stats.n_faces == 0 && ...
    contains(sub_ff2, '(point cloud)');

record('C11 Face-free mesh rendering', ff_ok, ...
    sprintf('status=%s faces=%d sub_has_0_faces=%s', meta_ff(2).render_status, meta_ff(2).stats.n_faces, tf(contains(sub_ff2, '(point cloud)'))));

if isgraphics(fig_ff), close(fig_ff); end

% -------------------------------------------------------------------------
% Check 12: In-run security boundary enforcement
% -------------------------------------------------------------------------
esc_path = fullfile(root, 'outside_run.ply');
write_text_utf8(esc_path, point_cloud_ply());
vis_esc = vis_base;
vis_esc.fused_ply = esc_path;

[ok_esc, err_esc, fig_esc] = tab.visualise_artifacts(vis_esc);
assert(ok_esc, ['visualise_artifacts outside-run failed: ' err_esc]);

meta_esc = getappdata(fig_esc, 'reconstruction_panel_metadata');
ax_escf = findobj(fig_esc, 'Tag', 'panel_fused');
txt_escf = findobj(ax_escf, 'Type', 'text');

esc_ok = strcmp(meta_esc(1).render_status, 'INCOMPATIBLE') && ...
    ~isempty(txt_escf) && any(contains(lower(string(get(txt_escf(1), 'String'))), 'outside the run folder'));

record('C12 In-run security boundary enforcement', esc_ok, ...
    sprintf('status=%s has_security_text=%s', meta_esc(1).render_status, tf(esc_ok)));

if isgraphics(fig_esc), close(fig_esc); end

% Restore the valid sidecar and use a fresh resolver for v2 immutability.
write_text_utf8(v2_path, v2_bytes);
tab = rabbit_reconstruction_tab();
tab.load_state(root, 'test');

% -------------------------------------------------------------------------
% Check 13: Strict byte immutability across open, resolve, and close
% -------------------------------------------------------------------------
protected_artifacts = {fused_path, rebuilt_path, projected_path};
before_hashes = cellfun(@sha256f, protected_artifacts, 'UniformOutput', false);
before_manifest_hash = sha256f(v2_path);

[res_ok, res_err, vis_res] = tab.resolve_visualisation_context(run_id);
assert(res_ok, ['resolve_visualisation_context failed: ' res_err]);
[sh_ok, sh_err, fig_imm] = tab.visualise_artifacts(vis_res);
assert(sh_ok, ['visualise_artifacts immutable failed: ' sh_err]);

% Close via tab.close_visualisation
tab.close_visualisation(fig_imm);

after_hashes = cellfun(@sha256f, protected_artifacts, 'UniformOutput', false);
after_manifest_hash = sha256f(v2_path);
artifacts_unchanged = isequal(before_hashes, after_hashes);
camera_persisted = ~strcmp(before_manifest_hash, after_manifest_hash);

record('C13 Artifact bytes unchanged; v2 close persists camera only', ...
    artifacts_unchanged && camera_persisted, ...
    sprintf('artifacts_unchanged=%s camera_persisted=%s', ...
    tf(artifacts_unchanged), tf(camera_persisted)));

% Legacy measured-output checks use a v1-only source and a fresh resolver.
delete(v2_path);
tab = rabbit_reconstruction_tab();
tab.load_state(root, 'test');

% -------------------------------------------------------------------------
% Check 14: Portable acceptance fixtures, rendered through production code
% -------------------------------------------------------------------------
fixture_root = om_test_getenv('OM_TEST_VISUALISE_FIXTURE_ROOT');
if isempty(fixture_root)
    fixture_root = fullfile(repo_dir, 'tests', 'fixtures', 'reproj-recon', 'staging');
end
r1_fix = fullfile(fixture_root, 'r1_4', 'subset.matom', 'reconstruction', 'runs', ...
    '20260909T110043_d091bb44', 'outputs', 'reprojection', 'activation_projected.ply');
r2_fix = fullfile(fixture_root, 'r2_4', 'reprojection', 'activation_projected.ply');
if (exist(r1_fix, 'file') ~= 2 || exist(r2_fix, 'file') ~= 2) && isempty(om_test_getenv('OM_TEST_VISUALISE_FIXTURE_ROOT'))
    % The measured fixtures are not in the repository
    fprintf(['SKIP C14: the measured fixtures r1_4 and r2_4 were not found under tests/fixtures; ' ...
        'set OM_TEST_VISUALISE_FIXTURE_ROOT to the folder holding them.\n']);
    skip = skip + 1;
elseif exist(r1_fix, 'file') ~= 2 || exist(r2_fix, 'file') ~= 2
    fprintf('PROBE_INCOMPLETE C14 required fixtures unavailable; set OM_TEST_VISUALISE_FIXTURE_ROOT.\n');
    error('probe_visualise_captions:FixtureUnavailable', ...
        'C3.1 acceptance requires both measured fixtures under OM_TEST_VISUALISE_FIXTURE_ROOT.');
else
    original_hashes = {sha256f(r1_fix), sha256f(r2_fix)};
    fixture_tmp = fullfile(run_dir, 'outputs', 'reprojection', 'acceptance-copies');
    mkdir(fixture_tmp);
    r1_copy = fullfile(fixture_tmp, 'golden-activation.ply');
    r2_copy = fullfile(fixture_tmp, 'real-activation.ply');
    copyfile(r1_fix, r1_copy);
    copyfile(r2_fix, r2_copy);
    rendered = false(1, 2);
    visible = cell(1, 2);
    meta_counts = false(1, 2);
    copies = {r1_copy, r2_copy};
    expected_copy = {'0 / 16,781', '924 / 16,781'};
    expected_nz = [0, 924];
    for fi = 1:2
        fvis = vis_base;
        fvis.projected_ply = copies{fi};
        [fok, ferr, ffig] = tab.visualise_artifacts(fvis);
        if fok
            fax = findobj(ffig, 'Tag', 'panel_projected');
            visible{fi} = subtitle_text(fax);
            fm = getappdata(ffig, 'reconstruction_panel_metadata');
            rendered(fi) = contains(visible{fi}, expected_copy{fi});
            meta_counts(fi) = fm(3).stats.n_vertices == 16781 && ...
                fm(3).stats.n_nonzero == expected_nz(fi);
            close(ffig);
        else
            visible{fi} = ferr;
        end
    end
    originals_unchanged = strcmp(original_hashes{1}, sha256f(r1_fix)) && ...
        strcmp(original_hashes{2}, sha256f(r2_fix));
    record('C14 Actual golden/real fixtures render exact visible denominators', ...
        all(rendered) && all(meta_counts) && originals_unchanged, ...
        sprintf('golden="%s" real="%s" originals_unchanged=%s', ...
        expected_copy{1}, expected_copy{2}, tf(originals_unchanged)));
end

% -------------------------------------------------------------------------
% Check 15: Intermediate run resolution and defensive format count
% -------------------------------------------------------------------------
fmt_nan_ok = strcmp(tab.format_count(NaN), 'NaN') && ...
    strcmp(tab.format_count([]), 'NaN');

% Create an intermediate run with only fused and rebuilt (reprojection not yet executed)
int_run_id = '20260913T000000_intermediate';
int_dir = fullfile(root, 'test.matom', 'reconstruction', 'runs', int_run_id);
int_out = fullfile(int_dir, 'outputs');
mkdir(int_out);
write_text_utf8(fullfile(int_out, 'fused-geometric.ply'), point_cloud_ply());
write_text_utf8(fullfile(int_out, 'alignment-rebuilt-mesh.ply'), mesh_ply());
int_manifest = valid_v1(int_run_id, root, 'RUNNING');
int_manifest.stages = [struct('name', 'stereo_fusion', 'status', 'PASSED'), ...
    struct('name', 'mesh_cleanup', 'status', 'PASSED')];
write_text_utf8(fullfile(int_dir, 'manifest.json'), jsonencode(int_manifest));

[int_res_ok, int_res_err, int_vis] = tab.resolve_visualisation_context(int_run_id);
int_vis_ok = false;
if int_res_ok
    [int_v_ok, int_v_err, int_fig] = tab.visualise_artifacts(int_vis);
    if int_v_ok
        int_meta = getappdata(int_fig, 'reconstruction_panel_metadata');
        int_vis_ok = strcmp(int_meta(1).render_status, 'READY') && ...
            strcmp(int_meta(2).render_status, 'READY') && ...
            strcmp(int_meta(3).render_status, 'NOT_YET_PRODUCED');
        if isgraphics(int_fig), close(int_fig); end
    end
end

record('C15 Intermediate run resolution and defensive format count', ...
    fmt_nan_ok && int_res_ok && int_vis_ok, ...
    sprintf('fmt_nan=%s int_resolve=%s int_vis=%s', tf(fmt_nan_ok), tf(int_res_ok), tf(int_vis_ok)));

% -------------------------------------------------------------------------
% Check 16: Arbitrary scalar properties are explicitly unverified
% -------------------------------------------------------------------------
confidence_path = fullfile(reproj_dir, 'confidence_projected.ply');
write_text_utf8(confidence_path, mesh_with_named_scalar_ply( ...
    [20 0 0; 21 0 0; 20 1 0], [1 2 3], [0.2; 0.6; 0.9], 'confidence'));
vis_conf = vis_base;
vis_conf.projected_ply = confidence_path;
[conf_ok, conf_err, conf_fig] = tab.visualise_artifacts(vis_conf);
conf_meta = getappdata(conf_fig, 'reconstruction_panel_metadata');
conf_ax = findobj(conf_fig, 'Tag', 'panel_projected');
conf_copy = subtitle_text(conf_ax);
conf_title = char(get(get(conf_ax, 'Title'), 'String'));
conf_cb = findobj(conf_fig, 'Type', 'ColorBar');
conf_cb_copy = '';
if ~isempty(conf_cb), conf_cb_copy = char(conf_cb(1).Label.String); end
conf_truth = conf_ok && strcmp(conf_meta(3).activation_semantics, 'UNVERIFIED_SCALAR') && ...
    contains(conf_copy, 'Unverified scalar') && contains(conf_copy, 'confidence') && ...
    strcmp(conf_title, 'Projected values') && ...
    ~contains(lower(conf_copy), 'activation time') && ~contains(lower(conf_cb_copy), 'activation') && ...
    ~contains(lower(conf_cb_copy), '(ms)');
record('C16 Confidence scalar is not labelled as activation time', conf_truth, ...
    sprintf('semantics=%s title=%s subtitle=%s colorbar=%s err=%s', ...
    conf_meta(3).activation_semantics, conf_title, conf_copy, conf_cb_copy, conf_err));
if isgraphics(conf_fig), close(conf_fig); end

% -------------------------------------------------------------------------
% Check 17: Existing and absent external paths are incompatible and suppressed
% -------------------------------------------------------------------------
ext_existing = fullfile(root, 'external-existing.ply');
write_text_utf8(ext_existing, point_cloud_ply());
ext_absent = fullfile(root, 'external-absent.ply');
ext_vis = vis_base;
ext_vis.fused_ply = ext_existing;
[ext_ok1, ~, ext_fig1] = tab.visualise_artifacts(ext_vis);
ext_meta1 = getappdata(ext_fig1, 'reconstruction_panel_metadata');
ext_sub1 = subtitle_text(findobj(ext_fig1, 'Tag', 'panel_fused'));
ext_vis.fused_ply = ext_absent;
[ext_ok2, ~, ext_fig2] = tab.visualise_artifacts(ext_vis);
ext_meta2 = getappdata(ext_fig2, 'reconstruction_panel_metadata');
ext_sub2 = subtitle_text(findobj(ext_fig2, 'Tag', 'panel_fused'));
ext_truth = ext_ok1 && ext_ok2 && ...
    strcmp(ext_meta1(1).render_status, 'INCOMPATIBLE') && ...
    strcmp(ext_meta2(1).render_status, 'INCOMPATIBLE') && ...
    isempty(ext_meta1(1).source_path) && isempty(ext_meta2(1).source_path) && ...
    strcmp(ext_meta1(1).source_display, '[hidden: outside the run folder]') && ...
    strcmp(ext_meta2(1).source_display, '[hidden: outside the run folder]') && ...
    ~contains(ext_sub1, ext_existing) && ~contains(ext_sub2, ext_absent);
record('C17 External existing/absent sources are blocked and path-suppressed', ...
    ext_truth, sprintf('existing=%s absent=%s', ...
    ext_meta1(1).render_status, ext_meta2(1).render_status));
if isgraphics(ext_fig1), close(ext_fig1); end
if isgraphics(ext_fig2), close(ext_fig2); end

% -------------------------------------------------------------------------
% Check 18: A stale v2 sidecar cannot supply camera or projected-output wires
% -------------------------------------------------------------------------
stale_id = '20260913T130000_stalev2';
stale_root = fullfile(root, 'stale-dataset');
stale_dir = fullfile(stale_root, 'stale.matom', 'reconstruction', 'runs', stale_id);
stale_out = fullfile(stale_dir, 'outputs');
mkdir(fullfile(stale_out, 'reprojection'));
copyfile(fused_path, fullfile(stale_out, 'fused-geometric.ply'));
copyfile(rebuilt_path, fullfile(stale_out, 'alignment-rebuilt-mesh.ply'));
copyfile(projected_path, fullfile(stale_out, 'reprojection', 'activation_projected.ply'));
stale_v1_path = fullfile(stale_dir, 'manifest.json');
stale_v1 = valid_v1(stale_id, stale_root, 'FAILED');
write_text_utf8(stale_v1_path, jsonencode(stale_v1, 'PrettyPrint', true));
stale_builder = rabbit_reconstruction_tab();
[stale_bytes, ~] = stale_builder.convert_v1_to_v2(stale_v1_path, stale_dir);
stale_v2_path = fullfile(stale_dir, 'manifest.v2.json');
write_text_utf8(stale_v2_path, stale_bytes);
[stale_cam_ok, stale_cam_err, stale_camera] = stale_builder.validate_camera_state(camera_state([91 92 93]));
[stale_activation, stale_activation_err] = activation_state_with_projection(stale_builder, [10; 20; 30]);
[stale_origin_ok, stale_origin_sha, stale_origin_err] = stale_builder.manifest_bytes_sha256(stale_v2_path);
assert(stale_cam_ok, stale_cam_err);
assert(isempty(stale_activation_err), stale_activation_err);
assert(stale_origin_ok, stale_origin_err);
[stale_persist_ok, stale_persist_err] = stale_builder.persist_restore_fields( ...
    stale_dir, stale_activation, stale_camera, stale_origin_sha, '0');
assert(stale_persist_ok, stale_persist_err);
stale_v1.result.status = 'CANCELLED';
write_text_utf8(stale_v1_path, jsonencode(stale_v1, 'PrettyPrint', true));
stale_tab = rabbit_reconstruction_tab();
stale_tab.load_state(stale_root, 'stale');
[stale_ok, stale_err, stale_vis] = stale_tab.resolve_visualisation_context(stale_id);
[stale_pm_ok, ~, stale_panels] = stale_tab.visualisation_panel_model(stale_vis);
stale_truth = stale_ok && stale_pm_ok && strcmp(stale_vis.open_kind, 'STALE_V2') && ...
    strcmp(stale_vis.active_manifest_schema, 'cd2.reconstruction.manifest.v1') && ...
    isempty(stale_vis.projected_output) && isempty(stale_vis.camera_origin_sha256) && ...
    isstruct(stale_vis.camera_state) && ~strcmp(stale_vis.camera_state.status, 'AVAILABLE') && ...
    strcmp(stale_panels(3).activation_semantics, 'LEGACY_ZERO_AMBIGUOUS');
record('C18 Stale v2 camera/projected-output wires are never consumed', stale_truth, ...
    sprintf('kind=%s schema=%s projected_empty=%s origin_empty=%s err=%s', ...
    stale_vis.open_kind, stale_vis.active_manifest_schema, tf(isempty(stale_vis.projected_output)), ...
    tf(isempty(stale_vis.camera_origin_sha256)), stale_err));

% A current authoritative mutation state suppresses an older projected PLY.
write_text_utf8(v2_path, v2_bytes);
tab = rabbit_reconstruction_tab();
tab.load_state(root, 'test');
[pending_state_ok, pending_state_err, pending_activation] = ...
    tab.mark_activation_mutation_pending(wire_zero);
assert(pending_state_ok, pending_state_err);
[pending_write_ok, pending_write_err] = tab.write_active_manifest(run_dir, ...
    @(m) set_activation_restore(m, pending_activation));
assert(pending_write_ok, pending_write_err);
vis_pending = vis_base;
vis_pending.active_manifest_path = v2_path;
[pending_ok, ~, pending_panels] = tab.visualisation_panel_model(vis_pending);
pending_truth = pending_ok && ...
    strcmp(pending_panels(3).render_status, 'NOT_YET_PRODUCED') && ...
    strcmp(pending_panels(3).activation_semantics, 'UNAVAILABLE') && ...
    contains(pending_panels(3).render_detail, 'Existing projected PLY is not current');
record('C18b Authoritative pending state suppresses stale projected PLY', ...
    pending_truth, pending_panels(3).render_detail);
write_text_utf8(v2_path, v2_bytes);

% -------------------------------------------------------------------------
% Check 19: Real App Designer manual entry renders trusted partial placeholders
% -------------------------------------------------------------------------
partial_id = '20260913T140000_partial';
partial_root = fullfile(root, 'partial-dataset');
partial_dir = fullfile(partial_root, 'partial.matom', 'reconstruction', 'runs', partial_id);
partial_out = fullfile(partial_dir, 'outputs');
mkdir(fullfile(partial_out, 'reprojection'));
write_text_utf8(fullfile(partial_out, 'fused-geometric.ply'), point_cloud_ply());
write_text_utf8(fullfile(partial_out, 'reprojection', 'activation_projected.ply'), ...
    sprintf('ply\nformat ascii 1.0\nelement vertex 9\nproperty float x\nend_header\n'));
partial_v1_path = fullfile(partial_dir, 'manifest.json');
write_text_utf8(partial_v1_path, jsonencode(valid_v1(partial_id, partial_root, 'RUNNING'), ...
    'PrettyPrint', true));
partial_app = analyse_optical_mapping;
partial_app.recon.test_manifest_pick = partial_v1_path;
partial_app.recon.OpenReconstructionManifestMenuSelected();
partial_app.recon.ReconstructionRunList.Value = partial_app.recon.ReconstructionRunList.Items{1};
partial_app.recon.reconstruction_update_enablement();
partial_enabled = strcmp(partial_app.recon.ReconstructionVisualiseButton.Enable, 'on');
path_labels_ok = strcmp(partial_app.recon.VisualiseFusedLabel.Text, 'Fused point cloud path') && ...
    strcmp(partial_app.recon.VisualiseRebuiltLabel.Text, 'Mesh path') && ...
    strcmp(partial_app.recon.VisualiseProjectedLabel.Text, 'Projected activation path');
partial_app.recon.ReconstructionVisualiseButtonPushed();
drawnow;
partial_fig = find_visualisation_figure(partial_id);
partial_meta = struct([]);
partial_states = 'no figure';
partial_entry_truth = false;
if ~isempty(partial_fig)
    partial_meta = getappdata(partial_fig, 'reconstruction_panel_metadata');
    partial_states = sprintf('%s/%s/%s', partial_meta(1).render_status, ...
        partial_meta(2).render_status, partial_meta(3).render_status);
    partial_entry_truth = partial_enabled && path_labels_ok && ...
        strcmp(partial_meta(1).render_status, 'READY') && ...
        strcmp(partial_meta(2).render_status, 'MISSING') && ...
        strcmp(partial_meta(3).render_status, 'INCOMPATIBLE') && ...
        contains(axis_text(partial_fig, 'panel_rebuilt'), 'MISSING') && ...
        contains(axis_text(partial_fig, 'panel_projected'), 'INCOMPATIBLE');
end
partial_status = strjoin(partial_app.recon.VisualiseStatusText.Value, ' ');
record('C19 App Designer manual entry reaches trusted partial placeholders', ...
    partial_entry_truth, sprintf('enabled=%s labels=%s states=%s status=%s', ...
    tf(partial_enabled), tf(path_labels_ok), partial_states, partial_status));
if ~isempty(partial_fig) && isgraphics(partial_fig), close(partial_fig); end
if isvalid(partial_app), delete(partial_app); end

% The real App Designer callback must also show the diagnostic figure when
% every artefact role is non-ready.
none_id = '20260913T145000_none';
none_dir = fullfile(partial_root, 'partial.matom', 'reconstruction', 'runs', none_id);
mkdir(fullfile(none_dir, 'outputs', 'reprojection'));
none_manifest_path = fullfile(none_dir, 'manifest.json');
write_text_utf8(none_manifest_path, jsonencode(valid_v1(none_id, partial_root, 'RUNNING'), ...
    'PrettyPrint', true));
none_app = analyse_optical_mapping;
none_app.recon.test_manifest_pick = none_manifest_path;
none_app.recon.OpenReconstructionManifestMenuSelected();
none_idx = find(contains(string(none_app.recon.ReconstructionRunList.Items), none_id), 1, 'first');
assert(~isempty(none_idx), 'all-missing run was not listed');
none_app.recon.ReconstructionRunList.Value = none_app.recon.ReconstructionRunList.Items{none_idx};
none_app.recon.reconstruction_update_enablement();
none_enabled = strcmp(none_app.recon.ReconstructionVisualiseButton.Enable, 'on');
none_app.recon.ReconstructionVisualiseButtonPushed();
drawnow;
none_fig = find_visualisation_figure(none_id);
none_entry_truth = false;
none_states = 'no figure';
if ~isempty(none_fig)
    none_meta = getappdata(none_fig, 'reconstruction_panel_metadata');
    none_states = sprintf('%s/%s/%s', none_meta(1).render_status, ...
        none_meta(2).render_status, none_meta(3).render_status);
    none_entry_truth = none_enabled && all(~strcmp({none_meta.render_status}, 'READY'));
end
none_status = strjoin(none_app.recon.VisualiseStatusText.Value, ' ');
record('C19b App Designer entry renders all-non-ready diagnostic figure', ...
    none_entry_truth, sprintf('enabled=%s states=%s status=%s', ...
    tf(none_enabled), none_states, none_status));
if ~isempty(none_fig) && isgraphics(none_fig), close(none_fig); end
if isvalid(none_app), delete(none_app); end

% -------------------------------------------------------------------------
% Check 20: Manual/automatic camera origin and close/reopen persistence symmetry
% -------------------------------------------------------------------------
cam_id = '20260913T150000_c0ffee12';
cam_root = fullfile(root, 'camera-dataset');
cam_dir = fullfile(cam_root, 'camera.matom', 'reconstruction', 'runs', cam_id);
cam_out = fullfile(cam_dir, 'outputs');
mkdir(fullfile(cam_out, 'reprojection'));
write_text_utf8(fullfile(cam_out, 'fused-geometric.ply'), point_cloud_ply());
write_text_utf8(fullfile(cam_out, 'alignment-rebuilt-mesh.ply'), mesh_ply());
write_text_utf8(fullfile(cam_out, 'reprojection', 'activation_projected.ply'), ...
    mesh_with_scalar_ply([20 0 0; 21 0 0; 20 1 0], [1 2 3], [1; 2; 3]));
cam_v1_path = fullfile(cam_dir, 'manifest.json');
cam_v1 = valid_v1(cam_id, cam_root, 'FAILED');
cam_v1.stages = struct('name', 'stereo_fusion', 'status', 'PASSED');
write_text_utf8(cam_v1_path, jsonencode(cam_v1, 'PrettyPrint', true));
cam_builder = rabbit_reconstruction_tab();
[cam_bytes, ~] = cam_builder.convert_v1_to_v2(cam_v1_path, cam_dir);
cam_v2_path = fullfile(cam_dir, 'manifest.v2.json');
write_text_utf8(cam_v2_path, cam_bytes);
cam_tab = rabbit_reconstruction_tab();
cam_tab.load_state(cam_root, 'camera');
[cam_ctx_ok, cam_ctx_err, cam_vis] = cam_tab.resolve_visualisation_context(cam_id);
[manual_ok, manual_err, manual_fig] = cam_tab.visualise_artifacts(cam_vis);
manual_axes = getappdata(manual_fig, 'reconstruction_axes_handles');
set(manual_axes(1), 'CameraPosition', [7 8 9]); drawnow;
manual_origin = getappdata(manual_fig, 'reconstruction_camera_origin_sha256');
manual_revision = getappdata(manual_fig, 'reconstruction_camera_origin_revision');
[manual_capture_valid, manual_capture_err] = ...
    cam_tab.validate_camera_state(cam_tab.capture_camera_state(manual_axes));
lastwarn('');
cam_tab.close_visualisation(manual_fig);
[manual_close_warning, manual_close_warning_id] = lastwarn;
cam_tab2 = rabbit_reconstruction_tab();
cam_tab2.load_state(cam_root, 'camera');
[reopen_ok, reopen_err, reopen_vis] = cam_tab2.resolve_visualisation_context(cam_id);
[reopen_show_ok, reopen_show_err, reopen_fig] = cam_tab2.visualise_artifacts(reopen_vis);
reopen_axes = getappdata(reopen_fig, 'reconstruction_axes_handles');
reopen_position = get(reopen_axes(1), 'CameraPosition');
reopen_restore_status = getappdata(reopen_fig, 'reconstruction_camera_restore_status');
manual_persisted = all(abs(reopen_position - [7 8 9]) < 1e-9);
auto_app = analyse_optical_mapping;
auto_app.recon.test_manifest_pick = cam_v2_path;
auto_app.recon.OpenReconstructionManifestMenuSelected();
drawnow;
auto_fig = find_visualisation_figure(cam_id, reopen_fig);
auto_origin = '';
auto_restored = false;
if ~isempty(auto_fig)
    auto_origin = getappdata(auto_fig, 'reconstruction_camera_origin_sha256');
    auto_axes = getappdata(auto_fig, 'reconstruction_axes_handles');
    auto_restored = all(abs(get(auto_axes(1), 'CameraPosition') - [7 8 9]) < 1e-9);
    set(auto_axes(1), 'CameraPosition', [11 12 13]); drawnow;
    close(auto_fig);
end
auto_status = strjoin(auto_app.recon.VisualiseStatusText.Value, ' ');
cam_tab3 = rabbit_reconstruction_tab();
cam_tab3.load_state(cam_root, 'camera');
[final_ok, final_err, final_vis] = cam_tab3.resolve_visualisation_context(cam_id);
[final_show_ok, final_show_err, final_fig] = cam_tab3.visualise_artifacts(final_vis);
final_axes = getappdata(final_fig, 'reconstruction_axes_handles');
auto_persisted = all(abs(get(final_axes(1), 'CameraPosition') - [11 12 13]) < 1e-9);
cam_truth = cam_ctx_ok && manual_ok && reopen_ok && reopen_show_ok && final_ok && ...
    final_show_ok && manual_capture_valid && isempty(manual_capture_err) && ...
    isempty(manual_close_warning_id) && isempty(manual_close_warning) && ...
    ~isempty(manual_origin) && ~isempty(manual_revision) && ...
    ~isempty(auto_origin) && strcmp(reopen_vis.open_kind, 'VALID_V2') && ...
    strcmp(reopen_vis.camera_state.status, 'AVAILABLE') && ...
    strcmp(reopen_restore_status, 'AVAILABLE') && ...
    manual_persisted && auto_restored && auto_persisted;
record('C20 Manual/automatic camera origin and persistence are symmetric', cam_truth, ...
    sprintf(['manual_origin=%s manual_revision=%s capture_valid=%s reopen=%s/%s ' ...
    'manual_persisted=%s auto_origin=%s auto_restored=%s auto_persisted=%s ' ...
    'errors=%s|%s|%s|%s|%s'], ...
    manual_origin, manual_revision, tf(manual_capture_valid), ...
    reopen_vis.open_kind, reopen_restore_status, tf(manual_persisted), auto_origin, ...
    tf(auto_restored), tf(auto_persisted), cam_ctx_err, manual_err, ...
    reopen_err, reopen_show_err, [final_err final_show_err ' auto_status=' auto_status]));
if isgraphics(reopen_fig), delete(reopen_fig); end
if isgraphics(final_fig), delete(final_fig); end
if isvalid(auto_app), delete(auto_app); end

% -------------------------------------------------------------------------
% Summary
% -------------------------------------------------------------------------
fprintf('PROBE_VISUALISE_CAPTIONS RESULT: %d passed, %d failed, %d skipped-nonpass\n', pass, fail, skip);
if fail == 0
    fprintf('PROBE_OK probe_visualise_captions %d/0 skips=%d\n', pass, skip);
else
    fprintf('PROBE_FAIL probe_visualise_captions\n');
    error('probe_visualise_captions:failed', '%d checks failed', fail);
end

    function record(name, ok, detail)
        fprintf('%s: %s (%s)\n', name, tf(ok), detail);
        if ok, pass = pass + 1; else, fail = fail + 1; end
    end
end

% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------
function [next, result] = set_activation_restore(manifest, activation)
next = manifest;
if ~isfield(next, 'restore') || ~isstruct(next.restore)
    next.restore = struct();
end
next.restore.activation_map = activation;
result = [];
end

function txt = numeric_field(s, name)
if isstruct(s) && isfield(s, name) && isnumeric(s.(name)) && isscalar(s.(name))
    txt = num2str(s.(name));
else
    txt = 'missing';
end
end

function txt = point_cloud_ply()
txt = sprintf(['ply\nformat ascii 1.0\nelement vertex 3\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face 0\nproperty list uchar int vertex_indices\nend_header\n' ...
    '0 0 0\n1 0 0\n0 1 0\n']);
end

function txt = mesh_ply(~, pts, faces)
if nargin < 2, pts = [10 0 0; 11 0 0; 10 1 0]; end
if nargin < 3, faces = [1 2 3]; end
n_v = size(pts, 1);
n_f = size(faces, 1);

pts_str = '';
for k = 1:n_v
    pts_str = [pts_str sprintf('%.6g %.6g %.6g\n', pts(k, 1), pts(k, 2), pts(k, 3))]; %#ok<AGROW>
end

faces_str = '';
for k = 1:n_f
    faces_str = [faces_str sprintf('3 %d %d %d\n', faces(k, 1)-1, faces(k, 2)-1, faces(k, 3)-1)]; %#ok<AGROW>
end

txt = sprintf(['ply\nformat ascii 1.0\nelement vertex %d\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'element face %d\nproperty list uchar int vertex_indices\nend_header\n' ...
    '%s%s'], n_v, n_f, pts_str, faces_str);
end

function txt = mesh_with_scalar_ply(pts, faces, scalars)
n_v = size(pts, 1);
n_f = size(faces, 1);

pts_str = '';
for k = 1:n_v
    pts_str = [pts_str sprintf('%.6g %.6g %.6g %.6g\n', pts(k, 1), pts(k, 2), pts(k, 3), scalars(k))]; %#ok<AGROW>
end

faces_str = '';
for k = 1:n_f
    faces_str = [faces_str sprintf('3 %d %d %d\n', faces(k, 1)-1, faces(k, 2)-1, faces(k, 3)-1)]; %#ok<AGROW>
end

txt = sprintf(['ply\nformat ascii 1.0\nelement vertex %d\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'property float activation\n' ...
    'element face %d\nproperty list uchar int vertex_indices\nend_header\n' ...
    '%s%s'], n_v, n_f, pts_str, faces_str);
end

function txt = mesh_with_named_scalar_ply(pts, faces, scalars, scalar_name)
n_v = size(pts, 1);
n_f = size(faces, 1);
pts_str = '';
for k = 1:n_v
    pts_str = [pts_str sprintf('%.6g %.6g %.6g %.6g\n', ...
        pts(k, 1), pts(k, 2), pts(k, 3), scalars(k))]; %#ok<AGROW>
end
faces_str = '';
for k = 1:n_f
    faces_str = [faces_str sprintf('3 %d %d %d\n', ...
        faces(k, 1)-1, faces(k, 2)-1, faces(k, 3)-1)]; %#ok<AGROW>
end
txt = sprintf(['ply\nformat ascii 1.0\nelement vertex %d\n' ...
    'property float x\nproperty float y\nproperty float z\n' ...
    'property float %s\n' ...
    'element face %d\nproperty list uchar int vertex_indices\nend_header\n' ...
    '%s%s'], n_v, scalar_name, n_f, pts_str, faces_str);
end

function m = valid_v1(run_id, dataset_root, result_status)
m = struct();
m.manifest_schema = 'cd2.reconstruction.manifest.v1';
m.run_id = run_id;
m.state_schema_version = 1;
m.recipe_version = 1;
m.tool_versions = struct();
m.tool_provenance = [];
m.dataset = struct('role', 'reconstruction', 'path', dataset_root);
m.inputs = struct('files', []);
m.fov_mapping = struct();
m.image_discovery = struct();
m.stages = struct('name', {}, 'status', {});
m.deviations = [];
m.resource_checks = [];
m.touchups = [];
m.intensity_filters = [];
m.area_removals = [];
m.smoothings = [];
m.citations = [];
m.result = struct('status', result_status);
end

function camera = camera_state(position)
lim = struct('x', [-1 1], 'y', [-1 1], 'z', [-1 1]);
camera = struct('position', position, 'target', [0 0 0], 'up', [0 0 1], ...
    'view_angle', 45, 'limits', struct('fused', lim, 'rebuilt', lim, 'projected', lim));
end

function [wire, err] = activation_state_with_projection(tab, projected_values, target_digest)
wire = struct();
err = '';
if nargin < 3
    target_digest = repmat('1', 1, 64);
end
map = single([1 NaN; 0 2]);
params = struct('schema', 'method-parameters-v1', 'operation', 'load', ...
    'parent_map_digest', [], 'parent_time_reference', [], ...
    'parameters', struct('kind', 'load', ...
    'source_recording_identity_sha256', repmat('0', 1, 64), ...
    'initial_time_reference', struct('kind', 'relative_to_first_frame', ...
    'anchor_frame', '1', 'applied_offset_ms', '0000000000000000', 'parent', [])));
params_json = tab.jcs_json(params);
projection_digest = repmat('2', 1, 64);
prov = struct('map_kind', 'activation_time', 'units', 'ms', ...
    'method', struct('name', 'activation_time_pipeline', 'version', 'method-v1', ...
    'parameters_json', params_json, 'parameters_sha256', ...
    tab.restore_domain_digest('OM-ACTIVATION-METHOD', 'method-v1', jsondecode(params_json))), ...
    'time_reference', struct('kind', 'relative_to_first_frame', ...
    'anchor_frame', '1', 'applied_offset_ms', '0000000000000000', 'parent', []), ...
    'recording_identity', struct(), 'geometry', struct(), ...
    'geometry_digest', repmat('0', 1, 64), ...
    'projection_contract', struct(), ...
    'projection_contract_digest', projection_digest, ...
    'target_mesh_digest', target_digest);
[ok, err, wire] = tab.validate_activation_state(map, prov);
if ~ok, return; end
[ok, err, projected] = tab.validate_projected_output( ...
    projected_values, target_digest, projection_digest);
if ~ok, wire = struct(); return; end
wire.projected_output = projected;
end

function txt = subtitle_text(ax)
% The caption with Panel details ticked: the short caption and the full text
txt = '';
if isempty(ax), return; end
pd = findobj(ancestor(ax, 'figure'), 'Tag', 'ReconstructionPanelDetails');
if isscalar(pd) && pd.Value == 0
    pd.Value = 1;
    pd.Callback(pd, []);
end
txt = get(get(ax, 'Subtitle'), 'String');
if iscell(txt), txt = strjoin(txt, ' '); end
txt = char(txt);
% Since 24.11.2026 the full text is in a box under the panel
box = findobj(ancestor(ax, 'figure'), 'Tag', ['ReconstructionPanelDetailsText_' extractAfter(ax.Tag, 'panel_')]);
if isscalar(box) && strcmp(box.Visible, 'on')
    txt = [txt ' ' strjoin(cellstr(box.String), ' ')];
end
end

function txt = axis_text(fig, tag)
txt = '';
if isempty(fig), return; end
ax = findobj(fig, 'Tag', tag);
if isempty(ax), return; end
items = findobj(ax, 'Type', 'text');
parts = cell(1, numel(items));
for k = 1:numel(items)
    value = get(items(k), 'String');
    if iscell(value), value = strjoin(value, ' '); end
    parts{k} = char(value);
end
txt = strjoin(parts, ' ');
end

function fig = find_visualisation_figure(run_id, excluded)
if nargin < 2, excluded = []; end
fig = [];
figs = findall(0, 'Type', 'figure');
for k = 1:numel(figs)
    if ~isempty(excluded) && isequal(figs(k), excluded), continue; end
    if endsWith(get(figs(k), 'Name'), ['Reconstruction visualisation - run ' run_id])   % a NOT FOR ANALYSIS prefix first (F13)
        fig = figs(k);
        return;
    end
end
end

function write_text_utf8(path, text)
fid = fopen(path, 'wb');
assert(fid >= 0, 'Could not write UTF-8 file: %s', path);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, unicode2native(text, 'UTF-8'), 'uint8');
end

function h = sha256f(path)
fid = fopen(path, 'rb');
assert(fid >= 0, 'Could not hash file: %s', path);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = fread(fid, Inf, '*uint8');
md = java.security.MessageDigest.getInstance('SHA-256');
digest = md.digest(data);
bytes = typecast(int8(digest), 'uint8');
h = lower(reshape(dec2hex(bytes, 2)', 1, []));
end

function cleanup_case(root)
try close all force; catch, end
if exist(root, 'dir'), rmdir(root, 's'); end
end
