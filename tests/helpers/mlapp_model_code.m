function [code, info] = mlapp_model_code(mlapp_file, theme)
%% Rebuild the code App Designer would write for an .mlapp from its model
% Collin Snitchler
% 23.11.2026
% An .mlapp holds two copies of the app: the code (matlab/document.xml) and
% App Designer's model (appdesigner/appModel.mat). App Designer's save writes
% the code again from the model, so code that the model does not describe is
% lost. This function writes that code headless, from the model alone:
%   - the model is loaded by MATLAB's own loader
%     (appdesigner.internal.serialization.MLAPPDeserializer, R2026a);
%   - each component's lines are made by MATLAB's own component code
%     generator (appdesigner.internal.codegeneration.ComponentCodeGenerator
%     with the component's adapter), as App Designer does when it opens an
%     app;
%   - the rest (declarations, the editable section, callbacks, createComponents
%     and the constructor) is assembled as App Designer's code view does
%     (web/release/bundle.mwBundle.appdesigner.js in R2026a). That assembly
%     is a re-implementation, checked against files App Designer saved.
% info.stale_component_code lists components whose stored ComponentCode
% differs from the regenerated lines (App Designer would write the new ones).
% theme: the colour theme App Designer generates component code for
% ('unthemed' by default; 'light' when App Designer runs with themes on, which
% adds e.g. UIAxes ColorOrder lines). Internal MathWorks API: checked on
% R2026a only.
if nargin < 2 || isempty(theme), theme = 'unthemed'; end

app_data = appdesigner.internal.serialization.MLAPPDeserializer(char(mlapp_file), {}).getAppData();
fig = app_data.components.UIFigure;
cleanup = onCleanup(@() delete(fig));
c = app_data.code;
if isfield(c, 'HelpComments') && (~isempty(c.HelpComments.Summary) || ~isempty(c.HelpComments.Description))
    error('mlapp_model_code:help', 'help comments are not handled');
end
adapters = appdesigner.internal.appmetadata.getProductionComponentAdapterMap();
generator = appdesigner.internal.codegeneration.ComponentCodeGenerator();

% components in creation order and in declaration order
created = creation_order(fig);
% UIAxes: App Designer's design-time controller adds transient aliased
% properties before it generates code (DesignTimeUIAxesController,
% prepareAliasedProperties); without them Visible = 'off' is not written
for k = 1:numel(created)
    if isa(created{k}, 'matlab.ui.control.UIAxes'), prepare_uiaxes(created{k}); end
end
declared = declaration_order(fig);
info.stale_component_code = {};
info.components = cellfun(@(h) h.DesignTimeProperties.CodeName, created, 'UniformOutput', false);

% callback bindings: callback name -> {CodeName, property, component type}
bind = containers.Map();
for k = 1:numel(created)
    h = created{k};
    p = properties(h);
    for j = 1:numel(p)
        if ~(endsWith(p{j}, 'Fcn') || endsWith(p{j}, 'Callback')), continue; end
        v = h.(p{j});
        if (ischar(v) || isstring(v)) && strlength(v) > 0
            v = char(v);
            if ~bind.isKey(v), bind(v) = cell(0, 3); end
            bind(v) = [bind(v); {h.DesignTimeProperties.CodeName, p{j}, class(h)}];
        end
    end
end

L = {};
L{end+1} = ['classdef ' c.ClassName ' < matlab.apps.AppBase'];
L{end+1} = '';
L{end+1} = '    % Properties that correspond to app components';
L{end+1} = '    properties (Access = public)';
% names are padded to the longest name of at most 30 characters, + 2
names = cellfun(@(h) h.DesignTimeProperties.CodeName, declared, 'UniformOutput', false);
n_len = cellfun(@numel, names);
width = max([n_len(n_len <= 30), 0]) + 2;
for k = 1:numel(declared)
    n = names{k};
    L{end+1} = sprintf('        %s%s%s', n, blanks(max(width, numel(n) + 2) - numel(n)), class(declared{k})); %#ok<*AGROW>
end
L{end+1} = '    end';
L{end+1} = '';
esc = field_or(c, 'EditableSectionCode', {});
if ~isempty(esc)
    L = [L, reshape(cellstr(esc), 1, [])];
    L{end+1} = '';
end

% callbacks
has_startup = isfield(c, 'StartupCallback') && ~isempty(c.StartupCallback) && ~isempty(c.StartupCallback.Name);
cbs = field_or(c, 'Callbacks', struct('Name', {}, 'Code', {}));
inputs = field_or(c, 'InputParameters', '');
if has_startup || ~isempty(cbs)
    L{end+1} = '    % Callbacks that handle component events';
    L{end+1} = '    methods (Access = private)';
    L{end+1} = '';
    if has_startup
        L{end+1} = '        % Code that executes after component creation';
        if isempty(inputs)
            L{end+1} = sprintf('        function %s(app)', c.StartupCallback.Name);
        else
            L{end+1} = sprintf('        function %s(app, %s)', c.StartupCallback.Name, inputs);
        end
        L = [L, reshape(cellstr(c.StartupCallback.Code), 1, [])];
        L{end+1} = '        end';
        L{end+1} = '';
    end
    for k = 1:numel(cbs)
        L = [L, callback_comment(cbs(k).Name, bind)];
        L{end+1} = sprintf('        function %s(app, event)', cbs(k).Name);
        L = [L, reshape(cellstr(cbs(k).Code), 1, [])];
        L{end+1} = '        end';
        L{end+1} = '';
    end
    L(end) = [];
    L{end+1} = '    end';
    L{end+1} = '';
end

% createComponents
fig_name = fig.DesignTimeProperties.CodeName;
L{end+1} = '    % Component initialization';
L{end+1} = '    methods (Access = private)';
L{end+1} = '';
L{end+1} = '        % Create UIFigure and components';
L{end+1} = '        function createComponents(app)';
L{end+1} = '';
uses_images = any(cellfun(@(h) isfield(h.DesignTimeProperties, 'ImageRelativePath') && ...
    ~isempty(h.DesignTimeProperties.ImageRelativePath), created));
if uses_images
    L{end+1} = '            % Get the file path for locating images';
    L{end+1} = '            pathToMLAPP = fileparts(mfilename(''fullpath''));';
    L{end+1} = '';
end
for k = 1:numel(created)
    h = created{k};
    n = h.DesignTimeProperties.CodeName;
    lines = component_lines(h, adapters, generator, theme);
    stored = cellstr(h.DesignTimeProperties.ComponentCode);
    if ~isequal(reshape(stored, [], 1), reshape(lines, [], 1))
        info.stale_component_code{end+1} = n;
    end
    if k == 1
        L{end+1} = sprintf('            %% Create %s and hide until all components are created', n);
    else
        L{end+1} = sprintf('            %% Create %s', n);
    end
    parent = '';
    if k > 1, parent = h.Parent.DesignTimeProperties.CodeName; end
    for j = 1:numel(lines)
        s = strrep(strrep(lines{j}, 'ad_PARENTCODENAME_ad', parent), 'ad_CODENAME_ad', n);
        tok = regexp(s, '^app\.\w+\.(\w+) = ''(\w+)'';$', 'tokens', 'once');
        if ~isempty(tok) && (endsWith(tok{1}, 'Fcn') || endsWith(tok{1}, 'Callback')) && bind.isKey(tok{2})
            s = sprintf('app.%s.%s = createCallbackFcn(app, @%s, true);', n, tok{1}, tok{2});
        end
        L{end+1} = ['            ' s];
    end
    L{end+1} = '';
end
L{end+1} = '            % Show the figure after all components are created';
L{end+1} = sprintf('            app.%s.Visible = ''on'';', fig_name);
L{end+1} = '        end';
L{end+1} = '    end';
L{end+1} = '';

% constructor and delete
L{end+1} = '    % App creation and deletion';
L{end+1} = '    methods (Access = public)';
L{end+1} = '';
L{end+1} = '        % Construct app';
if isempty(inputs)
    L{end+1} = sprintf('        function app = %s', c.ClassName);
else
    L{end+1} = sprintf('        function app = %s(varargin)', c.ClassName);
end
L{end+1} = '';
L{end+1} = '            % Create UIFigure and components';
L{end+1} = '            createComponents(app)';
L{end+1} = '';
L{end+1} = '            % Register the app with App Designer';
L{end+1} = sprintf('            registerApp(app, app.%s)', fig_name);
L{end+1} = '';
if has_startup
    L{end+1} = '            % Execute the startup function';
    if isempty(inputs)
        L{end+1} = sprintf('            runStartupFcn(app, @%s)', c.StartupCallback.Name);
    else
        L{end+1} = sprintf('            runStartupFcn(app, @(app)%s(app, varargin{:}))', c.StartupCallback.Name);
    end
    L{end+1} = '';
end
L{end+1} = '            if nargout == 0';
L{end+1} = '                clear app';
L{end+1} = '            end';
L{end+1} = '        end';
L{end+1} = '';
L{end+1} = '        % Code that executes before app deletion';
L{end+1} = '        function delete(app)';
L{end+1} = '';
L{end+1} = '            % Delete UIFigure when app is deleted';
L{end+1} = sprintf('            delete(app.%s)', fig_name);
L{end+1} = '        end';
L{end+1} = '    end';
L{end+1} = 'end';
code = strjoin(L, newline);
end

function v = field_or(s, f, d)
v = d;
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); end
end

