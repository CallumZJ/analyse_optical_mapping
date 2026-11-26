function report = mlapp_sync_model(target_mlapp, base_mlapp, out_mlapp)
%% Rebuild an .mlapp's App Designer model so that it describes its code
% Collin Snitchler
% 23.11.2026
% The code in target_mlapp (matlab/document.xml) is the truth. The model is
% started from base_mlapp's model (App Designer's own components, which keeps
% hidden design-time state), then brought into line with the code:
%   - components: each '% Create X' block of createComponents is run against
%     the model (an existing component keeps its object; a new one is made
%     and given DesignTimeProperties); components the code does not make are
%     deleted; children are put in the code's creation order; properties the
%     model sets but the code does not are reset to their defaults;
%   - code: the editable section, the callbacks and startupFcn are taken
%     from the code text.
% The model is written with MATLAB's own serializer
% (appdesigner.internal.serialization.MLAPPSerializer, R2026a) to out_mlapp,
% which starts as a copy of target_mlapp; the code in its document.xml is
% checked to be target_mlapp's (see put_back_part for the XML bytes). Check the result with
% tests/probe_mlapp_model_consistency.m. Internal MathWorks API: R2026a only.
% Usage (headless):
%   matlab -batch "addpath('<repo>/tests/helpers'); mlapp_sync_model('<app>.mlapp', '<base>.mlapp', '<out>.mlapp')"

target_mlapp = char(target_mlapp); base_mlapp = char(base_mlapp); out_mlapp = char(out_mlapp);
code_text = appdesigner.internal.codegeneration.getAppFileCode(target_mlapp);
parsed = mlapp_parse_code(code_text);
base = appdesigner.internal.serialization.MLAPPDeserializer(base_mlapp, {});
app_data = base.getAppData();
fig = app_data.components.UIFigure;
cleanup = onCleanup(@() delete(fig));
adapters = appdesigner.internal.appmetadata.getProductionComponentAdapterMap();
generator = appdesigner.internal.codegeneration.ComponentCodeGenerator();
report = struct('created', {{}}, 'deleted', {{}}, 'reset', {{}}, 'unmatched', {{}});

% the model's components by CodeName
model = containers.Map();
all_comps = findall(fig, '-property', 'DesignTimeProperties');
for k = 1:numel(all_comps)
    model(all_comps(k).DesignTimeProperties.CodeName) = all_comps(k);
end
dtp_fields = containers.Map();
for k = 1:numel(all_comps)
    dtp_fields(class(all_comps(k))) = fieldnames(all_comps(k).DesignTimeProperties);
end

% 1) run each component block of createComponents against the model
app = struct();
blocks = parsed.blocks;
in_code = {};
for k = 1:numel(blocks)
    n = blocks(k).name;
    in_code{end+1} = n; %#ok<AGROW>
    lines = blocks(k).lines;
    ctor = regexp(lines{1}, ['^app\.' n ' = (\w+)\((.*)\);$'], 'tokens', 'once');
    if isempty(ctor), error('mlapp_sync_model:ctor', 'no constructor line for %s', n); end
    made = [];
    if model.isKey(n), made = model(n); end
    if k == 1
        app.(n) = made;
    else
        parent_name = regexp(ctor{2}, '^app\.(\w+)', 'tokens', 'once');
        parent = app.(parent_name{1});
        if ~isempty(made) && isvalid(made) && strcmp(class(made), expected_class(ctor{1}, ctor{2}, made))
            if made.Parent ~= parent, made.Parent = parent; end
            app.(n) = made;
        else
            if ~isempty(made) && isvalid(made), delete(made); end
            app.(n) = run_line(app, lines{1}, n);
            h = app.(n);
            p = addprop(h, 'DesignTimeProperties');
            p.NonCopyable = true;
            f = {'CodeName'; 'GroupId'; 'ComponentCode'};
            if dtp_fields.isKey(class(h)), f = dtp_fields(class(h)); end
            dtp = cell2struct(repmat({''}, numel(f), 1), f, 1);
            dtp.CodeName = n;
            dtp.ComponentCode = {};
            h.DesignTimeProperties = dtp;
            model(n) = h;
            report.created{end+1} = n;
        end
    end
    for j = 2:numel(lines)
        run_line(app, lines{j}, n);
    end
end

% 2) delete model components the code does not make
names = model.keys;
for k = 1:numel(names)
    if ~ismember(names{k}, in_code) && isvalid(model(names{k}))
        report.deleted{end+1} = names{k};
        delete(model(names{k}));
    end
end

% 3) children in the code's creation order (Children lists the newest
% first, except in tab groups and grid layouts)
for k = 1:numel(in_code)
    h = app.(in_code{k});
    if ~isprop(h, 'Children') || isempty(h.Children), continue; end
    kids = h.Children;
    kid_names = arrayfun(@(c) code_name(c), kids, 'UniformOutput', false);
    want = in_code(ismember(in_code, kid_names));
    if ~(isa(h, 'matlab.ui.container.TabGroup') || isa(h, 'matlab.ui.container.GridLayout'))
        want = flip(want);
    end
    designed = ~cellfun(@isempty, kid_names);
    [~, pos] = ismember(want, kid_names);
    ordered = kids;
    ordered(designed) = kids(pos);
    if ~isequal(ordered, kids), h.Children = ordered; end
