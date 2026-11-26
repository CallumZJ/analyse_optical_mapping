classdef app_screenshot
    %% File > Current app screenshot: PNG pictures of the app as it is now
    % Collin Snitchler
    % 26.11.2026
    % One click saves, in a folder the user chooses (uigetdir; the last
    % folder is remembered in the MATLAB preferences):
    %   <stem>_<yyyymmdd-HHMMSS>_window.png   the top of the main window as
    %       it is on the screen: the system's title bar (minimise, maximise,
    %       close) and the menu bar, taken from the screen (grab_window)
    %   <stem>_<yyyymmdd-HHMMSS>_preview.png  the part of the app above the
    %       tabs (top line, image, signal axes), as the non-reconstruction
    %       tabs show it; only when data is loaded
    %   <stem>_<yyyymmdd-HHMMSS>_tab_<Title>.png  each tab of the main tab
    %       group, chosen in turn, without the part above the tabs
    % <stem> is the loaded recording's name, or "app" when none is loaded.
    % An existing file is never overwritten: a suffix _2, _3, ... is added.
    % Afterwards the tab that was shown is shown again; no value changes.
    % A short message lists the files saved and anything not saved.
    %
    % The window picture is a screen grab (java.awt.Robot), so it shows
    % what is on the screen there. MATLAB gives the window's place in its
    % own pixels; the screen grab works in the screen's pixels. Their
    % ratio (screen_scale: Java's screen width over groot's ScreenSize) is
    % the display scaling on Windows (2.25 at 225 %), and 1 on macOS and on
    % most Linux displays, where both count the same units. The window
    % picture is not taken in a headless run (OM_APP_HEADLESS=1, figure
    % windows off, no Java display) or when the window is hidden,
    % minimised or off the screen; the message says so.
    % The preview and the tabs are drawn by exportapp (which also works for
    % a hidden window) and cut out of its picture.

    methods (Static)

        function menu = attach_menu(app, file_menu)
            %% File > Current app screenshot, right after Workspace
            menu = findall(file_menu, 'Tag', 'CurrentAppScreenshotMenu');
            if ~isempty(menu), return; end
            menu = uimenu(file_menu, 'Text', 'Current app screenshot', 'Tag', 'CurrentAppScreenshotMenu', ...
                'Tooltip', {'Save PNG pictures of the window''s top, the map preview and each tab, as they are now, in a folder you choose. Nothing in the app changes.'}, ...
                'MenuSelectedFcn', @(~, ~) app_screenshot.take(app));
            try
                % a menu lists its children last-made first: in the order shown
                kids = flipud(file_menu.Children);
                kids(kids == menu) = [];
                k = find(kids == app.workspace, 1);
                if ~isempty(k)
                    kids = [kids(1:k); menu; kids(k + 1:end)];
                    file_menu.Children = flipud(kids);
                end
            catch
                % left at the end of the menu
            end
        end

        function saved = take(app, stamp)
            %% Ask for the folder, save the pictures, say what was saved
            % stamp (optional, yyyymmdd-HHMMSS) is the time in the file
            % names; by default the time now. saved lists the full paths.
            saved = {};
            fig = app.opticalmappingUIFigure;
            if nargin < 2 || isempty(stamp)
                stamp = char(datetime('now', 'Format', 'yyyyMMdd-HHmmss'));
            end
            folder = app_screenshot.ask_folder();
            app.focus_main_window();
            if isempty(folder), return; end   % Cancel: nothing saved, nothing said
            base = [app_screenshot.stem_of(app) '_' stamp];
            skipped = {};

            % (a) the top of the window, from the screen, before any tab changes
            [file, why] = app_screenshot.grab_window(fig, fullfile(folder, [base '_window']));
            if isempty(file)
                skipped{end + 1} = ['window: not saved (' why ')'];
            else
                saved{end + 1} = file;
            end

            tg = app.TabGroup;
            state = app_screenshot.tab_state(app);
            restore = onCleanup(@() app_screenshot.restore_tabs(app, state));
            if strcmp(char(tg.Visible), 'off')
                tg.Visible = 'on';   % before a load the tabs are hidden; shown for the pictures only
            end
            tabs = tg.Children;
            recon = app_screenshot.reconstruction_tab(app);

            % (b) the part above the tabs, with a tab other than Reconstruction shown
            if app_screenshot.has_data(app)
                try
                    if ~isempty(recon) && isequal(tg.SelectedTab, recon)
                        others = tabs(tabs ~= recon);
                        if ~isempty(others), app_screenshot.choose_tab(app, others(1)); end
                    end
                    img = app_screenshot.app_picture(fig);
                    pos = tg.Position;
                    above = [1, pos(2) + pos(4), fig.Position(3), fig.Position(4) - (pos(2) + pos(4)) + 1];
                    file = app_screenshot.free_name(fullfile(folder, [base '_preview']));
                    imwrite(app_screenshot.cut(img, fig, above), file);
                    saved{end + 1} = file;
                catch ME
                    skipped{end + 1} = ['preview: not saved (' ME.message ')'];
                end
            else
                skipped{end + 1} = 'no data loaded: preview not saved';
            end

            % (c) each tab, chosen in turn
            for k = 1:numel(tabs)
                title = char(tabs(k).Title);
                try
                    app_screenshot.choose_tab(app, tabs(k));
                    img = app_screenshot.app_picture(fig);
                    file = app_screenshot.free_name(fullfile(folder, [base '_tab_' app_screenshot.file_part(title)]));
                    imwrite(app_screenshot.cut(img, fig, tg.Position), file);
                    saved{end + 1} = file; %#ok<AGROW>
                catch ME
                    skipped{end + 1} = sprintf('tab %s: not saved (%s)', title, ME.message); %#ok<AGROW>
                end
            end
            clear restore;   % the tab shown before, and the tab group's place, back

            names = cellfun(@app_screenshot.name_only, saved, 'UniformOutput', false);
            msg = sprintf('Saved in %s:\n%s', folder, strjoin(names, newline));
            if isempty(saved), msg = sprintf('Nothing saved in %s.', folder); end
            if ~isempty(skipped)
                msg = sprintf('%s\n\n%s', msg, strjoin(skipped, newline));
            end
            uialert(fig, msg, 'Current app screenshot', 'Icon', 'info');
        end

        function folder = ask_folder()
            %% The folder, from uigetdir, starting at the one used last ('' for Cancel)
            group = 'analyse_optical_mapping_AppScreenshot';
            start = pwd;
            try
                if ispref(group, 'last_folder')
                    last = getpref(group, 'last_folder');
                    if ischar(last) && isfolder(last), start = last; end
                end
            catch
                % an unreadable preference: start in the current folder
            end
            folder = uigetdir(start, 'Folder for the app screenshots');
            if isequal(folder, 0) || isempty(folder)
                folder = '';
                return;
            end
            folder = char(folder);
            try
                setpref(group, 'last_folder', folder);
            catch
                % not remembered; the pictures are still saved
            end
        end

        function [file, why] = grab_window(fig, base)
            %% The window's title bar and menu bar from the screen; file is '' and why says why when not taken
            % The strip from the window's outer top edge (OuterPosition) to
            % the top of its drawing area (Position), which is the title
            % bar and the menu bar. When MATLAB does not report a strip
            % (less than 10 of its pixels), the whole outer window is taken.
            file = '';
            why = app_screenshot.why_no_screen(fig);
            if ~isempty(why), return; end
            figure(fig);   % to the front, with the focus
            drawnow;
            pause(0.5);    % the menu that was clicked closes; the screen is redrawn
            old_units = fig.Units;
            fig.Units = 'pixels';
            outer = fig.OuterPosition;
            inner = fig.Position;
            fig.Units = old_units;
            screen = get(groot, 'ScreenSize');
            scale = app_screenshot.screen_scale();
            % MATLAB counts from the primary screen's bottom-left corner (1, 1);
            % the screen grab from its top-left corner (0, 0)
            top = outer(2) - 1 + outer(4);                 % outer top edge, from the bottom
            strip = top - (inner(2) - 1 + inner(4));       % title bar and menu bar
            if strip < 10, strip = outer(4); end           % not reported: the whole window
            rect = round([outer(1) - 1, screen(4) - top, outer(3), strip] * scale);
            rect = app_screenshot.on_screen(rect);
            if isempty(rect)
                why = 'the window is off the screen';
                return;
            end
            robot = java.awt.Robot();
            r = java.awt.Rectangle(rect(1), rect(2), rect(3), rect(4));
            img = [];
            try
                % Java 9 and later: the picture at the screen's own resolution
                variants = robot.createMultiResolutionScreenCapture(r).getResolutionVariants();
                img = variants.get(variants.size() - 1);
            catch
                % Java 8 (as MATLAB ships on Windows): screen pixels already
            end
            if isempty(img), img = robot.createScreenCapture(r); end
            file = app_screenshot.free_name(base);
            javax.imageio.ImageIO.write(img, 'png', java.io.File(file));
        end

        function why = why_no_screen(fig)
            %% '' when the window can be taken from the screen, otherwise the reason
            why = '';
            if strcmp(getenv('OM_APP_HEADLESS'), '1')
                why = 'headless run (OM_APP_HEADLESS=1): a screen picture can only be taken on a real screen';
                return;
            end
            try
                if ~feature('ShowFigureWindows')
                    why = 'figure windows are off (-noFigureWindows)';
                    return;
                end
            catch
                % no such switch in this MATLAB: decided by the checks below
            end
            if ~usejava('awt') || java.awt.GraphicsEnvironment.isHeadless()
                why = 'no Java display';
                return;
            end
            if ~strcmp(char(fig.Visible), 'on')
                why = 'the window is hidden';
                return;
            end
            if strcmp(char(fig.WindowState), 'minimized')
                why = 'the window is minimised';
            end
        end

        function scale = screen_scale()
            %% Screen pixels per MATLAB pixel (2.25 on Windows at 225 % scaling, 1 on macOS)
            % Java reports the primary screen in the pixels it grabs in;
            % groot reports the same screen in MATLAB's pixels.
            scale = 1;
            try
                d = java.awt.Toolkit.getDefaultToolkit().getScreenSize();
                s = get(groot, 'ScreenSize');
                ratio = double(d.width) / s(3);
                if isfinite(ratio) && ratio > 0.5 && ratio < 8, scale = ratio; end
            catch
                % no Java screen: MATLAB's pixels are taken as screen pixels
            end
        end

        function rect = on_screen(rect)
            %% rect cut to the screens; [] when less than half of it is on a screen
            % rect is [x y width height] in screen pixels from the top left.
            % The screens' union is taken as one rectangle: a window across
            % two screens of different heights may keep a corner of desktop.
            env = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment();
            devs = env.getScreenDevices();
            lo = [inf inf];
            hi = [-inf -inf];
            for k = 1:devs.length
                b = devs(k).getDefaultConfiguration().getBounds();
                lo = min(lo, [b.x b.y]);
                hi = max(hi, [b.x + b.width, b.y + b.height]);
            end
            a = max(rect(1:2), lo);
            b = min(rect(1:2) + rect(3:4), hi);
            if any(b <= a) || prod(b - a) < 0.5 * prod(rect(3:4))
                rect = [];
                return;
            end
            rect = [a, b - a];
        end

        function img = app_picture(fig)
            %% The whole app (menu bar included) as exportapp draws it
            tmp = [tempname '.png'];
            cleanup = onCleanup(@() app_screenshot.remove_temp(tmp));
            drawnow;
            exportapp(fig, tmp);
            img = imread(tmp);
        end

        function part = cut(img, fig, pos)
            %% The part of exportapp's picture at pos ([left bottom width height] in the window)
            % exportapp draws at the display's scale and puts the menu bar
            % above the drawing area, so the scale comes from the widths
            % and rows count from the picture's bottom edge.
            f = fig.Position;
            s = size(img, 2) / f(3);
            rows = max(1, round(size(img, 1) - (pos(2) - 1 + pos(4)) * s) + 1) : min(size(img, 1), round(size(img, 1) - (pos(2) - 1) * s));
            cols = max(1, round((pos(1) - 1) * s) + 1) : min(size(img, 2), round((pos(1) - 1 + pos(3)) * s));
            if isempty(rows) || isempty(cols), error('OM:Screenshot:Empty', 'the part is outside the window'); end
            part = img(rows, cols, :);
        end

        function state = tab_state(app)
            %% What choosing tabs changes: the tab shown, the tab group's place, size and visibility, the stacking
            tg = app.TabGroup;
            state.selected = tg.SelectedTab;
            state.position = tg.Position;
            state.visible = char(tg.Visible);
            state.children = app.opticalmappingUIFigure.Children;
            state.fresh = [];
            try
                state.fresh = app.recon.ReconstructionHelpFreshShownThisSelection;
            catch
                % no Reconstruction tab object
            end
        end

        function restore_tabs(app, state)
            %% The tab shown before, as it was shown
            try
                if ~isempty(state.selected) && isvalid(state.selected)
                    app_screenshot.choose_tab(app, state.selected);
                end
                fig = app.opticalmappingUIFigure;
                kids = fig.Children;
                if numel(kids) == numel(state.children) && all(ismember(kids, state.children))
                    fig.Children = state.children;   % the stacking as before (Reconstruction puts the tabs on top)
                end
                app.TabGroup.Position = state.position;
                app.TabGroup.Visible = state.visible;
                if ~isempty(state.fresh), app.recon.ReconstructionHelpFreshShownThisSelection = state.fresh; end
                drawnow;
            catch
                % left as the last tab chosen
            end
        end

        function choose_tab(app, tab)
            %% Show a tab as a user's choice lays it out, without opening the Reconstruction Help
            % The tab group's SelectionChangedFcn sets the tab group's
            % height (Reconstruction takes the window's height); while the
            % programmatic-selection count is up, it opens no Help.
            tg = app.TabGroup;
            counted = false;
            try
                app.recon.ReconstructionHelpProgrammaticSelectionDepth = app.recon.ReconstructionHelpProgrammaticSelectionDepth + uint32(1);
                counted = true;
            catch
                % no Reconstruction tab object
            end
            cleanup = onCleanup(@() app_screenshot.end_choice(app, counted));
            tg.SelectedTab = tab;
            if ~isempty(tg.SelectionChangedFcn)
                tg.SelectionChangedFcn(tg, []);
            end
            drawnow;
        end

        function end_choice(app, counted)
            %% The programmatic-selection count down again
            if ~counted, return; end
            try
                d = app.recon.ReconstructionHelpProgrammaticSelectionDepth;
                if d > 0, app.recon.ReconstructionHelpProgrammaticSelectionDepth = d - uint32(1); end
            catch
                % the app is gone
            end
        end

        function t = reconstruction_tab(app)
            %% The Reconstruction/Reprojection tab, or [] when there is none
            t = [];
            try
                t = app.recon.ReconstructionTab;
            catch
                % no Reconstruction tab object
            end
        end

        function yes = has_data(app)
            %% True when a recording is loaded
            yes = false;
            try
                yes = ~isempty(app.data.image_stack) || ~isempty(app.processed_data.image_stack);
            catch
                % no data fields yet
            end
        end

        function stem = stem_of(app)
            %% The loaded recording's name without its extension, or 'app'
            stem = 'app';
            try
                if app_screenshot.has_data(app) && ischar(app.file_info.file) && ~isempty(app.file_info.file)
                    [~, stem] = fileparts(app.file_info.file);
                end
            catch
                % no file name known
            end
            stem = app_screenshot.file_part(stem);
            if isempty(stem), stem = 'app'; end
        end

        function s = file_part(s)
            %% Text made safe for a file name on every system: letters, digits, . - _ kept, the rest _
            s = regexprep(char(s), '[^A-Za-z0-9._-]+', '_');
            s = regexprep(s, '^[_.]+|[_.]+$', '');
            if isempty(s), s = 'untitled'; end
        end

        function file = free_name(base)
            %% base.png, or base_2.png, base_3.png, ... when it exists: no file is overwritten
            file = [base '.png'];
            k = 1;
            while isfile(file)
                k = k + 1;
                file = sprintf('%s_%d.png', base, k);
            end
        end

        function n = name_only(file)
            %% The file's name with its extension
            [~, n, e] = fileparts(file);
            n = [n e];
        end

        function remove_temp(file)
            %% Remove this function's own temporary picture
            if isfile(file), delete(file); end
        end
    end
end
