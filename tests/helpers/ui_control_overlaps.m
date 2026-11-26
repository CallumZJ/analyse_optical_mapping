function report = ui_control_overlaps(root, tolerance)
%% Visible controls that overlap another visible control in the same container
% Collin Snitchler
% 23.11.2026
% Test helper. For every container under root (grid layouts, panels,
% tabs), the Position rectangles of its visible children are compared in
% pairs; two that share more than tolerance pixels (default 1) in both
% directions overlap. Children of a scrollable grid are compared too,
% as their rows can be pushed into each other. Call drawnow first, so the
% grid layouts have placed their children.
% report: struct array of container (class and tag/text of the parent),
% a, b (class and text of the two children), and the two rectangles.
if nargin < 2, tolerance = 1; end
report = struct('container', {}, 'a', {}, 'b', {}, 'rect_a', {}, 'rect_b', {});
report = walk(root, report, tolerance);
end


function report = walk(h, report, tol)
% The children of h that are shown, compared in pairs, then each child's own children
if ~isprop(h, 'Children'), return; end
kids = h.Children;
kids = kids(arrayfun(@shown, kids));
for i = 1:numel(kids)
    for j = i + 1:numel(kids)
        a = rect(kids(i));
        b = rect(kids(j));
        if isempty(a) || isempty(b), continue; end
        % Overlap along x and along y, in pixels
        ox = min(a(1) + a(3), b(1) + b(3)) - max(a(1), b(1));
        oy = min(a(2) + a(4), b(2) + b(4)) - max(a(2), b(2));
        if ox > tol && oy > tol
            report(end + 1) = struct('container', name_of(h), 'a', name_of(kids(i)), ...
                'b', name_of(kids(j)), 'rect_a', a, 'rect_b', b); %#ok<AGROW>
        end
    end
end
for i = 1:numel(kids)
    report = walk(kids(i), report, tol);
end
end


function tf = shown(h)
% Visible, and not a menu or a context menu (they have no place in the layout)
tf = isprop(h, 'Visible') && strcmp(char(h.Visible), 'on') && ...
    ~isa(h, 'matlab.ui.container.Menu') && ~isa(h, 'matlab.ui.container.ContextMenu');
end


function r = rect(h)
% The child's Position in its parent, [] when it has none or no size
r = [];
if ~isprop(h, 'Position'), return; end
p = double(h.Position);
if numel(p) ~= 4 || any(~isfinite(p)) || p(3) <= 0 || p(4) <= 0, return; end
r = p;
end


function s = name_of(h)
% The class and a short text of a component, for the report
s = class(h);
s = s(find(s == '.', 1, 'last') + 1:end);
for f = {'Text', 'Title', 'Tag'}
    if isprop(h, f{1})
        t = h.(f{1});
        if iscell(t), t = strjoin(cellstr(t), ' / '); end
        t = char(t);
        if ~isempty(t)
            s = sprintf('%s "%s"', s, t(1:min(end, 50)));
            return;
        end
    end
end
end