end

% 4) UIAxes as App Designer prepares them, then reset what the code does
% not set, and store each component's generated lines
for k = 1:numel(in_code)
    h = app.(in_code{k});
    if isa(h, 'matlab.ui.control.UIAxes'), prepare_uiaxes(h); end
end
ax = uiaxes(uifigure('Visible', 'off'));
default_order = round(ax.ColorOrder, 3);
delete(ancestor(ax, 'figure'));
for k = 1:numel(blocks)
    n = blocks(k).name;
    h = app.(n);
    adapter = feval(adapters(class(h)));
    want = as_r2026a(blocks(k).lines, default_order);
    for attempt = 1:3
        gen = component_code(generator, h, adapter, n, code_name(h.Parent));
        extra = setdiff(gen, want, 'stable');
        if isempty(extra), break; end
        defaults = adapter.getComponentRunTimeDefaults('unthemed');
        for j = 1:numel(extra)
            prop = regexp(extra{j}, ['^app\.' n '\.(\w+) = '], 'tokens', 'once');
            if isempty(prop), continue; end
            prop = prop{1};
            if isprop(h, [prop 'Mode'])
                h.([prop 'Mode']) = 'auto';
            elseif isfield(defaults, prop)
                h.(prop) = defaults.(prop);
            end
            report.reset{end+1} = [n '.' prop];
        end
    end
    gen = component_code(generator, h, adapter, n, code_name(h.Parent));
    if ~isequal(gen, want)
        report.unmatched{end+1} = n;
    end
    h.DesignTimeProperties.ComponentCode = generator.getComponentGenerationCode(h, adapter, 'Standard', 'unthemed');
end

% 5) groups that still have members
groups = {};
if isfield(app_data.components, 'Groups'), groups = app_data.components.Groups; end
used = cellfun(@(n) app.(n).DesignTimeProperties.GroupId, in_code, 'UniformOutput', false);
keep = {};
for k = 1:numel(groups)
    if ismember(groups{k}.Id, used), keep{end+1} = groups{k}; end %#ok<AGROW>
end
changed = true;
while changed
    changed = false;
    ids = cellfun(@(g) g.Id, keep, 'UniformOutput', false);
    for k = 1:numel(groups)
        if ismember(groups{k}.Id, ids), continue; end
        if any(cellfun(@(g) strcmp(g.ParentGroupId, groups{k}.Id), keep))
            keep{end+1} = groups{k}; changed = true; %#ok<AGROW>
        end
    end
end

% 6) write: start from a copy of the target so its other parts stay
copyfile(target_mlapp, out_mlapp, 'f');
s = appdesigner.internal.serialization.MLAPPSerializer(out_mlapp, fig);
s.ClassName = parsed.class_name;
s.MatlabCodeText = code_text;
report.helpers = parsed.helpers;
base_code = app_data.code;
% same orientation as App Designer stores them (a row of lines; callback
% code as a row too)
s.EditableSectionCode = reshape(parsed.editable, 1, []);
s.Callbacks = parsed.callbacks;
s.StartupCallback = parsed.startup;
if ~isempty(parsed.inputs), s.InputParameters = parsed.inputs; end
if isfield(base_code, 'SingletonMode'), s.SingletonMode = base_code.SingletonMode; end
if isfield(base_code, 'AppTypeData'), s.AppTypeData = base_code.AppTypeData; end
s.Groups = keep;
meta = base.getAppMetadata();
mm = appdesigner.internal.model.MetadataModel();
f = fieldnames(meta);
for k = 1:numel(f)
    try, set(mm, f{k}, meta.(f{k})); catch, end
end
s.Metadata = mm;
s.save();

% 7) the code in document.xml must be the target's
put_back_part(out_mlapp, target_mlapp, 'matlab/document.xml');
report.groups = numel(keep);
end

function c = expected_class(fcn, args, made)
% the class a constructor line makes (uibutton(..., 'state') is a StateButton)
c = class(made);
m = struct('uifigure', 'matlab.ui.Figure', 'uimenu', 'matlab.ui.container.Menu', ...
    'uitabgroup', 'matlab.ui.container.TabGroup', 'uitab', 'matlab.ui.container.Tab', ...
    'uigridlayout', 'matlab.ui.container.GridLayout', 'uipanel', 'matlab.ui.container.Panel', ...
    'uibuttongroup', 'matlab.ui.container.ButtonGroup', 'uilabel', 'matlab.ui.control.Label', ...
    'uitextarea', 'matlab.ui.control.TextArea', 'uiaxes', 'matlab.ui.control.UIAxes', ...
    'uidropdown', 'matlab.ui.control.DropDown', 'uicheckbox', 'matlab.ui.control.CheckBox', ...
    'uislider', 'matlab.ui.control.Slider', 'uispinner', 'matlab.ui.control.Spinner', ...
    'uiimage', 'matlab.ui.control.Image', 'uilistbox', 'matlab.ui.control.ListBox', ...
    'uitable', 'matlab.ui.control.Table', 'uiradiobutton', 'matlab.ui.control.RadioButton', ...
    'uitogglebutton', 'matlab.ui.control.ToggleButton', 'uiswitch', 'matlab.ui.control.Switch');
