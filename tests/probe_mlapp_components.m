function probe_mlapp_components
%% Probe: controls built only in code are still made, and the .mlapp does not hold them
% Collin Snitchler
% 15.10.2026
% The Reconstruction tab of the main app is made in code, not in App
% Designer's layout model, so an App Designer save would drop it from
% createComponents (README, "Editing the .mlapp files"). Since 23.11.2026 the
% tab is made by rabbit_reconstruction_ui.m, which the app makes in
% startupFcn. This checks that the class's constructor still creates each
% control, that analyse_optical_mapping.mlapp declares none of the class's
% controls, and that startupFcn hides the figure again for
% OM_APP_HEADLESS=1 as its first statement (both apps; createComponents is
% App Designer's own code and shows it, see probe_mlapp_model_consistency).
% The region dialog's rabbit controls are made in its startupFcn, which App
% Designer keeps.
% Usage: matlab -batch "addpath('<repo>/tests'); probe_mlapp_components" -noFigureWindows

repo_dir = fileparts(fileparts(mfilename('fullpath')));
pass = 0; fail = 0;
want = struct('app', {'analyse_optical_mapping', 'region_parameters'}, 'names', { ...
    {'ReconstructionTab', 'ReconstructionRunButton', 'ReconstructionSfmRecipeDropDown', ...
    'ReconstructionColmapBrowseButton', 'ReconstructionModelsField', 'ReconstructionCloudSourceDropDown', ...
    'ReconstructionViewNumberingDropDown', 'ReconstructionOmPoseFrameDropDown', 'ReconstructionRunList', ...
    'StageRowsGrid', 'ReconstructionDatasetFolderDropDown'}, ...
    {}}, 'ui_class', {'rabbit_reconstruction_ui', ''});
for a = 1:numel(want)
    tmp = tempname;
    unzip(fullfile(repo_dir, [want(a).app '.mlapp']), tmp);
    xml = fileread(fullfile(tmp, 'matlab', 'document.xml'));
    rmdir(tmp, 's');
    body = function_body(xml, 'function createComponents(app)');
    startup = function_body(xml, 'function startupFcn(app');
    missing = {};
    if ~isempty(want(a).ui_class)
        % The tab's controls: made by the class's constructor, not declared in the .mlapp
        cls = fileread(fullfile(repo_dir, [want(a).ui_class '.m']));
        ctor = function_body(cls, ['function obj = ' want(a).ui_class '(']);
        missing = want(a).names(cellfun(@(n) isempty(regexp(ctor, ['obj\.' n '\s*=\s*ui'], 'once')), want(a).names));
        props = regexp(cls, 'properties \(Access = public\)(.*?)\n    end', 'tokens', 'once');
        comps = regexp(props{1}, '^\s+(\w+)\s+matlab\.ui\.', 'tokens', 'lineanchors');
        comps = cellfun(@(c) c{1}, comps, 'UniformOutput', false);
        held = comps(cellfun(@(n) ~isempty(regexp(xml, ['^\s+' n '\s+matlab\.ui\.'], 'once', 'lineanchors')), comps));
        if isempty(comps)
            missing{end+1} = 'the class''s component list';
        end
        missing = [missing, strcat('declared in the .mlapp: ', held)];
        fprintf('%s: %d controls of %s, none declared in the .mlapp: %s\n', want(a).app, numel(comps), ...
            want(a).ui_class, char(70 + 14 * isempty(held)));
    end
    % both apps stay hidden for scripts and tests (OM_APP_HEADLESS=1): the
    % first statement of startupFcn hides the figure again
    code = regexprep(regexp(startup, '\n', 'split'), '^\s+', '');
    code = code(2:end);
    code = code(~cellfun(@isempty, code) & ~startsWith(code, '%'));
    hides = numel(code) >= 3 && strcmp(code{1}, 'if strcmp(getenv(''OM_APP_HEADLESS''), ''1'')') && ...
        ~isempty(regexp(code{2}, '^app\.\w+\.Visible = ''off'';$', 'once')) && strcmp(code{3}, 'end');
    if ~hides
        missing{end+1} = 'the OM_APP_HEADLESS hide at the top of startupFcn';
    end
    ok = ~isempty(body) && isempty(missing);
    found = 'found';
    if isempty(body), found = 'NOT FOUND'; end
    fprintf('%s: createComponents %s; missing: %s -> %s\n', want(a).app, found, strjoin(missing, ', '), char(70 + 14 * ok));
    if ok, pass = pass + 1; else, fail = fail + 1; end
end
fprintf('PROBE_MLAPP_COMPONENTS RESULT: %d passed, %d failed\n', pass, fail);
if fail == 0
    fprintf('PROBE_OK probe_mlapp_components %d/0\n', pass);
else
    fprintf('PROBE_FAIL probe_mlapp_components\n');
    error('probe_mlapp_components:Failed', '%d check(s) failed.', fail);
end
end


function body = function_body(src, start_text)
% The text of one method, from its function line to the next method or block end
body = '';
% only a line that starts with it (after indentation): a comment that quotes
% the signature, such as a file's section map, is not the method
i0 = regexp(src, ['^[ \t]*' regexptranslate('escape', start_text)], 'once', 'lineanchors');
if isempty(i0), return; end
rest = src(i0(1):end);
i1 = regexp(rest, '\n        function |\n    end\s*\n\s*methods', 'once');
if isempty(i1), i1 = numel(rest); end
body = rest(1:i1);
end