function k = design_children(h)
% children that App Designer knows (they carry DesignTimeProperties)
k = {};
if ~isprop(h, 'Children'), return; end
a = allchild(h);
for i = 1:numel(a)
    if isprop(a(i), 'DesignTimeProperties'), k{end+1} = a(i); end
end
end

function k = created_children(h)
% Children lists the newest component first; tabs and grid children are
% listed in creation order
k = design_children(h);
if ~(isa(h, 'matlab.ui.container.TabGroup') || isa(h, 'matlab.ui.container.GridLayout'))
    k = flip(k);
end
end

function out = creation_order(h)
out = {h};
k = created_children(h);
for i = 1:numel(k), out = [out, creation_order(k{i})]; end
end

function out = declaration_order(h)
% declarations: menus and tabs in creation order, other components newest first
out = {h};
k = created_children(h);
is_menu = cellfun(@(x) isa(x, 'matlab.ui.container.Menu'), k);
others = k(~is_menu);
if ~isa(h, 'matlab.ui.container.TabGroup'), others = flip(others); end
k = [k(is_menu), others];
for i = 1:numel(k), out = [out, declaration_order(k{i})]; end
end

function lines = component_lines(h, adapters, generator, theme)
% the lines App Designer generates for one component from its properties
t = class(h);
if ~adapters.isKey(t)
    lines = reshape(cellstr(h.DesignTimeProperties.ComponentCode), [], 1);
    return;
