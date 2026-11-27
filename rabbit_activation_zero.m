classdef rabbit_activation_zero
    %% What time 0 of an activation map is, recorded with the map
    % Collin Snitchler
    % 25.11.2026
    % Purpose: the activation map's method and its zero are recorded with the
    %          map (processed_data.activation_zero, so a workspace keeps it)
    %          and with its projection (reprojection_manifest.json
    %          activation_zero), so that a label can say "ms from start of
    %          averaged window" only when that is true. It is true for the
    %          df/dt and peak methods of Generate map without New zero: their
    %          times are read off the averaged window's own time axis. The
    %          cross-correlation and mid-point methods, and the Traces tab's
    %          map, subtract their earliest time (0 = the earliest pixel);
    %          New zero subtracts a typed value. Any other map (APD, beat by
    %          beat, ...) has no record, and a map without one is labelled
    %          plainly "activation (ms)".
    %          Beside the record, the
    %          map's maximum as made (processed_data.activation_max, ms),
    %          moved with New zero, so the map's own upper end is kept in
    %          its saved data and not only in a display limit. A record
    %          only: nothing is cut at it.
    % Record:  struct('method', 'df/dt' | 'peak' | 'cross-correlation' |
    %          'mid-point' | 'traces', 'zero', 'start of averaged window' |
    %          'earliest activation', 'new_zero_ms', the sum of the values
    %          New zero subtracted since (0 = none))

    methods (Static)

        function r = make(method)
            %% The record of a map just made by method (Generate map's method name, or 'traces')
            m = lower(strtrim(char(method)));
            zero = 'earliest activation';
            if any(strcmp(m, {'df/dt', 'peak'})), zero = 'start of averaged window'; end
            r = struct('method', m, 'zero', zero, 'new_zero_ms', 0);
        end

        function mark(app, method)
            %% A new activation map: its record, and its maximum (activation_max, ms)
            app.processed_data.activation_zero = rabbit_activation_zero.make(method);
            % the largest activation time of the map just made (NaN when
            % it has none); Generate map and the Traces tab's map call this
            % right after they set the map
            mx = NaN;
            try
                mx = double(max(app.processed_data.activation_map(:), [], 'omitnan'));
                if isempty(mx), mx = NaN; end
            catch
            end
            app.processed_data.activation_max = mx;
        end

        function forget(app)
            %% A map that is not an activation map, or whose zero is not known: no record
            if isfield(app.processed_data, 'activation_zero')
                app.processed_data = rmfield(app.processed_data, 'activation_zero');
            end
            if isfield(app.processed_data, 'activation_max')
                app.processed_data = rmfield(app.processed_data, 'activation_max');
            end
        end

        function new_zero(app, ms)
            %% New zero subtracted ms from the map
            r = rabbit_activation_zero.of(app);
            if isempty(r), return; end
            ms = double(ms);
            if ~(isscalar(ms) && isfinite(ms)), ms = NaN; end   % a value that was not a number: the zero is unknown
            r.new_zero_ms = r.new_zero_ms + ms;
            app.processed_data.activation_zero = r;
            % the maximum moves with the map (NaN when the value was not a number)
            if isfield(app.processed_data, 'activation_max')
                app.processed_data.activation_max = app.processed_data.activation_max - ms;
            end
        end

        function mx = max_of(app)
            %% The activation map's maximum as made (ms, after any New zero); NaN without one
            mx = NaN;
            try
                if isfield(app.processed_data, 'activation_max')
                    v = double(app.processed_data.activation_max);
                    if isscalar(v), mx = v; end
                end
            catch
            end
        end

        function r = of(app)
            %% The record of the app's activation map, [] without one
            r = [];
            try
                if isfield(app.processed_data, 'activation_zero')
                    r = rabbit_activation_zero.check(app.processed_data.activation_zero);
                end
            catch
                r = [];
            end
        end

        function r = check(r)
            %% A record as read back (from a workspace or JSON), [] when it is not one
            if ~isstruct(r) || ~isscalar(r) || ~all(isfield(r, {'method', 'zero', 'new_zero_ms'}))
                r = [];
                return;
            end
            r = struct('method', char(r.method), 'zero', char(r.zero), 'new_zero_ms', double(r.new_zero_ms));
            if isempty(r.new_zero_ms), r.new_zero_ms = NaN; end   % JSON null: unknown
        end

        function tf = from_window_start(r)
            %% True only when the map's times are ms from the start of the averaged window
            r = rabbit_activation_zero.check(r);
            tf = ~isempty(r) && strcmp(r.zero, 'start of averaged window') && isequal(r.new_zero_ms, 0);
        end

        function t = label(r)
            %% The colour-bar label of an activation map with record r ([] = none)
            if rabbit_activation_zero.from_window_start(r)
                t = 'activation (ms from start of averaged window)';
            else
                t = 'activation (ms)';
            end
        end
    end
end
