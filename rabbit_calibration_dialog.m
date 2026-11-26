classdef rabbit_calibration_dialog < handle
    %% Window of the rig calibration (Reconstruction tab, step 2, Calibrate...)
    % Collin Snitchler
    % 02.11.2026
    % Purpose: choose the calibration recordings, their target and its
    %          size, run pyCamSet and read the verdict. The work is done by
    %          rabbit_reconstruction_tab.run_calibration; this file is only
    %          the window.
    % The window is modal, so a dataset cannot change under a calibration.
    % Run keeps the window live while pyCamSet works, like a run's external
    % steps: Cancel reaches the job, and the line above the results follows
    % the job's log.
    % Sources shown in the window: pyCamSet (R. Laven and contributors).
    % Each recording's frame is placed in the reconstruction
    % frame when it is added (rabbit_calibration.placement: same camera, so
    % only the camera's area of interest can differ), shown under Frame
    % position, and can be typed in with Position....

    properties
        Tab                 % the rabbit_reconstruction_tab of the dataset
        OnDone              % called after a calibration, to refresh step 2
        Figure
        Table               % File, Use for, Target, Squares, Edge (mm), Size from
        FocalField
        PitchField
        LensField
        PreprocessBox       % Sauvola pre-processing of Ccube recordings (default on)
        PythonField
        CheckoutField
        RunButton
        CancelButton
        CloseButton
        StatusLabel
        ResultsArea
        Bounds = []         % 4x4 tile bounds in the reconstruction frame
        FrameHw = []        % [rows columns] of the reconstruction frame
        RoiHw = []          % [rows columns] of the frame the regions were drawn on
        Reference = ''      % the reconstruction recording, to place the calibration frames against
        RoiJson = ''        % the ROI file, whose region-dialog line-ups can place a calibration recording
        Held = []           % the line-ups the app holds now, when the ROI file has none
        SameSizeAnswer = '' % the file whose "They line up" answer also covers later same-size recordings
        Places = {}         % per table row: struct offset, score, note, source (rabbit_calibration.placement)
        LastDir = ''        % folder of the last calibration
        LastOk = false
        Timer = []
        Running = false
    end

    methods
        function obj = rabbit_calibration_dialog(tab, bounds, focal_px, on_done, frame_hw, roi_hw, reference, roi_json, held, prefill)
            obj.Tab = tab;
            obj.OnDone = on_done;
            obj.Bounds = bounds;
            obj.FrameHw = frame_hw;
            obj.RoiHw = roi_hw;
            if nargin >= 7, obj.Reference = char(reference); end
            if nargin >= 8, obj.RoiJson = char(roi_json); end
            if nargin >= 9, obj.Held = held; end
            % No wider than the screen
            ss = get(groot, 'ScreenSize');
            f = uifigure('Name', 'Rig calibration (pyCamSet)', 'Position', [40 60 min(1240, max(900, ss(3) - 80)) 640], ...
                'WindowStyle', 'modal', 'CloseRequestFcn', @(s, e) obj.close_window(), ...
                'Visible', rabbit_calibration.ternary(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'off', 'on'));
            obj.Figure = f;
            g = uigridlayout(f, [8 1]);
            % The file table about four rows high (it is usually one or
            % two recordings), so the results pane below shows its last
            % line
            g.RowHeight = {60, 104, 30, 30, 30, 30, 22, '1x'};
            uilabel(g, 'WordWrap', 'on', 'Text', ['Solves the four virtual cameras of the rig in mm with ' ...
                'pyCamSet (R. Laven and contributors). The cube edge sets the scale of everything measured ' ...
                'later, so give the measured value. Mark one recording "fit" to solve from, and the others ' ...
                '"holdout": the distances on those are the independent check.']);
            obj.Table = uitable(g, 'ColumnName', {'File'; 'Use for'; 'Target'; 'Squares'; 'Edge (mm)'; ...
                'Frame position'}, ...
                'ColumnEditable', [false true true true true false], ...
                'ColumnWidth', {'auto', 75, 125, 80, 110, 400}, ...
                'ColumnFormat', {'char', {'fit', 'holdout'}, rabbit_calibration.TARGET_TYPES, 'char', 'char', ...
                'char'}, ...
                'Data', cell(0, 6));
            % Squares and Edge: columns wide enough not to clip ("6.",
            % "30."), left-aligned as the text columns, and shown as text
            % (%s of the %g value: 30, 29.5, not 30.0000), as a numeric
            % cell draws a stray dot at its right edge; make_spec reads
            % them back as numbers (cell_number)
            addStyle(obj.Table, uistyle('HorizontalAlignment', 'left'), 'column', [4 5]);
            b1 = uigridlayout(g, [1 9]);
            b1.ColumnWidth = {120, 120, 100, 100, '1x', 110, 70, 110, 70};
            b1.Padding = [0 0 0 0];
            uibutton(b1, 'push', 'Text', 'Add recording...', 'ButtonPushedFcn', @(s, e) obj.add_recording(), ...
                'Tooltip', {'A FITS file or a TIFF stack.'});
            uibutton(b1, 'push', 'Text', 'Add cut folder...', 'ButtonPushedFcn', @(s, e) obj.add_cut_folder(), ...
                'Tooltip', {'A cut folder: a folder per view, View1 to View4, with cut_locations_per_view.json.'});
            uibutton(b1, 'push', 'Text', 'Remove last', 'ButtonPushedFcn', @(s, e) obj.remove_recording());
            uibutton(b1, 'push', 'Text', 'Position...', 'ButtonPushedFcn', @(s, e) obj.set_position(), ...
                'Tooltip', {'Type in where the selected recording''s frame sits in the reconstruction frame.'});
            obj.PreprocessBox = uicheckbox(b1, 'Text', 'Sauvola for Ccube', 'Value', true, ...
                'Tooltip', {['Binarise Ccube recordings before the cube is found: Sauvola (window 7 px, ' ...
                'k 0; Sauvola and Pietikainen 2000). On by default: on the rabbit ccube1 recordings it ' ...
                'was the only setting tried with which all three calibrated. Other targets are not changed.']});
            uilabel(b1, 'Text', 'Focal length (px)', 'HorizontalAlignment', 'right');
            obj.FocalField = uieditfield(b1, 'numeric', 'Value', focal_px, 'Editable', 'off', ...
                'Tooltip', {'The sparse model recipe''s focal length. Both rigs must use the same one.'});
            % the micro sign, not "um"
            uilabel(b1, 'Text', ['Pixel pitch (' char(181) 'm)'], 'HorizontalAlignment', 'right');
            obj.PitchField = uieditfield(b1, 'numeric', 'Value', 6.5, ...
                'Tooltip', {['Pixel pitch of the camera (Andor Zyla 5.5: 6.5 ' char(181) 'm). Only used to state the focal length in mm.']});
            obj.LensField = [];
            obj.PythonField = obj.path_row(g, 'Python with pyCamSet''s packages', ...
                tab.pycamset_python, @() obj.browse_python());
            obj.CheckoutField = obj.path_row(g, 'pyCamSet checkout (development branch)', ...
                tab.pycamset_checkout, @() obj.browse_checkout());
            b2 = uigridlayout(g, [1 4]);
            b2.ColumnWidth = {'1x', 110, 110, 110};
            b2.Padding = [0 0 0 0];
            uilabel(b2, 'Text', '');
            obj.RunButton = uibutton(b2, 'push', 'Text', 'Run', 'ButtonPushedFcn', @(s, e) obj.run());
            obj.CancelButton = uibutton(b2, 'push', 'Text', 'Cancel', 'Enable', 'off', ...
                'ButtonPushedFcn', @(s, e) obj.cancel());
            obj.CloseButton = uibutton(b2, 'push', 'Text', 'Close', 'ButtonPushedFcn', @(s, e) obj.close_window());
            obj.StatusLabel = uilabel(g, 'Text', 'Ready.');
            obj.ResultsArea = uitextarea(g, 'Editable', 'off', 'Value', {''});
            % prefill: the calibration recordings of the region dialog,
            % listed already (the first to fit, the others held out) and
            % placed from its line-up
            if nargin >= 10 && ~isempty(prefill)
                for k = 1:numel(prefill)
                    if exist(prefill{k}, 'file') == 2 || isfolder(prefill{k})
                        role = 'holdout';
                        if isempty(obj.Table.Data), role = 'fit'; end
                        obj.add_row(prefill{k}, role, 'PuzzleBoardCube', 7, [], '');
                    end
                end
            end
        end

        function field = path_row(obj, g, label, value, browse)
            % One labelled path with a Browse... button. A typed or browsed
            % path is kept at once, not only at Run, so that
            % Open in pyCamSet... and Link camera set... can use it
            row = uigridlayout(g, [1 3]);
            row.ColumnWidth = {260, '1x', 90};
            row.Padding = [0 0 0 0];
            uilabel(row, 'Text', label);
            field = uieditfield(row, 'text', 'Value', char(value), ...
                'ValueChangedFcn', @(s, e) obj.keep_paths());
            uibutton(row, 'push', 'Text', 'Browse...', 'ButtonPushedFcn', @(s, e) browse());
        end

        function ok = add_row(obj, path, role, type, n_points, edge_mm, ~)
            % (a 7th argument, an Edge from value from older callers, is ignored)
            %% One recording in the table, with its frame placed in the reconstruction frame
            % A measured, trusted position is used; a same-size recording
            % that could not be measured is asked about (same position or
            % typed); one of another size needs its position typed in. A
            % cancelled question leaves the recording out.
            ok = false;
            place = struct('offset', [], 'score', NaN, 'note', '', 'source', '');
            if ~isempty(obj.FrameHw)
                [p, err] = rabbit_calibration.placement(obj.Reference, obj.FrameHw, char(path), obj.RoiJson, obj.Held);
                if ~isempty(err)
                    uialert(obj.Figure, err, 'Rig calibration');
                    return;
                end
                if isempty(p.source)
                    p = obj.ask_unmeasured(char(path), p);
                    if isempty(p), return; end
                end
                place = struct('offset', p.offset, 'score', p.score, 'note', p.note, 'source', p.source);
            end
            obj.Places{end + 1} = place;
            obj.Table.Data = [obj.Table.Data; {char(path), char(role), char(type), obj.cell_text(n_points), ...
                obj.cell_text(edge_mm), place.note}];
            ok = true;
        end

        function p = ask_unmeasured(obj, path, p)
            %% The user's answer for a recording the app could not line up itself; [] when cancelled
            % In plain words; the numbers only in the fields
            [~, nm, ex] = fileparts(path);
            % One answer for all recordings of the reconstruction's size:
            % asked for the first only
            if p.same_size && ~isempty(obj.SameSizeAnswer)
                p.offset = [0 0];
                p.source = 'same frame';
                p.note = sprintf('lines up with the reconstruction recording (same size; not checked; as answered for %s)', ...
                    obj.SameSizeAnswer);
                return;
            end
            while true
                if p.same_size
                    answer = uiconfirm(obj.Figure, sprintf(['%s%s is the same size as the reconstruction ' ...
                        'recording, but the two look too different for the app to check that they line up (a cube ' ...
                        'recording rarely looks like the heart recording). It is taken to line up unless you enter a ' ...
                        'shift; the answer also holds for further recordings of this size.'], nm, ex), 'Line up the calibration recording', ...
                        'Options', {'They line up', 'Enter the shift...', 'Cancel'}, 'DefaultOption', 1, ...
                        'CancelOption', 3, 'Icon', 'warning');
                else
                    answer = 'Enter the shift...';
                end
                switch answer
                    case 'They line up'
                        p.offset = [0 0];
                        p.source = 'same frame';
                        p.note = 'lines up with the reconstruction recording (same size; not checked)';
                        obj.SameSizeAnswer = [nm ex];
                        return;
                    case 'Enter the shift...'
                        new = obj.ask_position(path, [], p.score, p.same_size);
                        if ~isempty(new)
                            p.offset = new.offset; p.source = new.source; p.note = new.note;
                            return;
                        end
                        if ~p.same_size
                            p = [];   % no shift, no recording
                            return;
                        end
                    otherwise
                        p = [];
                        return;
                end
            end
        end

        function place = ask_position(obj, path, off, score, same_size)
            %% The shift typed in for one recording, or [] when cancelled
            % off: the shift to show to start with ([] = empty fields, so
            % that a shift is never taken by pressing OK alone)
            if nargin < 5, same_size = true; end
            place = [];
            [~, nm, ex] = fileparts(path);
            prompts = rabbit_fov_position.shift_prompts([nm ex], 'reconstruction');
            if ~same_size
                prompts{1} = [sprintf(['%s%s is a different size from the reconstruction recording, and the two look ' ...
                    'too different for the app to line them up itself. '], nm, ex) prompts{1}];
            end
            prefill = {'', ''};
            if ~isempty(off), prefill = {num2str(off(1)), num2str(off(2))}; end
            rc = rabbit_fov_position.ask_typed(obj.Figure, 'Line up the calibration recording', prompts, prefill);
            if isempty(rc), return; end
            % The image match is left out: a cube and the heart match about
            % as badly at a right as at a wrong position
            note = sprintf('shifted %d px down, %d px right (typed in)', rc(1), rc(2));
            place = struct('offset', [rc(1), rc(2)], 'score', NaN, 'note', note, 'source', 'typed');
        end

        function set_position(obj)
            %% Type in where the selected (else the last) recording sits
            d = obj.Table.Data;
            if isempty(d)
                return;
            end
            row = size(d, 1);
            try
                sel = obj.Table.Selection;
                if ~isempty(sel), row = sel(1); end
            catch
                row = size(d, 1);
            end
            if isfolder(d{row, 1})
                uialert(obj.Figure, 'A cut folder is always the reconstruction frame itself.', 'Frame position');
                return;
            end
            place = obj.Places{row};
            new = obj.ask_position(d{row, 1}, place.offset, place.score);
            if isempty(new), return; end
            obj.Places{row} = new;
            obj.Table.Data{row, 6} = new.note;
        end

        function add_recording(obj)
            % Starts where the last recording was added, else next to the
            % reconstruction recording
            start = '';
            if ~isempty(obj.Table.Data)
                start = fileparts(char(obj.Table.Data{end, 1}));
            elseif ~isempty(obj.Reference)
                start = fileparts(obj.Reference);
            end
            if ~isfolder(start), start = ''; end
            [f, p] = uigetfile({'*.fits;*.fit;*.tif;*.tiff', 'Recordings'; '*.*', 'All files'}, ...
                'Calibration recording', [start filesep]);
            if isequal(f, 0), return; end
            role = 'holdout';
            if isempty(obj.Table.Data), role = 'fit'; end
            obj.add_row(fullfile(p, f), role, 'PuzzleBoardCube', 7, [], '');
        end

        function add_cut_folder(obj)
            p = uigetdir('', 'Cut folder of a calibration recording');
            if isequal(p, 0), return; end
            if exist(fullfile(p, 'cut_locations_per_view.json'), 'file') ~= 2
                uialert(obj.Figure, sprintf('%s has no cut_locations_per_view.json.', p), 'Rig calibration');
                return;
            end
            role = 'holdout';
            if isempty(obj.Table.Data), role = 'fit'; end
            obj.add_row(p, role, 'PuzzleBoardCube', 7, [], '');
        end

        function remove_recording(obj)
            if ~isempty(obj.Table.Data)
                obj.Table.Data(end, :) = [];
                obj.Places(end) = [];
            end
        end

        function browse_python(obj)
            [f, p] = uigetfile({'python*', 'Python'; '*.*', 'All files'}, 'Python with pyCamSet''s packages');
            if ~isequal(f, 0), obj.PythonField.Value = fullfile(p, f); obj.keep_paths(); end
        end

        function browse_checkout(obj)
            p = uigetdir(obj.CheckoutField.Value, 'pyCamSet checkout');
            if ~isequal(p, 0), obj.CheckoutField.Value = p; obj.keep_paths(); end
        end

        function keep_paths(obj)
            %% Keep the Python and the checkout for this dataset and this computer
            if isempty(obj.PythonField) || isempty(obj.CheckoutField), return; end
            try
                obj.Tab.set_tool_path('pycamset_python', obj.PythonField.Value);
                obj.Tab.set_tool_path('pycamset_checkout', obj.CheckoutField.Value);
                rabbit_reconstruction_tab.remember_tool_path('pycamset_python', obj.PythonField.Value);
                rabbit_reconstruction_tab.remember_tool_path('pycamset_checkout', obj.CheckoutField.Value);
            catch
                % a test double without these: kept at Run
            end
        end

        function t = cell_text(~, x)
            %% A Squares or Edge value as the table shows it: '' when empty, else %g
            t = '';
            if ischar(x) || isstring(x), t = strtrim(char(x)); return; end
            if ~isempty(x) && isfinite(x), t = sprintf('%g', x); end
        end

        function v = cell_number(~, x)
            %% A Squares or Edge cell as a number: text or number; NaN when empty or not a number
            if ischar(x) || isstring(x)
                v = str2double(strtrim(char(x)));
            elseif isempty(x)
                v = NaN;
            else
                v = double(x);
            end
        end

        function spec = make_spec(obj)
            %% The table and fields as a rabbit_calibration spec
            spec = rabbit_calibration.default_spec();
            d = obj.Table.Data;
            recs = struct('path', {}, 'role', {}, 'type', {}, 'n_points', {}, 'edge_mm', {}, ...
                'size_source', {}, 'frame_offset', {}, 'offset_note', {}, 'offset_source', {});
            for k = 1:size(d, 1)
                e = obj.cell_number(d{k, 5});
                place = struct('offset', [], 'note', '', 'source', '');
                if k <= numel(obj.Places), place = obj.Places{k}; end
                recs(end+1) = struct('path', d{k, 1}, 'role', d{k, 2}, 'type', d{k, 3}, ...
                    'n_points', obj.cell_number(d{k, 4}), 'edge_mm', e, 'size_source', '', ...
                    'frame_offset', place.offset, 'offset_note', place.note, 'offset_source', place.source); %#ok<AGROW>
            end
            spec.recordings = recs;
            spec.focal_px = obj.FocalField.Value;
            spec.pixel_pitch_um = obj.PitchField.Value;
            spec.roi_bounds = obj.Bounds;
            spec.frame_hw = obj.FrameHw;
            spec.roi_hw = obj.RoiHw;
            if ~obj.PreprocessBox.Value
                spec.preprocess = [];   % unticked: no pre-processing
            end
            spec.size_source = '';   % the table has no Edge from column
        end

        function run(obj)
            %% Run pyCamSet; the window stays live
            tab = obj.Tab;
            spec = obj.make_spec();
            [ok, err] = rabbit_calibration.check_spec(spec);
            if ~ok
                uialert(obj.Figure, err, 'Rig calibration');
                return;
            end
            tab.set_tool_path('pycamset_python', obj.PythonField.Value);
            tab.set_tool_path('pycamset_checkout', obj.CheckoutField.Value);
            rabbit_reconstruction_tab.remember_tool_path('pycamset_python', obj.PythonField.Value);
            rabbit_reconstruction_tab.remember_tool_path('pycamset_checkout', obj.CheckoutField.Value);
            obj.set_running(true);
            obj.ResultsArea.Value = {''};
            lines = {};
            cal_dir = '';
            before = obj.folders();
            % Whatever happens below, the window must come back: it is modal
            try
                obj.start_timer();
                [ok, err, cal_dir, lines] = tab.run_calibration(spec);
            catch ME
                ok = false;
                err = sprintf('The calibration stopped with an error: %s', ME.message);
                fresh = setdiff(obj.folders(), before);
                if ~isempty(fresh)
                    cal_dir = fullfile(tab.calibration_root(), fresh{end});
                    if exist(fullfile(cal_dir, 'verdict.json'), 'file') ~= 2
                        try
                            tab.record_calibration_failure(cal_dir, err);
                        catch
                        end
                    end
                end
            end
            obj.stop_timer();
            obj.LastDir = cal_dir;
            obj.LastOk = ok;
            obj.set_running(false);
            if ok
                obj.StatusLabel.Text = 'Finished.';
                obj.ResultsArea.Value = lines(:);
            else
                obj.StatusLabel.Text = 'Stopped.';
                saved = {};
                if ~isempty(cal_dir), saved = rabbit_calibration.saved_lines(cal_dir); end
                obj.ResultsArea.Value = [{err}; saved(:)];
            end
            obj.OnDone();
        end

        function names = folders(obj)
            %% The calibration folders there are now
            names = {};
            try
                d = dir(fullfile(obj.Tab.calibration_root(), 'cal_*'));
                names = sort({d([d.isdir]).name});
            catch
                names = {};
            end
        end

        function cancel(obj)
            obj.Tab.cancel_calibration();
            obj.StatusLabel.Text = 'Cancelling...';
        end

        function set_running(obj, tf)
            obj.Running = tf;
            on = rabbit_calibration.ternary(tf, 'on', 'off');
            off = rabbit_calibration.ternary(tf, 'off', 'on');
            obj.RunButton.Enable = off;
            obj.CloseButton.Enable = off;
            obj.CancelButton.Enable = on;
        end

        function start_timer(obj)
            obj.Timer = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, 'BusyMode', 'drop', ...
                'TimerFcn', @(s, e) obj.show_progress());
            start(obj.Timer);
        end

        function stop_timer(obj)
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            obj.Timer = [];
        end

        function show_progress(obj)
            %% The last PROGRESS line of the newest calibration's log
            try
                d = dir(fullfile(obj.Tab.calibration_root(), 'cal_*'));
                if isempty(d), return; end
                [~, k] = max([d.datenum]);
                txt = fileread(fullfile(d(k).folder, d(k).name, 'calibration.log'), 'Encoding', 'UTF-8');
                t = regexp(txt, 'PROGRESS \d+ ([^\r\n]*)', 'tokens');
                if ~isempty(t), obj.StatusLabel.Text = t{end}{1}; end
            catch
            end
        end

        function close_window(obj)
            if obj.Running, return; end
            obj.stop_timer();
            delete(obj.Figure);
        end
    end
end