end
adapter = feval(adapters(t));
lines = generator.getComponentGenerationCode(h, adapter, 'Standard', theme);
lines = reshape(cellstr(lines), [], 1);
end

function out = callback_comment(name, bind)
% comment line(s) above a callback, as in App Designer's code view
mixed = 'Callback function';
if ~bind.isKey(name)
    % App Designer's own files show this for callbacks no component uses
    % (the JS would write ': not associated with a component' only for a
    % callback made in this session)
    out = {['        % ' mixed]};
    return;
end
b = bind(name);
r = mixed;
if numel(unique(b(:, 2))) == 1
    r = default_comment(b{1, 3}, b{1, 2});
end
g = sort(b(:, 1));
g = reshape(g, 1, []);
r = [r ': '];
C = 8;
A = C + numel(r);
d = {r};
D = 0;
M = numel(g);
while ~isempty(g)
    v = g{1}; g(1) = [];
    if ~isempty(g), v = [v ', ']; end
    if A + numel(v) > 75
        if D
            n = M - D;
            if n == 1, m = '...and 1 other component'; else, m = sprintf('...and %d other components', n); end
            d{end+1} = ['% ' m];
            break;
        else
            D = D + 1;
            S = format_comment(v);
            d{end+1} = S;
            A = C + numel(S);
        end
    else
        D = D + 1;
        d{end} = [d{end} v];
        A = A + numel(v);
    end
