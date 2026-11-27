function probe_segmentation_preview_views
%% Probe: the segmentation preview's title names the view, not the ROI row
% Collin Snitchler
% 24.11.2026
% The naming: View1 is the leftmost region, View2 to
% View4 to its right, as the regions file's view_order says; the cut's
% images are named _view<k> with k the ROI row. The preview's title is
% "<file name> (View<n>)": the file name as it is, n the view of that ROI
% row through view_order. Without a GUI and a cut folder:
%   S1  title_text through the run's order (view2, view3, view1, view4):
%       ROI rows 1-4 give View2, View3, View1, View4, with the file name
%       unchanged
%   S2  row_views_of reads a cell or a "view2; view3; view1; view4" text,
%       and falls back to ROI row k as View k when it cannot
%   S3  the constructor takes view_order from the ROI JSON and rerender
%       titles through title_text (source check; the preview is not built)
% Usage: matlab -batch "addpath('<repo>/tests'); probe_segmentation_preview_views" -noFigureWindows
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
results = struct('id', {}, 'ok', {}, 'detail', {});

%% S1
rv = rabbit_segmentation_preview.row_views_of({'view2', 'view3', 'view1', 'view4'});
names = arrayfun(@(k) sprintf('13h-05m-59s_view%d_frame_0035', k), 1:4, 'UniformOutput', false);
titles = arrayfun(@(k) rabbit_segmentation_preview.title_text(names{k}, k, rv), 1:4, 'UniformOutput', false);
want = {'13h-05m-59s_view1_frame_0035 (View2)', '13h-05m-59s_view2_frame_0035 (View3)', ...
    '13h-05m-59s_view3_frame_0035 (View1)', '13h-05m-59s_view4_frame_0035 (View4)'};
results = add(results, 'S1 the title names the mapped view, the file name unchanged', isequal(titles, want), ...
    strjoin(titles, ' | '));

%% S2
r_text = rabbit_segmentation_preview.row_views_of('view2; view3; view1; view4');
r_bad = rabbit_segmentation_preview.row_views_of({'view2', 'view2', 'view1', 'view4'});
r_none = rabbit_segmentation_preview.row_views_of([]);
results = add(results, 'S2 view_order as a list or text; ROI row k as View k when unusable', ...
    isequal(r_text, [2 3 1 4]) && isequal(r_bad, 1:4) && isequal(r_none, 1:4), ...
    sprintf('%s %s %s', mat2str(r_text), mat2str(r_bad), mat2str(r_none)));

%% S3
src = fileread(fullfile(repo, 'rabbit_segmentation_preview.m'));
results = add(results, 'S3 the constructor reads view_order; rerender titles through title_text', ...
    contains(src, 'obj.row_views = rabbit_segmentation_preview.row_views_of(payload.view_order);') && ...
    contains(src, 'obj.TitleLabel.Text = rabbit_segmentation_preview.title_text(fname, v, obj.row_views);') && ...
    ~contains(src, '(view %d)'), '');

%% Summary
n_pass = sum([results.ok]);
for k = 1:numel(results)
    if results(k).ok, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('%s %s: %s\n', tag, results(k).id, results(k).detail);
end
fprintf('\nPROBE_SEGMENTATION_PREVIEW_VIEWS RESULT: %d passed, %d failed\n', n_pass, numel(results) - n_pass);
if n_pass ~= numel(results)
    error('probe_segmentation_preview_views:Failed', '%d check(s) failed.', numel(results) - n_pass);
end
fprintf('PROBE_OK probe_segmentation_preview_views %d/0\n', n_pass);
end


function r = add(r, id, ok, detail)
r(end + 1) = struct('id', id, 'ok', logical(ok), 'detail', detail);
end
