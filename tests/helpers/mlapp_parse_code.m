function p = mlapp_parse_code(code_text)
%% Split App Designer app code into the parts App Designer's model stores
% Collin Snitchler
% 23.11.2026
% For code laid out as App Designer writes it: the component declarations,
% the editable section (properties and functions), startupFcn, the callbacks
% and the '% Create X' blocks of createComponents.
% App Designer's callbacks block can hold only callbacks: "function
% name(app, event)" under the comment App Designer writes. Other functions
% that were put there outside App Designer (helpers, other inputs, own
% comments) cannot be stored as callbacks. They are returned in p.helpers
% and placed, text unchanged, at the end of the editable section's last
% private methods block, which is where an App Designer save made from this
% model writes them. p.moved_code is the code with that move made (equal to
% code_text when there are none).
% Lines App Designer cannot keep inside createComponents (comments, other
% code) are listed in p.create_extra.
% Used by mlapp_sync_model.

L = regexp(code_text, '\n', 'split');
[L2, p.helpers] = move_helpers(L);
p.moved_code = strjoin(L2, newline);
L = L2;
p.class_name = char(regexp(L{1}, '^classdef (\w+)', 'tokens', 'once'));
[d0, d1, c0, k0] = sections(L);
p.declared = regexp(L(d0+1:d1-1), '^\s+(\w+)\s+(\S+)$', 'tokens', 'once');
p.declared = vertcat(p.declared{:});
if isempty(c0)
    p.editable = L(d1+2:k0-2);
else
    p.editable = L(d1+2:c0-2);
end

% callbacks: '        % comment', '        function name(app, ...)', code, '        end'
p.callbacks = struct('Name', {}, 'Code', {});
p.startup = struct('Name', {}, 'Code', {});
p.inputs = '';
for f = functions_in(L, c0, k0)
    body = L(f.line+1:f.last-1);
    if f.is_startup
        p.startup = struct('Name', f.name, 'Code', {body});
        p.inputs = strtrim(regexprep(f.args, '^app\s*,?', ''));
    else
        p.callbacks(end+1) = struct('Name', f.name, 'Code', {body});
    end
end

% createComponents: '% Create X' blocks up to the closing lines
[p.blocks, p.create_extra] = create_blocks(L);
end

function [d0, d1, c0, k0] = sections(L)
d0 = find(strcmp(L, '    properties (Access = public)'), 1);
d1 = d0 + find(strcmp(L(d0+1:end), '    end'), 1);
c0 = find(strcmp(L, '    % Callbacks that handle component events'), 1);
k0 = find(strcmp(L, '    % Component initialization'), 1);
end

function F = functions_in(L, c0, k0)
% the functions of the callbacks block, with the comment lines above each
F = struct('name', {}, 'args', {}, 'first', {}, 'line', {}, 'last', {}, 'is_startup', {});
if isempty(c0), return; end
i = c0 + 3;
stop = k0 - 2;
while i <= stop
    % function name(args), function out = name(args), function [a, b] = name(args)
    t = regexp(L{i}, '^        function (\[[^\]]*\]\s*=\s*|\w+\s*=\s*)?(\w+)(\((.*)\))?\s*$', 'tokens', 'once');
    if isempty(t), i = i + 1; continue; end
    has_out = ~isempty(t{1});
    t = {t{2}, regexprep(t{3}, '^\((.*)\)$', '$1')};
    if has_out, t{2} = ['<out> ' t{2}]; end
    e = i + find(strcmp(L(i+1:stop), '        end'), 1);
    first = i;
    while first > c0 + 3 && startsWith(L{first-1}, '        %')
        first = first - 1;
    end
    F(end+1) = struct('name', t{1}, 'args', t{2}, 'first', first, 'line', i, 'last', e, ...
        'is_startup', strcmp(L{i-1}, '        % Code that executes after component creation')); %#ok<AGROW>
    i = e + 1;
end
end

function [blocks, extra] = create_blocks(L)
f0 = find(strcmp(L, '        function createComponents(app)'), 1);
f1 = f0 + find(strcmp(L(f0+1:end), '        end'), 1);
blocks = struct('name', {}, 'lines', {});
extra = {};
cur = 0;
for i = f0 + 1:f1 - 1
    s = L{i};
    t = regexp(s, '^\s*% Create (\w+)( and hide until all components are created)?$', 'tokens', 'once');
    if ~isempty(t)
        if ~startsWith(s, '            % Create ')
            extra{end+1} = sprintf('%d: %s', i, s); %#ok<AGROW>
        end
        blocks(end+1) = struct('name', t{1}, 'lines', {{}}); %#ok<AGROW>
        cur = numel(blocks);
        continue;
    end
    if isempty(strtrim(s))
        cur = 0;
        continue;
    end
    if cur && startsWith(s, '            ') && ~startsWith(strtrim(s), '%')
        blocks(cur).lines{end+1} = s(13:end);
    else
        extra{end+1} = sprintf('%d: %s', i, s); %#ok<AGROW>
    end
end
end

function [L, names] = move_helpers(L)
% move functions App Designer cannot hold as callbacks to the editable section
names = {};
[~, d1, c0, k0] = sections(L);
if isempty(c0), return; end
% callbacks that createComponents attaches to a component
[blocks, ~] = create_blocks(L);
bound = {};
for b = blocks
    t = regexp(b.lines, 'createCallbackFcn\(app, @(\w+), true\)', 'tokens', 'once');
    t = t(~cellfun(@isempty, t));
    bound = [bound, cellfun(@(x) x{1}, t, 'UniformOutput', false)]; %#ok<AGROW>
end
F = functions_in(L, c0, k0);
helper = false(size(F));
for k = 1:numel(F)
    if F(k).is_startup, continue; end
    comment = L(F(k).first:F(k).line-1);
    callback_like = strcmp(F(k).args, 'app, event') && ...
        (ismember(F(k).name, bound) || isequal(comment, {'        % Callback function'}));
    helper(k) = ~callback_like;
end
if ~any(helper), return; end
F = F(helper);
names = {F.name};
moved = {};
drop = false(size(L));
for k = 1:numel(F)
    moved = [moved, {''}, L(F(k).first:F(k).last)]; %#ok<AGROW>
    drop(F(k).first:F(k).last) = true;
    % and the blank line that separated it from the next function
    if F(k).last + 1 <= numel(L) && isempty(L{F(k).last + 1}), drop(F(k).last + 1) = true; end
end
% into the last methods block of the editable section if it is private,
% else into a new private methods block at its end
esc_end = c0 - 2;
last_methods = find(startsWith(L(d1+1:esc_end), '    methods'), 1, 'last') + d1;
if ~isempty(last_methods) && strcmp(L{last_methods}, '    methods (Access = private)')
    close = find(strcmp(L(1:esc_end), '    end'), 1, 'last');
    L2 = [L(1:close-1), moved, L(close:end)];
    shift = numel(moved);
    drop = [drop(1:close-1), false(1, shift), drop(close:end)];
else
    block = [{'', '    methods (Access = private)'}, moved(2:end), {'    end'}];
    L2 = [L(1:esc_end), block, L(esc_end+1:end)];
    drop = [drop(1:esc_end), false(1, numel(block)), drop(esc_end+1:end)];
end
L = L2(~drop);
% a callbacks block left with a blank line before its end
c0 = find(strcmp(L, '    % Callbacks that handle component events'), 1);
k0 = find(strcmp(L, '    % Component initialization'), 1);
if k0 > 2 && strcmp(L{k0-2}, '    end') && isempty(L{k0-3})
    L(k0-3) = [];
end
end