end
out = cellfun(@(s) ['        ' format_comment(s)], d, 'UniformOutput', false);
end

function s = format_comment(s)
if ~startsWith(s, '%'), s = ['% ' s]; end
end

function s = default_comment(type, prop)
if strcmp(type, 'matlab.ui.container.TabGroup') && strcmp(prop, 'SelectionChangedFcn')
    s = '% Selection change function';
    return;
end
m = struct('ButtonDownFcn', 'Button down function', 'ButtonPushedFcn', 'Button pushed function', ...
    'ClickedFcn', 'Clicked callback', 'CloseRequestFcn', 'Close request function', ...
    'ContextMenuOpeningFcn', 'Context menu opening function', 'DoubleClickedFcn', 'Double-clicked callback', ...
    'DropDownOpeningFcn', 'Drop down opening function', 'DataChangedFcn', 'Data changed function', ...
    'HTMLEventReceivedFcn', 'Event received function', 'ImageClickedFcn', 'Image clicked function', ...
    'KeyPressFcn', 'Key press function', 'KeyReleaseFcn', 'Key release function', ...
    'MenuSelectedFcn', 'Menu selected function', 'SelectionChangedFcn', 'Selection changed function', ...
    'SizeChangedFcn', 'Size changed function', 'ThemeChangedFcn', 'Theme changed function', ...
    'OffCallback', 'Off callback', 'OnCallback', 'On callback', 'NodeCollapsedFcn', 'Node collapsed function', ...
    'NodeExpandedFcn', 'Node expanded function', 'NodeTextChangedFcn', 'Node text changed function', ...
    'CellEditCallback', 'Cell edit callback', 'CellSelectionCallback', 'Cell selection callback', ...
    'DisplayDataChangedFcn', 'Display data changed function', 'ValueChangedFcn', 'Value changed function', ...
    'ValueChangingFcn', 'Value changing function', 'WindowButtonDownFcn', 'Window button down function', ...
    'WindowButtonMotionFcn', 'Window button motion function', 'WindowButtonUpFcn', 'Window button up function', ...
    'WindowKeyPressFcn', 'Window key press function', 'WindowKeyReleaseFcn', 'Window key release function', ...
    'WindowScrollWheelFcn', 'Window scroll wheel function');
if isfield(m, prop)
    s = ['% ' m.(prop)];
else
    s = 'Callback function';
end
end

function prepare_uiaxes(ax)
% as DesignTimeUIAxesController.prepareAliasedVisibleProperty,
% prepareColormapStringProperty and prepareAliasedToolbarProperty (R2026a)
if ~isprop(ax, 'AD_AliasedVisible')
    p = addprop(ax, 'AD_AliasedVisible');
    p.Transient = true;
    if isequal(ax.Visible, 'off')
        ax.AD_AliasedVisible = matlab.lang.OnOffSwitchState('off');
        ax.Visible = 'on';
    else
        ax.AD_AliasedVisible = matlab.lang.OnOffSwitchState('on');
    end
end
if ~isprop(ax, 'AD_ColormapString')
    p = addprop(ax, 'AD_ColormapString');
    p.Transient = true;
end
ax.AD_ColormapString = inspector.internal.getColormapString(ax.Colormap);
if ~isprop(ax, 'AD_AliasedToolbar')
    p = addprop(ax, 'AD_AliasedToolbar');
    p.Transient = true;
    if isempty(ax.Toolbar)
        ax.AD_AliasedToolbar = matlab.lang.OnOffSwitchState('off');
    else
        ax.AD_AliasedToolbar = matlab.lang.OnOffSwitchState('on');
    end
end
end
