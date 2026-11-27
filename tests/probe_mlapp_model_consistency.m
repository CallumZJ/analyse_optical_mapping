function probe_mlapp_model_consistency(varargin)
%% Probe: an App Designer save would write back the same code (every .mlapp)
% Collin Snitchler
% 23.11.2026
% App Designer's save writes an app's code again from the model inside the
% .mlapp (appdesigner/appModel.mat), not from the code (matlab/document.xml).
% For each .mlapp in the repository this probe rebuilds, headless, the code
% App Designer would write from the model (tests/helpers/mlapp_model_code.m)
% and compares it line by line with document.xml. It passes only if they
% are the same, apart from two kinds of line in files that Callum saved
% upstream with another App Designer (counted and shown; the result is the
% same app):
%   - UIAxes "ColorOrder = <this MATLAB's default>" lines, which App
%     Designer writes only where its default differs;
%   - "XTickLabelRotation = 0" written by older App Designer releases, which
%     R2026a writes as "XTickLabelRotationMode = 'manual'".
% So code that App Designer cannot hold makes it fail: comments or other
% code inside createComponents (e.g. an OM_APP_HEADLESS check; the apps hide
% their window at the top of startupFcn instead), and functions put by hand
% into the callbacks block that are not callbacks "name(app, event)" (they
% belong in the editable section above it).
% What it cannot check: the regenerated code is a re-implementation of App
% Designer's code view (component lines come from MATLAB's own generator).
% It was checked byte for byte against files App Designer saved, but only a
% save in App Designer itself is the final word.
% After an App Designer save, this probe also shows what the save changed.
% Usage: matlab -noFigureWindows -batch "addpath('<repo>/tests'); probe_mlapp_model_consistency"
%        probe_mlapp_model_consistency('<folder with .mlapp files>')

repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_dir, 'tests', 'helpers'));
app_dir = repo_dir;
if nargin, app_dir = char(varargin{1}); end
files = dir(fullfile(app_dir, '*.mlapp'));
pass = 0; fail = 0;
ax = uiaxes(uifigure('Visible', 'off'));
default_order = round(ax.ColorOrder, 3);
delete(ancestor(ax, 'figure'));
for k = 1:numel(files)
    f = fullfile(files(k).folder, files(k).name);
    try
        doc = appdesigner.internal.codegeneration.getAppFileCode(f);
        [regen, info] = mlapp_model_code(f);
        [D, nd] = normalise(regexp(doc, '\n', 'split'), default_order);
        [R, ~] = normalise(regexp(regen, '\n', 'split'), default_order);
        same = isequal(D, R);
        where = '';
        if ~same
            n = min(numel(D), numel(R));
            i = find(~strcmp(D(1:n), R(1:n)), 1);
            if isempty(i), i = n + 1; end
            where = sprintf(' first difference at line %d: code "%s" | model "%s"', i, ...
                strtrim(pick(D, i)), strtrim(pick(R, i)));
            % how far apart: lines only in one side (multiset count)
            [only_doc, only_model] = count_apart(D, R);
            where = sprintf('%s; %d lines only in the code, %d only in the model', where, only_doc, only_model);
        end
        fprintf(['%s: %d lines; model -> code %s; upstream-saved lines: %d ColorOrder, %d TickLabelRotation; ' ...
            'stale stored ComponentCode: %d%s\n'], files(k).name, numel(regexp(doc, '\n')) + 1, char(70 + 14 * same), ...
            nd.color_order, nd.rotation, numel(info.stale_component_code), where);
    catch me
        same = false;
        fprintf('%s: ERROR %s -> F\n', files(k).name, me.message);
    end
    if same, pass = pass + 1; else, fail = fail + 1; end
end
fprintf('PROBE_MLAPP_MODEL_CONSISTENCY RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_mlapp_model_consistency %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_mlapp_model_consistency %d/%d\n', pass, fail);
    error('probe_mlapp_model_consistency:fail', '%d .mlapp file(s) would lose code on an App Designer save', fail);
end
end

function s = pick(L, i)
s = '<end>';
if i <= numel(L), s = L{i}; end
end

function [only_a, only_b] = count_apart(A, B)
[u, ~, ia] = unique([A(:); B(:)]);
na = accumarray(ia(1:numel(A)), 1, [numel(u), 1]);
nb = accumarray(ia(numel(A)+1:end), 1, [numel(u), 1]);
only_a = sum(max(na - nb, 0));
only_b = sum(max(nb - na, 0));
end

function [L, n] = normalise(L, default_order)
% the two upstream-saved line kinds in the header, inside createComponents only
n = struct('color_order', 0, 'rotation', 0);
f0 = find(strcmp(L, '        function createComponents(app)'), 1);
if isempty(f0), return; end
f1 = f0 + find(strcmp(L(f0+1:end), '        end'), 1);
keep = true(size(L));
for i = f0 + 1:f1 - 1
    t = regexp(strtrim(L{i}), '^app\.\w+\.ColorOrder = (\[.*\]);$', 'tokens', 'once');
    if ~isempty(t) && isequal(round(str2num(t{1}), 3), default_order) %#ok<ST2NM>
        keep(i) = false;
        n.color_order = n.color_order + 1;
        continue;
    end
    r = regexprep(L{i}, '^(\s+app\.\w+\.[XYZ]TickLabelRotation) = 0;$', '$1Mode = ''manual'';');
    if ~strcmp(r, L{i})
        L{i} = r;
        n.rotation = n.rotation + 1;
    end
end
L = L(keep);
end
