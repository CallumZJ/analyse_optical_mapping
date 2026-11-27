classdef rabbit_recording_rhythm
    %% The loaded recording's rhythm, as the user states it: Sinus rhythm, Paced (with its cycle) or Not stated
    % Collin Snitchler
    % 25.11.2026
    % Purpose: one place where the user says whether the loaded recording
    %          is in sinus rhythm or paced, and for a paced one its cycle
    %          length (ms) or rate (Hz), kept in ms. The app never guesses
    %          it: a new recording and an old workspace are "Not stated".
    %          While it is Not stated, the app asks once, at the first CV
    %          map or projection (ask_once; never with OM_APP_HEADLESS=1,
    %          where scripts use app.set_recording_rhythm). When Remove
    %          artefact frames finds artefacts at a steady interval, the top
    %          line suggests "Paced?"; only the user's choice marks it.
    %          Display and labelling only: no value the app computes
    %          changes with the marker.
    % Headless (OM_APP_HEADLESS=1): ask_once returns without asking, and
    %          the Paced dialog takes its answer from inputdlg (paced_dialog).
    %
    % Where the marker is kept: app.data.rhythm (a struct, see not_stated).
    % It is saved with the workspace (save_workspace keeps app.data), so a
    % workspace without a marker loads as "Not stated" (of).
    % Step 2's "Pacing cycle (ms, optional)" field shows the same cycle,
    % and typing there changes the marker (from_step2,
    % rabbit_reconstruction_ui.reconstruction_rhythm_refresh): one value,
    % two places to see it.
    %
    % The marker as recorded (record) with a projection
    % (reprojection_manifest.json and the run manifest's
    % result.reprojection), as recording_rhythm:
    %   state             'sinus', 'paced' or 'not_stated'
    %   pacing_cycle_ms   paced only, when stated
    %   pacing_hz         paced only, when it was stated as a rate
    %   stated_as         'ms' or 'Hz' (paced with a cycle only)
    %   source            'as stated' (File > Recording rhythm, or
    %                     set_recording_rhythm) or 'Step 2' (typed in
    %                     Step 2's Pacing cycle)
    %   marked_at         when it was stated (yyyy-mm-ddTHH:MM:SS)
    %   pacing_site       paced only, when stated:
    %                     one of PACING_SITES ('not known' included)
    %   detected_beat_interval_ms, detected_beats, detected_from
    %                     the median interval of the beats Average beats
    %                     found (note_beats), when there is one
    %   detected_interval_ms, cycle_mismatch_pct, cycle_mismatch_warn
    %                     the check of the stated cycle against that
    %                     interval (cycle_check; [] / false when it cannot
    %                     be made)
    %   cycle_check       the state of that check in words:
    %                     'agrees', 'differs by more than
    %                     10 %', 'not run: Average beats not run on this
    %                     recording in this session', 'not applicable: no
    %                     stated cycle', 'not applicable: not paced' or
    %                     'not applicable: rhythm not stated'
    %   rhythm_row_text   the Results box's Rhythm row, ready:
    %                     words() with the check, e.g. "Paced, 500 ms
    %                     cycle, pacing site RV epicardium (as stated;
    %                     Average beats found 500 ms, agrees)"
    %   activation_spread the near-simultaneous check of the activation map
    %                     that was projected (rabbit_cv_map.simultaneous_check:
    %                     views, iqr_ms, warn_below_ms, basis); for the
    %                     mismatch caution only
    % The field is called recording_rhythm, not rhythm: "rhythm" in those
    % records is the RHYTHM projection software (Gloschat et al. 2018).

    methods (Static)

        % ---- The marker ----

        function r = not_stated()
            %% The marker of a recording nobody has marked yet (asked: the question was put)
            r = struct('state', 'not_stated', 'pacing_cycle_ms', [], 'pacing_hz', [], ...
                'stated_as', '', 'source', '', 'marked_at', '', 'suggestion', [], 'asked', false, ...
                'pacing_site', '', 'detected', [], 'detected_interval_ms', [], 'cycle_mismatch_pct', [], ...
                'cycle_mismatch_warn', false);
        end

        function s = PACING_SITES()
            %% The pacing sites the Paced dialog offers
            s = {'RV epicardium', 'LV epicardium', 'apex', 'base', 'atrium', 'other', 'not known'};
        end

        function f = CYCLE_MISMATCH()
            %% The stated cycle and the detected beat interval warn when they differ by more than this share
            f = 0.10;
        end

        function site = parse_site(txt)
            %% A pacing site from text (any case): one of PACING_SITES; blank is 'not known'
            % Errors: analyse_om:Rhythm:BadSite, with the list.
            t = lower(strtrim(char(txt)));
            sites = rabbit_recording_rhythm.PACING_SITES();
            if isempty(t), site = 'not known'; return; end
            k = find(strcmpi(sites, t), 1);
            if isempty(k)
                error('analyse_om:Rhythm:BadSite', '"%s" is not a pacing site. Type one of: %s.', char(txt), ...
                    strjoin(sites, ', '));
            end
            site = sites{k};
        end

        function r = unreadable()
            %% The marker of a projection whose record is there but cannot be read
            r = rabbit_recording_rhythm.not_stated();
            r.state = 'unreadable';
        end

        function r = make(state, amount, unit, source, site)
            %% A marker from what the user chose: state, and for Paced the cycle (ms) or rate (Hz)
            % state:  'Sinus rhythm' / 'sinus', 'Paced' / 'paced',
            %         'Not stated' / 'not_stated' (any case)
            % amount: [] / '' (Paced, cycle not stated), a number, or text
            %         such as '500', '500 ms' or '2 Hz' (unit then ignored);
            %         not used for Sinus rhythm (no cycle)
            % unit:   'ms' (default) or 'Hz'
            % source: 'as stated' (default), 'Step 2', or 'record' (read
            %         back from an older projection record)
            % site:   Paced only: the pacing site (PACING_SITES, any
            %         case; blank text 'not known'); [] or omitted: not
            %         given (an older marker, Step 2)
            % A marker the user made counts as asked: the question is not
            % put again. Errors: analyse_om:Rhythm:BadState,
            % analyse_om:Rhythm:BadCycle (with a message that says what to
            % type).
            if nargin < 2, amount = []; end
            if nargin < 3 || isempty(unit), unit = 'ms'; end
            if nargin < 4 || isempty(source), source = 'as stated'; end
            if nargin < 5, site = []; end
            r = rabbit_recording_rhythm.not_stated();
            r.asked = true;
            key = lower(regexprep(strtrim(char(state)), '[\s_]+', ' '));
            switch key
                case {'sinus', 'sinus rhythm'}
                    r.state = 'sinus';
                case {'paced', 'pacing', 'paced...'}
                    r.state = 'paced';
                case {'not stated', ''}
                    return;
                otherwise
                    error('analyse_om:Rhythm:BadState', ['"%s" is not a rhythm. Choose Sinus rhythm, Paced ' ...
                        'or Not stated.'], char(state));
            end
            r.source = char(source);
            r.marked_at = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
            if strcmp(r.state, 'sinus'), return; end
            [ms, hz, as] = rabbit_recording_rhythm.parse_cycle(amount, unit);
            r.pacing_cycle_ms = ms;
            r.pacing_hz = hz;
            r.stated_as = as;
            if ischar(site) || isstring(site), r.pacing_site = rabbit_recording_rhythm.parse_site(site); end
        end

        function [ms, hz, as] = parse_cycle(amount, unit)
            %% A cycle in ms from a number or text: '500', '500 ms', '2 Hz'; [] for blank
            % A bare number is in unit ('ms' unless 'Hz'). 0, a negative
            % number or text that is not a number is refused.
            ms = []; hz = []; as = '';
            if nargin < 2 || isempty(unit), unit = 'ms'; end
            if isempty(amount), return; end
            if ischar(amount) || isstring(amount)
                txt = lower(strtrim(char(amount)));
                if isempty(txt), return; end
                tok = regexp(txt, '^([-+]?[\d.]+(?:e[-+]?\d+)?)\s*(ms|hz)?$', 'tokens', 'once');
                if isempty(tok)
                    rabbit_recording_rhythm.bad_cycle(amount);
                end
                x = str2double(tok{1});
                if numel(tok) > 1 && ~isempty(tok{2}), unit = tok{2}; end
            else
                x = amount;
            end
            if ~isnumeric(x) || ~isscalar(x) || ~isreal(x) || ~isfinite(x) || x <= 0
                rabbit_recording_rhythm.bad_cycle(amount);
            end
            x = double(x);
            if strcmpi(unit, 'hz')
                hz = x;
                ms = 1000 / x;
                as = 'Hz';
            else
                ms = x;
                as = 'ms';
            end
        end

        function bad_cycle(amount)
            %% Refuse a cycle the app cannot read, saying what to type
            if ischar(amount) || isstring(amount)
                shown = char(amount);
            else
                shown = strtrim(evalc('disp(amount)'));
            end
            error('analyse_om:Rhythm:BadCycle', ['"%s" is not a pacing cycle. Type the cycle length in ms ' ...
                '(for example 500) or the rate in Hz (for example 2 Hz), or leave it blank when it is not known.'], shown);
        end

        function r = of(data)
            %% The marker kept in app.data; "Not stated" when there is none (an old workspace)
            r = rabbit_recording_rhythm.not_stated();
            if ~isstruct(data) || ~isfield(data, 'rhythm') || ~isstruct(data.rhythm) || ...
                    ~isfield(data.rhythm, 'state')
                return;
            end
            s = data.rhythm;
            if ~any(strcmp(char(s.state), {'sinus', 'paced', 'not_stated'})), return; end
            for f = fieldnames(r)'
                if isfield(s, f{1}), r.(f{1}) = s.(f{1}); end
            end
            r.state = char(r.state);
            r.asked = isequal(r.asked, true) || isequal(r.asked, 1);
            if isempty(r.pacing_site), r.pacing_site = ''; end
            r.pacing_site = char(r.pacing_site);
            % the beat interval Average beats found for this recording
            r.detected = [];
            if isfield(data, 'beat_interval') && isstruct(data.beat_interval) && isfield(data.beat_interval, 'ms')
                r.detected = data.beat_interval;
            end
            [r.detected_interval_ms, r.cycle_mismatch_pct, r.cycle_mismatch_warn] = rabbit_recording_rhythm.cycle_check(r);
        end

        function r = of_app(app)
            %% The app's marker (of), with the beat interval of the beats Average beats found when app.data has none
            % app.data.beat_interval is kept by note_beats; app.data put
            % back without it (an older workspace or checkpoint) loses it,
            % while the beat
            % times Average beats found (app.activation_times, set only by
            % Average beats and cleared for a new recording) are still
            % there. Their median interval, as note_beats takes it.
            r = rabbit_recording_rhythm.of(app.data);
            if isstruct(r.detected) && isfield(r.detected, 'ms'), return; end
            try
                t = double(app.activation_times(:));
            catch
                return;   % a test double without activation_times
            end
            t = t(isfinite(t));
            if numel(t) < 2, return; end
            r.detected = struct('ms', 1000 * median(diff(t)), 'n_beats', numel(t), 'from', 'Average beats');
            [r.detected_interval_ms, r.cycle_mismatch_pct, r.cycle_mismatch_warn] = rabbit_recording_rhythm.cycle_check(r);
        end

        function r = from_record(s)
            %% A marker read back from a record (recording_rhythm); "Not stated" if none can be read
            r = rabbit_recording_rhythm.not_stated();
            if ~isstruct(s) || ~isfield(s, 'state'), return; end
            r = rabbit_recording_rhythm.of(struct('rhythm', s));
            % the beats found, as record() keeps them (detected_interval_ms,
            % detected_beats, detected_from), so the cycle check and its
            % WARN read back from a record too
            if isfield(s, 'detected_interval_ms') && isnumeric(s.detected_interval_ms) && isscalar(s.detected_interval_ms)
                det = struct('ms', double(s.detected_interval_ms), 'n_beats', [], 'from', 'Average beats');
                if isfield(s, 'detected_beats') && isnumeric(s.detected_beats) && isscalar(s.detected_beats)
                    det.n_beats = double(s.detected_beats);
                end
                if isfield(s, 'detected_from') && ~isempty(s.detected_from), det.from = char(s.detected_from); end
                r.detected = det;
                [r.detected_interval_ms, r.cycle_mismatch_pct, r.cycle_mismatch_warn] = rabbit_recording_rhythm.cycle_check(r);
            end
        end

        function s = record(r, spread)
            %% The marker as recorded with a projection (recording_rhythm); the suggestion is never recorded
            % spread: the near-simultaneous check of the map projected
            % (spread_of_app), or [] when there is none
            s = struct('state', r.state);
            if strcmp(r.state, 'paced') && ~isempty(r.pacing_cycle_ms)
                s.pacing_cycle_ms = r.pacing_cycle_ms;
                if ~isempty(r.pacing_hz), s.pacing_hz = r.pacing_hz; end
                s.stated_as = r.stated_as;
            end
            % The pacing site, the beat interval found and the check of
            % the two (field names as in the class header)
            if strcmp(r.state, 'paced')
                s.pacing_site = 'not known';
                if isfield(r, 'pacing_site') && ~isempty(r.pacing_site), s.pacing_site = r.pacing_site; end
            end
            [s.detected_interval_ms, s.cycle_mismatch_pct, s.cycle_mismatch_warn] = rabbit_recording_rhythm.cycle_check(r);
            if isfield(r, 'detected') && isstruct(r.detected) && isfield(r.detected, 'ms')
                s.detected_beats = r.detected.n_beats;
                s.detected_from = r.detected.from;
            end
            if ~strcmp(r.state, 'not_stated')
                s.source = r.source;
                s.marked_at = r.marked_at;
            end
            % The check said in words, also when it
            % was not made, and the Rhythm row ready for the Results box
            [s.cycle_check, s.rhythm_row_text] = rabbit_recording_rhythm.check_words(r);
            if nargin > 1 && isstruct(spread) && isfield(spread, 'iqr_ms')
                s.activation_spread = struct('views', {cellstr(spread.views)}, 'iqr_ms', double(spread.iqr_ms(:)'), ...
                    'warn_below_ms', spread.warn_below_ms, 'basis', spread.basis);
            end
        end

        % ---- Words ----

        function txt = words(r)
            %% The marker in words: "Paced, 500 ms cycle (as stated)", "Sinus rhythm (as stated)", "Not stated"
            switch r.state
                case 'sinus'
                    txt = 'Sinus rhythm (as stated)';
                case 'paced'
                    if isempty(r.pacing_cycle_ms)
                        txt = 'Paced, cycle not stated (as stated)';
                    elseif strcmp(r.stated_as, 'Hz')
                        txt = sprintf('Paced, %s ms cycle, %s Hz (as stated)', ...
                            rabbit_recording_rhythm.num(r.pacing_cycle_ms), rabbit_recording_rhythm.num(r.pacing_hz));
                    else
                        txt = sprintf('Paced, %s ms cycle (as stated)', rabbit_recording_rhythm.num(r.pacing_cycle_ms));
                    end
                    % The pacing site; a marker without one says "pacing
                    % site not known" (missing information is shown, not
                    % hidden)
                    site = 'not known';
                    if isfield(r, 'pacing_site') && ~isempty(r.pacing_site), site = char(r.pacing_site); end
                    txt = strrep(txt, ' (as stated)', sprintf(', pacing site %s (as stated)', site));
                    if strcmp(r.source, 'Step 2')
                        txt = strrep(txt, '(as stated)', '(as stated in Step 2)');
                    elseif strcmp(r.source, 'record')
                        % a projection made before the marker, with a cycle recorded
                        txt = strrep(txt, '(as stated)', '(as recorded with the run)');
                    end
                case 'unreadable'
                    txt = 'could not be read';
                otherwise
                    txt = 'Not stated';
            end
        end

        function [state, row] = check_words(r)
            %% The cycle check's state in words, and the Rhythm row with it
            % state: see cycle_check in the header. row: words(r), with
            % "; Average beats found 500 ms, agrees" inside its closing
            % bracket when the interval is known, or "; beat interval not
            % checked (Average beats not run on this recording in this
            % session)" after it when a stated cycle could not be checked.
            row = rabbit_recording_rhythm.words(r);
            [d, pct, warn] = rabbit_recording_rhythm.cycle_check(r);
            switch r.state
                case 'paced'
                    if isempty(r.pacing_cycle_ms)
                        state = 'not applicable: no stated cycle';
                    elseif isempty(d)
                        state = 'not run: Average beats not run on this recording in this session';
                    elseif warn
                        state = sprintf('differs by more than %.0f %%', 100 * rabbit_recording_rhythm.CYCLE_MISMATCH());
                    else
                        state = 'agrees';
                    end
                case 'sinus'
                    state = 'not applicable: not paced';
                otherwise
                    state = 'not applicable: rhythm not stated';
            end
            if ~strcmp(r.state, 'paced') || ~endsWith(row, ')'), return; end
            if isempty(d)
                if ~isempty(r.pacing_cycle_ms)
                    row = [row '; beat interval not checked (Average beats not run on this recording in this session)'];
                end
                return;
            end
            found = sprintf('Average beats found %.0f ms', d);
            if isempty(pct)
                % no stated cycle: the interval found, nothing to agree with
            elseif warn
                found = sprintf('%s, %.0f %% different', found, pct);
            else
                found = [found ', agrees'];
            end
            row = [row(1:end - 1) '; ' found ')'];
        end

        function txt = line_of(r)
            %% "Rhythm: <words>": the captions, the footers and History
            txt = ['Rhythm: ' rabbit_recording_rhythm.words(r)];
        end

        function txt = status(r)
            %% The marker in the main window's top line, with the suggestion when there is one
            txt = rabbit_recording_rhythm.line_of(r);
            if strcmp(r.state, 'not_stated') && isstruct(r.suggestion) && ~isempty(r.suggestion)
                txt = sprintf('%s (Paced? %s; File > Recording rhythm)', txt, r.suggestion.why);
            elseif strcmp(r.state, 'not_stated')
                txt = [txt ' (File > Recording rhythm)'];
            end
        end

        function t = num(x)
            %% A number without trailing zeros: 500, 333.3, 2.5
            t = regexprep(sprintf('%.1f', x), '\.0$', '');
        end

        % ---- Cautions (display only) ----

        function s = spread_of_app(app)
            %% The near-simultaneous check of the app's activation map, [] when it cannot be made
            % The same basis as the CV tab's warning
            % (rabbit_cv_map.simultaneous_check: each view's IQR against
            % SIMULTANEOUS_IQR_MS), over the activation times the CV map
            % would take (values below 0 left out); single-view data have
            % one IQR over the whole map. [] without a map, or when its
            % pixels cannot be given to the views.
            % One value. The CV map's own check (the map
            % its fit used, smoothed when it was; processed_data.
            % CV_activation_spread) when there is one, so the projection's
            % two records agree; else the activation map as it is, with a
            % basis that says so.
            s = rabbit_recording_rhythm.cv_spread_of_app(app);
            if isstruct(s) && isfield(s, 'iqr_ms'), return; end
            s = [];
            try
                act = app.processed_data.activation_map;
                if isempty(act), return; end
                act(act < 0) = NaN;
                if strcmp(rabbit_calibration_scale.layout(app), 'views')
                    [view_of_col, why] = rabbit_calibration_scale.column_views(app);
                    if ~isempty(why) || numel(view_of_col) ~= size(act, 2), return; end
                    V = repmat(view_of_col, size(act, 1), 1);
                else
                    V = ones(size(act));
                end
                S = [];
                try
                    S = rabbit_calibration_scale.pixel_map(app);   % each view's limit from its size
                catch
                end
                s = rabbit_cv_map.simultaneous_check(act, V, S);
                s.basis = ['IQR (25-75 %) of the activation times of each view of the activation map as ' ...
                    'projected (not smoothed)'];
            catch
                s = [];
            end
        end

        function txt = mismatch(r, spread)
            %% The caution when the marker and the data disagree; '' when they do not
            % Marked paced, but every view with values activates nearly
            % simultaneously on the near-simultaneous warning's own basis
            % (spread: rabbit_cv_map.simultaneous_check, or the
            % activation_spread a record keeps): a paced wave usually takes
            % longer to cross a view. A caution only.
            txt = '';
            if ~strcmp(r.state, 'paced') || ~isstruct(spread) || ~isfield(spread, 'iqr_ms') || ...
                    ~isfield(spread, 'views'), return; end
            s = spread.iqr_ms;
            if iscell(s), s = cellfun(@rabbit_reconstruction_tab.nan_if_empty, s); end
            s = double(s(:)');
            names = spread.views;
            if ischar(names) || isstring(names), names = cellstr(names); end
            if isempty(names), names = {''}; end
            if numel(names) ~= numel(s), return; end
            % each view's limit as recorded (its size / 3 mm/ms), else the
            % fixed 10 ms of an older record
            lim = rabbit_reconstruction_tab.SIMULTANEOUS_IQR_MS;
            per_view = false;
            if isfield(spread, 'warn_below_ms')
                l = spread.warn_below_ms;
                if iscell(l), l = cellfun(@rabbit_reconstruction_tab.nan_if_empty, l); end
                l = double(l(:)');
                if numel(l) == numel(s) && ~all(l == lim)
                    lim = l; per_view = true;
                elseif ~isempty(l)
                    lim = l(1);
                end
            end
            if isscalar(lim), lim = repmat(lim, 1, numel(s)); end
            have = isfinite(s);
            if ~any(have) || any(s(have) >= lim(have)), return; end
            parts = {};
            for k = find(have)
                who = names{k};
                if isempty(who), who = 'the map'; end
                if per_view
                    parts{end + 1} = sprintf('%s %d ms < %s ms', who, round(s(k)), num2str(lim(k), 2)); %#ok<AGROW>
                else
                    parts{end + 1} = sprintf('%s %d ms', who, round(s(k))); %#ok<AGROW>
                end
            end
            if per_view
                % the limit in physics words
                txt = sprintf(['Marked as paced, but every view activates nearly simultaneously (middle half within ' ...
                    'the time it takes at 1.5 m/s, view size / 3: %s). Check the rhythm marker (File > Recording rhythm).'], ...
                    strjoin(parts, ', '));
            else
                txt = sprintf(['Marked as paced, but every view activates nearly simultaneously (middle half within ' ...
                    '%d ms: %s). Check the rhythm marker (File > Recording rhythm).'], lim(1), strjoin(parts, ', '));
            end
        end

        function txt = sinus_cv_note()
            %% The CV words for a recording marked Sinus rhythm
            % the near-simultaneous limit in physics words
            txt = ['Sinus rhythm: where a view activates nearly simultaneously (middle half within the time it ' ...
                'takes at 1.5 m/s, view size / 3), CV is an apparent speed, not conduction speed.'];
        end

        function lines = cv_lines(r, spread)
            %% The rhythm lines under a CV result (Conduction Velocity tab, Visualise CV caption)
            lines = {rabbit_recording_rhythm.line_of(r)};
            if strcmp(r.state, 'sinus'), lines{end + 1} = rabbit_recording_rhythm.sinus_cv_note(); end
            c = rabbit_recording_rhythm.mismatch(r, spread);
            if ~isempty(c), lines{end + 1} = ['Caution: ' c]; end
            w = rabbit_recording_rhythm.cycle_warning(r);   % stated cycle vs beats found
            if ~isempty(w), lines{end + 1} = w; end
        end

        function txt = cycle_warning(r)
            %% 'WARN Rhythm  stated cycle ...' when the stated cycle and the beats found differ by more than 10 %; else ''
            % Labelling only: marked paced
            % with a cycle, and Average beats found the beats' median
            % interval (r.detected, from note_beats). The difference is
            % taken against the stated cycle.
            txt = '';
            [d, pct, warn] = rabbit_recording_rhythm.cycle_check(r);
            if ~warn, return; end
            % the detected interval's source named in the words;
            % the number of intervals only when it is known (a record
            % without detected_beats)
            how = sprintf('beat interval from %s', r.detected.from);
            if isfield(r.detected, 'n_beats') && ~isempty(r.detected.n_beats)
                how = sprintf('%s, median of %d intervals', how, r.detected.n_beats - 1);
            end
            txt = sprintf(['WARN Rhythm  stated cycle %s ms, detected %s ms (%s): %.0f %% different (more than %.0f %%); ' ...
                'check the rhythm marker (File > Recording rhythm) and the beats'], ...
                rabbit_recording_rhythm.num(r.pacing_cycle_ms), rabbit_recording_rhythm.num(d), how, pct, ...
                100 * rabbit_recording_rhythm.CYCLE_MISMATCH());
        end

        function [detected_ms, pct, warn] = cycle_check(r)
            %% The detected beat interval (ms), its difference from the stated cycle (% of the cycle) and the warning flag
            % [] for what cannot be given: no beats found, or not paced
            % with a cycle (then warn is false).
            detected_ms = []; pct = []; warn = false;
            if ~isfield(r, 'detected') || ~isstruct(r.detected) || ~isfield(r.detected, 'ms'), return; end
            d = double(r.detected.ms);
            if ~(isscalar(d) && isfinite(d) && d > 0), return; end
            detected_ms = d;
            if ~strcmp(r.state, 'paced') || isempty(r.pacing_cycle_ms), return; end
            c = double(r.pacing_cycle_ms);
            pct = 100 * abs(c - d) / c;
            warn = pct > 100 * rabbit_recording_rhythm.CYCLE_MISMATCH();
        end

        function note_beats(app, times_s)
            %% Average beats found beats at times_s (s): keep their median interval for the cycle check
            % Kept in app.data.beat_interval (saved with a workspace;
            % cleared for a new recording by reset). History says it, and
            % the WARN when it disagrees with a stated cycle.
            t = double(times_s(:));
            t = t(isfinite(t));
            if numel(t) < 2, return; end
            app.data.beat_interval = struct('ms', 1000 * median(diff(t)), 'n_beats', numel(t), 'from', 'Average beats');
            rabbit_recording_rhythm.history(app, sprintf('Beats found by Average beats: %d, median interval %s ms.', ...
                numel(t), rabbit_recording_rhythm.num(app.data.beat_interval.ms)));
            w = rabbit_recording_rhythm.cycle_warning(rabbit_recording_rhythm.of(app.data));
            if ~isempty(w), rabbit_recording_rhythm.history(app, w); end
        end

        function s = cv_spread_of_app(app)
            %% The near-simultaneous check the last CV map recorded (processed_data.CV_activation_spread), else []
            s = [];
            try
                if isfield(app.processed_data, 'CV_activation_spread') && isstruct(app.processed_data.CV_activation_spread)
                    s = app.processed_data.CV_activation_spread;
                end
            catch
                s = [];
            end
        end

        % ---- Suggestions (never taken without the user) ----

        function s = suggest_from_artefacts(locations, fps)
            %% "Paced?" from the frames Remove artefact frames found; [] when they are not steady
            % Steady: at least 3 artefacts, their intervals within 10 % of
            % their median.
            s = [];
            if numel(locations) < 3 || isempty(fps) || ~isfinite(fps) || fps <= 0, return; end
            d = diff(double(locations(:))) / fps * 1000;
            ms = median(d);
            if ms <= 0 || any(abs(d - ms) > 0.1 * ms), return; end
            s = struct('pacing_cycle_ms', ms, 'why', sprintf('pacing artefacts about every %s ms', ...
                rabbit_recording_rhythm.num(ms)), 'from', 'Remove artefact frames');
        end

        % ---- The app side ----

        function mark(app, r, how)
            %% Keep the marker in app.data, say it in History, and show it in the top line and Step 2
            % how: 'marked' (the user chose it), 'load' (a new recording),
            % 'workspace' (a workspace was loaded), 'quiet' (no History line)
            if nargin < 3, how = 'marked'; end
            app.data.rhythm = r;
            switch how
                case 'marked'
                    rabbit_recording_rhythm.history(app, ['Rhythm marked: ' rabbit_recording_rhythm.words(r)]);
                    w = rabbit_recording_rhythm.cycle_warning(rabbit_recording_rhythm.of(app.data));   % stated cycle vs beats found
                    if ~isempty(w), rabbit_recording_rhythm.history(app, w); end
                case 'load'
                    rabbit_recording_rhythm.history(app, ['Rhythm: ' rabbit_recording_rhythm.words(r) ...
                        ' (mark it with File > Recording rhythm)']);
                case 'workspace'
                    rabbit_recording_rhythm.history(app, ['Rhythm (from the workspace): ' rabbit_recording_rhythm.words(r)]);
            end
            try
                if ~isempty(app.file_info.file), app.tool_tip_update(); end
            catch
                % no top line before a file is loaded
            end
            try
                app.recon.reconstruction_rhythm_refresh();
            catch
                % a test double without the Reconstruction tab
            end
        end

        function reset(app)
            %% A new recording starts "Not stated" (no History line: the load writes its own)
            rabbit_recording_rhythm.mark(app, rabbit_recording_rhythm.not_stated(), 'quiet');
            if isfield(app.data, 'beat_interval'), app.data = rmfield(app.data, 'beat_interval'); end   % the old recording's beats
            rabbit_recording_rhythm.forget_beat_times(app);   % of_app reads them
        end

        function forget_beat_times(app)
            %% The beat times of the last Average beats (app.activation_times) are not this recording's: clear them
            % A new recording (reset) and a loaded workspace (which does
            % not keep them)
            try
                app.activation_times = [];
            catch
                % a test double without activation_times
            end
        end

        function after_load(app)
            %% After a recording has loaded: "Not stated" in History; no question (it is asked at the first CV map or projection)
            rabbit_recording_rhythm.mark(app, rabbit_recording_rhythm.of(app.data), 'load');
        end

        function from_step2(app, txt)
            %% Step 2's Pacing cycle was changed: the same value, so the marker follows
            % A number: Paced with that cycle (as stated in Step 2).
            % Blank: a Paced marker keeps Paced with no cycle; any other
            % marker is left as it is.
            r = rabbit_recording_rhythm.of(app.data);
            if isempty(strtrim(char(txt)))
                if strcmp(r.state, 'paced') && ~isempty(r.pacing_cycle_ms)
                    rabbit_recording_rhythm.mark(app, rabbit_recording_rhythm.make('paced', [], 'ms', 'Step 2'));
                end
                return;
            end
            n = rabbit_recording_rhythm.make('paced', txt, 'ms', 'Step 2');
            if ~strcmp(r.state, 'paced') || abs(r.pacing_cycle_ms - n.pacing_cycle_ms) > 0.05 || isempty(r.pacing_cycle_ms)
                rabbit_recording_rhythm.mark(app, n);
            end
        end

        function note_artefacts(app, locations)
            %% Remove artefact frames found artefacts: keep a "Paced?" suggestion when the marker is Not stated
            r = rabbit_recording_rhythm.of(app.data);
            if ~strcmp(r.state, 'not_stated'), return; end
            s = rabbit_recording_rhythm.suggest_from_artefacts(locations, app.data.fps);
            if isempty(s), return; end
            r.suggestion = s;
            rabbit_recording_rhythm.mark(app, r, 'quiet');
            rabbit_recording_rhythm.history(app, sprintf(['Paced? %s were found. The rhythm is still Not stated: ' ...
                'mark it with File > Recording rhythm.'], s.why));
        end

        function menu = attach_menu(app, file_menu)
            %% File > Recording rhythm..., right after Load file partially
            menu = findall(file_menu, 'Tag', 'RecordingRhythmMenu');
            if ~isempty(menu), return; end
            menu = uimenu(file_menu, 'Text', 'Recording rhythm...', 'Tag', 'RecordingRhythmMenu', ...
                'MenuSelectedFcn', @(~, ~) rabbit_recording_rhythm.ask(app));
            try
                % A menu lists its children last-made first (as
                % rabbit_reconstruction_ui.place_child): in the order shown
                kids = flipud(file_menu.Children);
                kids(kids == menu) = [];
                k = find(kids == app.LoadfilepartiallyMenu, 1);
                if ~isempty(k)
                    kids = [kids(1:k); menu; kids(k + 1:end)];
                    file_menu.Children = flipud(kids);
                end
            catch
                % left at the end of the menu
            end
        end

        function ask_once(app)
            %% While the rhythm is Not stated, the question once per recording (first CV map or projection)
            % Never with OM_APP_HEADLESS=1 (scripts use
            % app.set_recording_rhythm), and not again once it was put.
            if strcmp(getenv('OM_APP_HEADLESS'), '1'), return; end
            r = rabbit_recording_rhythm.of(app.data);
            if ~strcmp(r.state, 'not_stated') || r.asked, return; end
            r.asked = true;
            app.data.rhythm = r;
            rabbit_recording_rhythm.ask(app);
        end

        function ask(app)
            %% The question: Sinus rhythm, Paced... or Not stated; for Paced, the cycle or rate
            % Closing the question, or Cancel in the cycle dialog, keeps
            % the marker as it was. A "Paced?" suggestion is said, and its
            % cycle offered, but only Paced... (the user's choice) marks the
            % recording paced.
            fig = app.opticalmappingUIFigure;
            if isempty(app.data.image_stack) && isempty(app.processed_data.image_stack)
                uialert(fig, 'Load a recording first: the rhythm is marked for the loaded recording.', 'Recording rhythm');
                return;
            end
            r = rabbit_recording_rhythm.of(app.data);
            msg = sprintf('Is this recording in sinus rhythm or paced?\nNow: %s.', rabbit_recording_rhythm.words(r));
            if strcmp(r.state, 'not_stated') && isstruct(r.suggestion) && ~isempty(r.suggestion)
                msg = sprintf('%s\nPaced? %s. Choose Paced... to confirm it.', msg, r.suggestion.why);
            end
            msg = sprintf(['%s\n\nIt is shown with the results and saved pictures, and recorded with each ' ...
                'projection. No value is changed. Later: File > Recording rhythm.'], msg);
            current = struct('sinus', 'Sinus rhythm', 'paced', 'Paced...', 'not_stated', 'Not stated');
            choice = uiconfirm(fig, msg, 'Recording rhythm', 'Options', {'Sinus rhythm', 'Paced...', 'Not stated'}, ...
                'DefaultOption', current.(r.state), 'CancelOption', current.(r.state));
            if strcmp(choice, current.(r.state)) && ~strcmp(choice, 'Paced...')
                % the same as now (or the question closed): nothing to mark
                if ~r.asked
                    r.asked = true;
                    app.data.rhythm = r;
                end
                return;
            end
            if strcmp(choice, 'Paced...')
                def = '';
                def_site = '';
                if strcmp(r.state, 'paced') && ~isempty(r.pacing_site), def_site = r.pacing_site; end
                if strcmp(r.state, 'paced') && ~isempty(r.pacing_cycle_ms)
                    def = rabbit_recording_rhythm.num(r.pacing_cycle_ms);
                    if strcmp(r.stated_as, 'Hz'), def = [rabbit_recording_rhythm.num(r.pacing_hz) ' Hz']; end
                elseif isstruct(r.suggestion) && ~isempty(r.suggestion) && ~isempty(r.suggestion.pacing_cycle_ms)
                    def = rabbit_recording_rhythm.num(r.suggestion.pacing_cycle_ms);
                end
                while true
                    % the cycle and the pacing site, the site from a
                    % drop-down (paced_dialog)
                    a = rabbit_recording_rhythm.paced_dialog(def, def_site);
                    if isempty(a), return; end   % Cancel: as it was
                    site = [];
                    if numel(a) >= 2, site = a{2}; end   % a script's answer may give the cycle only
                    try
                        n = rabbit_recording_rhythm.make('paced', a{1}, 'ms', 'as stated', site);
                        break;
                    catch ME
                        uialert(fig, ME.message, 'Recording rhythm', 'Icon', 'warning');
                        def = a{1};
                        if numel(a) >= 2, def_site = a{2}; end
                        if strcmp(getenv('OM_APP_HEADLESS'), '1'), return; end   % no loop without a user
                    end
                end
            else
                n = rabbit_recording_rhythm.make(choice);
            end
            rabbit_recording_rhythm.mark(app, n);
        end

        function a = paced_dialog(def, def_site)
            %% The Paced dialog: the cycle typed, the site from a drop-down; {cycle, site}, or {} for Cancel
            % The pacing site is chosen from PACING_SITES, not typed;
            % "Blank: not known." is said once, for the cycle. With
            % OM_APP_HEADLESS=1 the answer comes from inputdlg (scripts and
            % probes queue {cycle, site} there) and is put through the
            % dialog's controls; a site that is not in the list is passed
            % on as typed, so make() refuses it. A script's
            % answer with the cycle only gives {cycle} (site not given).
            [d, ctl] = rabbit_recording_rhythm.paced_dialog_figure(def, def_site, ...
                ~strcmp(getenv('OM_APP_HEADLESS'), '1'));
            cleanup = onCleanup(@() delete(d(isvalid(d)))); %#ok<NASGU>
            if strcmp(getenv('OM_APP_HEADLESS'), '1')
                a = inputdlg({ctl.cycle_label.Text, ctl.site_label.Text}, d.Name, [1 50], {def, def_site});
                if isempty(a), a = {}; return; end
                ctl.cycle.Value = char(a{1});
                if numel(a) < 2, a = {ctl.cycle.Value}; return; end
                try
                    ctl.site.Value = rabbit_recording_rhythm.parse_site(a{2});
                catch
                    a = {ctl.cycle.Value, char(a{2})};   % refused by make(), as typed
                    return;
                end
                a = {ctl.cycle.Value, ctl.site.Value};
                return;
            end
            uiwait(d);
            a = {};
            if isvalid(d) && isappdata(d, 'om_paced_answer'), a = getappdata(d, 'om_paced_answer'); end
        end

        function [d, ctl] = paced_dialog_figure(def, def_site, visible)
            %% The Paced dialog's window and controls (cycle field, site drop-down, OK, Cancel)
            sites = rabbit_recording_rhythm.PACING_SITES();
            if isempty(def_site) || ~any(strcmp(sites, char(def_site))), def_site = 'not known'; end
            d = uifigure('Name', 'Recording rhythm: paced', 'Position', [300 300 520 150], ...
                'WindowStyle', 'modal', 'Visible', 'off', 'Tag', 'RecordingRhythmPacedDialog');
            g = uigridlayout(d, [4 2], 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'fit', 'fit', 'fit', 'fit'});
            ctl.cycle_label = uilabel(g, 'Text', 'Pacing cycle in ms (e.g. 500), or rate in Hz (e.g. 2 Hz). Blank: not known.', ...
                'WordWrap', 'on');
            ctl.cycle_label.Layout.Row = 1; ctl.cycle_label.Layout.Column = [1 2];
            ctl.cycle = uieditfield(g, 'text', 'Value', char(def), 'Tag', 'PacedCycleField');
            ctl.cycle.Layout.Row = 2; ctl.cycle.Layout.Column = 2;
            cyc_name = uilabel(g, 'Text', 'Cycle or rate');
            cyc_name.Layout.Row = 2; cyc_name.Layout.Column = 1;
            ctl.site_label = uilabel(g, 'Text', 'Pacing site');
            ctl.site_label.Layout.Row = 3; ctl.site_label.Layout.Column = 1;
            ctl.site = uidropdown(g, 'Items', sites, 'Value', char(def_site), 'Tag', 'PacedSiteDropDown');
            ctl.site.Layout.Row = 3; ctl.site.Layout.Column = 2;
            b = uigridlayout(g, [1 3], 'ColumnWidth', {'1x', 80, 80}, 'Padding', [0 0 0 0]);
            b.Layout.Row = 4; b.Layout.Column = [1 2];
            ctl.ok = uibutton(b, 'Text', 'OK', 'ButtonPushedFcn', @(~, ~) answer({ctl.cycle.Value, ctl.site.Value}));
            ctl.ok.Layout.Column = 2;
            ctl.cancel = uibutton(b, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) answer({}));
            ctl.cancel.Layout.Column = 3;
            d.CloseRequestFcn = @(~, ~) answer({});
            d.Visible = matlab.lang.OnOffSwitchState(logical(visible));
            function answer(a)
                setappdata(d, 'om_paced_answer', a);
                uiresume(d);
            end
        end

        function history(app, txt)
            %% One line in the History tab
            try
                app.history_field.Value{end + 1, 1} = txt;
            catch
                % a test double without History
            end
        end
    end
end