if isfield(m, fcn), c = m.(fcn); return; end
if strcmp(fcn, 'uibutton')
    if contains(args, '''state''') && ~isempty(made), c = 'matlab.ui.control.StateButton';
    else, c = 'matlab.ui.control.Button'; end
elseif strcmp(fcn, 'uieditfield')
    if contains(args, '''numeric'''), c = 'matlab.ui.control.NumericEditField';
    else, c = 'matlab.ui.control.EditField'; end
end
end

function lines = as_r2026a(lines, default_order)
% the code lines as R2026a App Designer writes them (see the header of
% probe_mlapp_model_consistency): no ColorOrder line for the default
% colours, and TickLabelRotation = 0 written as TickLabelRotationMode
keep = true(size(lines));
for j = 1:numel(lines)
    t = regexp(lines{j}, '^app\.\w+\.ColorOrder = (\[.*\]);$', 'tokens', 'once');
    if ~isempty(t) && isequal(round(str2num(t{1}), 3), default_order) %#ok<ST2NM>
        keep(j) = false;
    end
    lines{j} = regexprep(lines{j}, '^(app\.\w+\.[XYZ]TickLabelRotation) = 0;$', '$1Mode = ''manual'';');
end
lines = lines(keep);
end

function n = code_name(h)
n = '';
if isprop(h, 'DesignTimeProperties'), n = h.DesignTimeProperties.CodeName; end
end

function out = run_line(app, line, ~)
% run one createComponents line; callbacks are stored by name in the model
line = regexprep(line, 'createCallbackFcn\(app, @(\w+), true\)', '''$1''');
if nargout
    rhs = regexp(line, '^app\.\w+ = (.*);$', 'tokens', 'once');
    out = eval(rhs{1});
else
    eval(line);
end
end

function lines = component_code(generator, h, adapter, n, parent)
lines = generator.getComponentGenerationCode(h, adapter, 'Standard', 'unthemed');
lines = reshape(cellstr(lines), 1, []);
lines = strrep(strrep(lines, 'ad_PARENTCODENAME_ad', parent), 'ad_CODENAME_ad', n);
for j = 1:numel(lines)
    tok = regexp(lines{j}, '^app\.\w+\.(\w+) = ''(\w+)'';$', 'tokens', 'once');
    if ~isempty(tok) && (endsWith(tok{1}, 'Fcn') || endsWith(tok{1}, 'Callback'))
        lines{j} = sprintf('app.%s.%s = createCallbackFcn(app, @%s, true);', n, tok{1}, tok{2});
    end
end
end

function prepare_uiaxes(ax)
% as DesignTimeUIAxesController.prepareAliasedProperties (R2026a)
if ~isprop(ax, 'AD_AliasedVisible')
    p = addprop(ax, 'AD_AliasedVisible'); p.Transient = true;
    if isequal(ax.Visible, 'off')
        ax.AD_AliasedVisible = matlab.lang.OnOffSwitchState('off'); ax.Visible = 'on';
    else
        ax.AD_AliasedVisible = matlab.lang.OnOffSwitchState('on');
    end
end
if ~isprop(ax, 'AD_ColormapString')
    p = addprop(ax, 'AD_ColormapString'); p.Transient = true;
end
ax.AD_ColormapString = inspector.internal.getColormapString(ax.Colormap);
if ~isprop(ax, 'AD_AliasedToolbar')
    p = addprop(ax, 'AD_AliasedToolbar'); p.Transient = true;
    if isempty(ax.Toolbar)
        ax.AD_AliasedToolbar = matlab.lang.OnOffSwitchState('off');
    else
        ax.AD_AliasedToolbar = matlab.lang.OnOffSwitchState('on');
    end
end
end

function put_back_part(out_mlapp, src_mlapp, ~)
% the serializer writes document.xml from the code text: the code must be
% the target's exactly. (R2026a leaves out the newline after
% </w:document>; to get the target's document.xml back byte for byte, run
% tests/helpers/mlapp_surgery.py --source out --edited-xml <target's
% document.xml>; a Java re-zip would change the zip flags it checks.)
code_out = appdesigner.internal.codegeneration.getAppFileCode(out_mlapp);
code_src = appdesigner.internal.codegeneration.getAppFileCode(src_mlapp);
if ~isequal(code_out, code_src)
    error('mlapp_sync_model:document', 'the code in %s differs from the target''s', out_mlapp);
end
end
