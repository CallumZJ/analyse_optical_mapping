classdef rabbit_cv_map
    %% Conduction velocity maps with a pixel size per view
    % Collin Snitchler
    % 24.11.2026
    % Purpose: the Conduction Velocity tab's two methods, moved out of
    %          generate_CV_map so that each pixel is measured with the size
    %          of its own view (S) and a fit never mixes two views (V). With
    %          one size everywhere and V all ones they give the
    %          single-size result. The tab's Bayly defaults (chosen for the
    %          rabbit data, not taken from a reference):
    %          the activation times smoothed by a 3 x 3 median (median3) and
    %          a time window of two frame intervals (controls); both can be
    %          changed on the tab.
    % Inputs:  act  activation map (ms), NaN where there is none
    %          S    um per pixel, per pixel of the map (rabbit_calibration_scale.pixel_map)
    %          V    view of each pixel (1-4; 0 = no view: left out)
    % Outputs: cv   HxWx3: row component, column component, speed, in mm/ms (m/s)
    %          progress (optional): the progress dialog, its Value set as the map is made
    % Sources: Bayly P.V. et al. (1998) Estimation of conduction velocity
    %          vector fields from epicardial mapping data, IEEE Trans Biomed
    %          Eng 45(5):563-571 (the method as generate_CV_map has it).

    methods (Static)

        function cv = bayly(act, S, V, distance_max_mm, time_max_ms, remove_outliers, progress)
            %% Bayly: a quadratic surface fitted to the points around each point, within its own view
            % distance_max_mm becomes a window in each view's own pixels.
            % remove_outliers: the Remove local outliers setting (default
            % off); only then are speeds above the map's mean + 3 SD cut.
            if nargin < 6 || isempty(remove_outliers), remove_outliers = false; end
            if nargin < 7, progress = []; end
            [H, W] = size(act);
            cv = nan(H, W, 3);
            [row, col] = find(~isnan(act) & V > 0);
            idx = sub2ind([H W], row, col);
            vk = V(idx);
            t = act(idx);
            for k = 1:numel(row)
                if ~isempty(progress) && mod(k, 200) == 0, progress.Value = k / numel(row); end
                dxy = 1000 * distance_max_mm / S(idx(k));
                wavefront = find(vk == vk(k) & abs(row - row(k)) < dxy & abs(col - col(k)) < dxy);
                times = t(wavefront);
                keep = abs(times - t(k)) < time_max_ms;
                wavefront = wavefront(keep);
                times = times(keep);
                if numel(times) >= 6
                    % Coordinates centred on the point: the same
                    % surface, but the normal equations stay well
                    % conditioned far from the map's corner, and the
                    % gradient at the point is the linear terms
                    r = row(wavefront) - row(k); c = col(wavefront) - col(k);
                    % A quadratic surface needs at least 3 distinct rows and
                    % 3 distinct columns, and a system that is not close to
                    % singular; otherwise no value (a singular fit would
                    % still give a speed, with MATLAB's "Matrix is singular"
                    % warning)
                    if numel(unique(r)) < 3 || numel(unique(c)) < 3, continue; end
                    A = [r.^2, c.^2, r.*c, r, c, ones(size(r))];
                    if ~(rcond(A' * A) > rabbit_cv_map.BAYLY_MIN_RCOND), continue; end
                    p = A \ times;
                    Tx = p(4);
                    Ty = p(5);
                    cv(row(k), col(k), 1) = Tx / (Tx^2 + Ty^2);   % pixels/ms
                    cv(row(k), col(k), 2) = Ty / (Tx^2 + Ty^2);
                end
            end
            cv(:, :, 3) = sqrt(cv(:, :, 1).^2 + cv(:, :, 2).^2);
            cv = cv .* (S / 1000);   % each pixel with its view's size: mm/ms
            % Outliers above the map's mean + 3 SD: cut only with Remove
            % local outliers on, so that the setting shows every cut.
            if remove_outliers
                sp = cv(:, :, 3);
                out = sp > mean(sp, 'all', 'omitnan') + 3 * std(sp, [], 'all', 'omitnan');
                cv(repmat(out, 1, 1, 3)) = NaN;
            end
        end

        function r = BAYLY_MIN_RCOND()
            %% The reciprocal condition of A'A below which a Bayly fit gives no value
            r = 1e-8;
        end

        function cv = nearest(act, S, V, fps, progress)
            %% Nearest neighbour: the 3 x 3 pixels around each point, all in its own view
            if nargin < 5, progress = []; end
            [H, W] = size(act);
            cv = nan(H, W, 3);
            wx = [-1, 0, 1; -1, 0, 1; -1, 0, 1];
            wy = [-1, -1, -1; 0, 0, 0; 1, 1, 1];
            [row, col] = find(~isnan(act) & V > 0);
            edge = row == 1 | row == H | col == 1 | col == W;
            row(edge) = []; col(edge) = [];
            for k = 1:numel(row)
                if ~isempty(progress) && mod(k, 200) == 0, progress.Value = k / numel(row); end
                r = row(k) - 1:row(k) + 1;
                c = col(k) - 1:col(k) + 1;
                a = act(r, c);
                if any(isnan(a(:))) || any(V(r, c) ~= V(row(k), col(k)), 'all'), continue; end
                mx = sum(a .* wx, 'all') / sum(abs(wx), 'all');   % d t / d column (ms per pixel)
                my = sum(a .* wy, 'all') / sum(abs(wy), 'all');   % d t / d row
                % The velocity is the gradient over its squared length,
                % v = g / |g|^2, as the Bayly fit gives it. Inverting each
                % component on its own (1/mx, 1/my) would overstate the
                % speed of any wave not along a pixel axis. No gradient
                % (|g|^2 below eps): no value. Layer 1 is the row and
                % layer 2 the column component, as the Bayly fit and the
                % arrows have them.
                g2 = mx ^ 2 + my ^ 2;
                if ~(g2 > eps), continue; end
                cv(row(k), col(k), 1) = my / g2;   % pixels/ms, along the rows
                cv(row(k), col(k), 2) = mx / g2;   % along the columns
            end
            cv(:, :, 3) = sqrt(cv(:, :, 1).^2 + cv(:, :, 2).^2);
            cv = cv .* (S / 1000);
        end

        function dxy = outlier_window(S, V, distance_max_mm)
            %% The outlier exclusion's window (odd, in pixels): one for the map, from the median view size
            % The local mean and SD are a neighbourhood measure; one window
            % for the whole map is kept, from the median pixel size.
            s = median(S(V > 0), 'omitnan');
            if ~isfinite(s), s = median(S(:), 'omitnan'); end
            dxy = 2 * floor(ceil(1000 * distance_max_mm / s) / 2) + 1;
        end

        function [cv, n_removed, n_passes] = remove_local_outliers(cv, dxy, V)
            %% Remove local outliers: blank each pixel whose speed is more than 2 SD from its window's mean
            % Each outlier pixel is blanked in all three layers (not the
            % block of every outlier row x column), and the passes repeat
            % until a pass removes nothing. The window (dxy x dxy pixels,
            % odd; outlier_window) stays within one view (V): pixels of
            % other views count as missing. A window with a missing value
            % has no mean or SD (conv2, stdfilt), so pixels next to missing
            % ones are not tested.
            if nargin < 3 || isempty(V) || ~any(V(:) > 0), V = ones(size(cv, 1), size(cv, 2)); end
            k = ones(dxy) / dxy ^ 2;
            n_removed = 0;
            n_passes = 0;
            while true
                n_passes = n_passes + 1;
                s = cv(:, :, 3);
                out = false(size(s));
                for v = unique(V(V > 0))'
                    sv = s;
                    sv(V ~= v) = NaN;                 % the window sees its own view only
                    local_mean = conv2(sv, k, 'same');
                    local_std = stdfilt(sv, ones(dxy));
                    out = out | (V == v & abs(sv - local_mean) > 2 * local_std);
                end
                if ~any(out(:)), break; end
                n_removed = n_removed + nnz(out);
                for L = 1:size(cv, 3)
                    layer = cv(:, :, L);
                    layer(out) = NaN;
                    cv(:, :, L) = layer;
                end
            end
        end

        function [cv, n_removed, n_passes] = remove_local_outliers_mad(cv, dxy, V)
            %% Remove local outliers, edges too: blank each pixel more than 3 scaled MAD from its window's median
            % A choice on the CV tab, off by default (the 2 SD method is
            % the default). The 2 SD test (remove_local_outliers)
            % needs a window without missing values, so pixels next to the
            % tissue's edge or a view seam are never tested, and that is
            % where the fastest wrong values sit. Here the window's values
            % that are there count (a normalised window: missing values and
            % other views are left out, not filled): a pixel is an outlier
            % when |s - median| > 3 x 1.4826 x MAD of its dxy x dxy window
            % in its own view, with at least 9 values in the window and MAD
            % above 0. Blanked in all three layers; passes repeat until one
            % removes nothing (at most 20).
            if nargin < 3 || isempty(V) || ~any(V(:) > 0), V = ones(size(cv, 1), size(cv, 2)); end
            n_removed = 0;
            n_passes = 0;
            while n_passes < 20
                n_passes = n_passes + 1;
                s = cv(:, :, 3);
                out = false(size(s));
                for v = unique(V(V > 0))'
                    sv = s;
                    sv(V ~= v) = NaN;
                    med = rabbit_cv_map.window_stat(sv, dxy, @(X) median(X, 1, 'omitnan'));
                    dev = abs(sv - med);
                    mad = rabbit_cv_map.window_stat(sv, dxy, @(X) median(abs(X - median(X, 1, 'omitnan')), 1, 'omitnan'));
                    n = rabbit_cv_map.window_stat(sv, dxy, @(X) sum(isfinite(X), 1));
                    out = out | (V == v & isfinite(sv) & n >= 9 & mad > 0 & dev > 3 * 1.4826 * mad);
                end
                if ~any(out(:)), break; end
                n_removed = n_removed + nnz(out);
                for L = 1:size(cv, 3)
                    layer = cv(:, :, L);
                    layer(out) = NaN;
                    cv(:, :, L) = layer;
                end
            end
        end

        function R = window_stat(A, dxy, fun)
            %% fun over each pixel's dxy x dxy window of A, NaN outside the map (colfilt would pad with 0)
            h = floor(dxy / 2);
            P = nan(size(A) + 2 * h);
            P(h + 1:end - h, h + 1:end - h) = A;
            R = colfilt(P, [dxy dxy], 'sliding', fun);
            R = R(h + 1:end - h, h + 1:end - h);
        end

        function [cv, line] = remove_outliers_chosen(app, cv, dxy, V)
            %% Remove local outliers with the method chosen on the CV tab, and its History line
            % 'mean +- 2 SD' (default) or 'median +- 3 MAD, edges too'
            if strcmp(rabbit_cv_map.outlier_method(app), 'mad')
                [cv, n_out, n_pass] = rabbit_cv_map.remove_local_outliers_mad(cv, dxy, V);
                line = sprintf(['Remove local outliers (median %s 3 MAD, edges too): %d pixels blanked (more than 3 ' ...
                    'scaled MAD from the median of a %d x %d pixel window in their own view; %d passes).'], ...
                    char(177), n_out, dxy, dxy, n_pass);
            else
                [cv, n_out, n_pass] = rabbit_cv_map.remove_local_outliers(cv, dxy, V);
                line = sprintf(['Remove local outliers: %d pixels blanked (more than 2 SD from the mean of a %d x %d ' ...
                    'pixel window in their own view; %d passes).'], n_out, dxy, dxy, n_pass);
            end
        end

        function m = outlier_method(app)
            %% 'sd' (default) or 'mad', from the CV tab's choice (controls)
            m = 'sd';
            try
                dd = findall(app.GridLayout22, 'Tag', 'CvOutlierMethodDropDown');
                if ~isempty(dd) && strcmp(dd(1).Value, 'mad'), m = 'mad'; end
            catch
            end
        end

        function [cut, source] = activation_cut(app)
            %% The latest activation time the CV map takes (ms): the activation map's own upper limit
            % The display's colour limit (CLim) is the CV map's own range
            % while the CV map is shown, and the Upper Y limit is a display
            % setting too (Undo filtering can set it from the CV map's
            % maximum), so a cut at either would make the CV result depend
            % on the screen. By default nothing is cut; the display limit
            % cuts only when
            % "Leave out activation times above the display limit (<x> ms)"
            % is ticked on the CV tab (controls). source says which, for the
            % CV settings, History and the projection's record.
            cut = Inf;
            source = 'none: every activation time of the map is used';
            try
                box = findall(app.GridLayout22, 'Tag', 'CvCutAtLimitCheckBox');
                v = double(app.upperylimit.Value);
                if ~isempty(box) && logical(box(1).Value) && isscalar(v) && isfinite(v) && v > 0
                    cut = v;
                    source = 'the activation map''s Upper Y limit (Leave out ... ticked)';
                end
            catch
            end
        end

        function t = cut_history_text(app, cut, source)
            %% The CV map's History words on its activation cut, naming the limit as it is
            % cut, source: activation_cut. With a cut: "Activation times
            % above 41.5 ms left out (...)."; without one, the Upper Y limit
            % is named when one is set but not used (Leave out ...
            % unticked, the default), and "no upper limit set" only when
            % there is none.
            if isfinite(cut)
                t = sprintf('Activation times above %s ms left out (%s).', num2str(cut, 5), source);
                return;
            end
            t = 'No activation times left out at the top (no upper limit set).';
            try
                v = double(app.upperylimit.Value);
                if isscalar(v) && isfinite(v) && v > 0
                    t = sprintf(['No activation times left out at the top: the Upper Y limit (%s ms) is a display ' ...
                        'limit and is not used ("Leave out activation times above the display limit" unticked).'], ...
                        num2str(v, 5));
                end
            catch
            end
        end

        % ---- Defaults of the Bayly method (chosen for the rabbit data) ----

        function out = median3(act, V)
            %% 3 x 3 median of the activation times, NaN ignored, within the tissue and one view
            % Each pixel with a time takes the median of the times around it
            % (itself included) that are in its own view; pixels without a
            % time (outside the tissue) stay without one and give nothing to
            % their neighbours, and no value crosses a view seam (V).
            [H, W] = size(act);
            P = nan(H + 2, W + 2);
            P(2:end - 1, 2:end - 1) = act;
            PV = zeros(H + 2, W + 2);
            PV(2:end - 1, 2:end - 1) = V;
            stack = nan(H, W, 9);
            n = 0;
            for dr = -1:1
                for dc = -1:1
                    n = n + 1;
                    a = P(2 + dr:H + 1 + dr, 2 + dc:W + 1 + dc);
                    a(PV(2 + dr:H + 1 + dr, 2 + dc:W + 1 + dc) ~= V) = NaN;   % another view: left out
                    stack(:, :, n) = a;
                end
            end
            out = median(stack, 3, 'omitnan');
            out(isnan(act) | V <= 0) = NaN;
        end

        function [s, names, n] = view_spreads(act, V)
            %% The basis of the near-simultaneous check: each view's activation IQR (25-75 %, ms) over its own pixels
            % The one place the basis is defined (the CV tab's warning, and
            % later the rhythm marker's mismatch caution). The IQR, not the
            % 5-95 % spread: scattered wrong-peak pixels and atrial patches
            % at a view's edge do not move it. V as for bayly:
            % with views (values 1-4) the IQR of each view, View1 to View4
            % (NaN where a view has no values); without (all ones) one IQR
            % over the whole map, its name ''.
            if max(V(:)) > 1
                names = {'View1', 'View2', 'View3', 'View4'};
            else
                names = {''};
            end
            s = nan(1, numel(names));
            n = zeros(1, numel(names));   % each view's pixels with a time
            for k = 1:numel(names)
                v = act(V == k & isfinite(act));
                n(k) = numel(v);
                if isempty(v), continue; end
                q = prctile(double(v), [25 75]);
                s(k) = q(2) - q(1);
            end
        end

        function r = simultaneous_check(act, V, S)
            %% The near-simultaneous check of a map the CV step used: each view's IQR, its limit and the warning ('' for none)
            % The limit of each view is L / 3 ms, L = sqrt(n_px)
            % x pixel_mm the view's size (n_px its pixels with a time, the
            % pixel its median size in S, um per pixel), 3 mm/ms = the
            % middle half crossing about L / 2 at 1.5 m/s
            % (simultaneous_limits); chosen for the rabbit data, not taken
            % from a reference. Without S: the fixed SIMULTANEOUS_IQR_MS
            % (10 ms) of every view.
            [s, names, n] = rabbit_cv_map.view_spreads(act, V);
            lim = repmat(rabbit_reconstruction_tab.SIMULTANEOUS_IQR_MS, 1, numel(names));
            basis_lim = 'a fixed 10 ms';
            if nargin >= 3 && ~isempty(S) && isequal(size(S), size(act))
                lim = rabbit_cv_map.simultaneous_limits(n, S, V);
                % The basis in physics words
                basis_lim = ['the time the middle half of each view takes at 1.5 m/s (view size / 3; view size L = ' ...
                    'sqrt(pixels with a time) x pixel size)'];
            end
            r = struct('views', {names}, 'iqr_ms', s, ...
                'warning', rabbit_reconstruction_tab.simultaneous_warning(names, s, 'plain', lim), ...
                'warn_below_ms', lim, 'n_px', n, ...
                'basis', ['IQR (25-75 %) of the activation times of each view of the map the CV step used, below ' basis_lim]);
        end

        function lim = simultaneous_limits(n, S, V)
            %% Each view's near-simultaneous limit (ms): sqrt(n_px) x pixel_mm / 3
            % n: the views' pixels with a time (view_spreads); S: um per
            % pixel; V: the view of each pixel (all ones: one view). NaN
            % for a view without pixels.
            lim = nan(1, numel(n));
            for k = 1:numel(n)
                if max(V(:)) > 1, in = V == k; else, in = V > 0; end
                px = median(S(in & isfinite(S)), 'omitnan') / 1000;
                if n(k) > 0 && isfinite(px), lim(k) = sqrt(n(k)) * px / rabbit_reconstruction_tab.SIMULTANEOUS_SPEED_MM_PER_MS; end
            end
        end

        function h = map_hash(act)
            %% SHA-256 of a map's values and size (hex), to tell later whether a CV map was made from it
            md = java.security.MessageDigest.getInstance('SHA-256');
            md.update(typecast([double(size(act)), reshape(double(act), 1, [])], 'uint8'));
            h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'))', 1, []));
        end

        function why = stale(app)
            %% '' when the CV map was made from the activation map shown now (or that is not known); else why not
            % Generate map, a filter, New zero or Undo filtering after the
            % CV map change the activation map the CV map was made from;
            % such a CV map is not projected. Older CV settings hold no
            % hash: not known, so nothing is said. Also when the pixel sizes
            % have changed since (Input Scale, Measure length, Scale from
            % calibration... or binning); settings without sizes: not known
            why = '';
            try
                s = app.processed_data.CV_settings;
                if ~isstruct(s), return; end
                if isfield(s, 'activation_sha256') && ~isempty(s.activation_sha256) && ...
                        ~strcmp(s.activation_sha256, rabbit_cv_map.map_hash(app.processed_data.activation_map))
                    why = 'The CV map was made from an earlier activation map; make the CV map again.';
                    return;
                end
                % Also when the CV tab's method has changed since; settings
                % without a method: not known
                now_m = '';
                try
                    now_m = char(app.CV_method.Value);
                catch
                    % a test double without the CV tab: not known
                end
                if isfield(s, 'method') && ~isempty(s.method) && ~isempty(now_m) && ~strcmp(char(s.method), now_m)
                    why = sprintf(['The CV map was made with another method (%s; the CV tab now says %s); make ' ...
                        'the CV map again.'], char(s.method), now_m);
                    return;
                end
                if isfield(s, 'pixel_um_views') && ~isempty(s.pixel_um_views)
                    was = double(s.pixel_um_views(:)');
                    now_v = rabbit_cv_map.pixel_sizes(app);
                    if numel(now_v) ~= numel(was) || any(abs(now_v - was) > 1e-9 * max(abs(was)))
                        why = 'The CV map was made with other pixel sizes; make the CV map again.';
                    end
                end
            catch
            end
        end

        function [v, src] = pixel_sizes(app)
            %% The pixel sizes a CV map is made with (um per map pixel) and where each came from
            % View1 to View4 for the rabbit panoramic
            % views, else one value for the whole map (rabbit_calibration_scale.views)
            [v, src] = rabbit_calibration_scale.views(app);
            if ~strcmp(rabbit_calibration_scale.layout(app), 'views')
                v = v(1);
                src = src(1);
            end
            v = double(v(:)');
            src = cellstr(src(:)');
        end

        function s = with_pixel_sizes(app, s)
            %% The CV settings with the pixel sizes the map was made with (pixel_um_views, pixel_sources)
            [s.pixel_um_views, s.pixel_sources] = rabbit_cv_map.pixel_sizes(app);
        end

        function s = with_method(app, s)
            %% The CV settings with the method and the outlier test the map was made with (method, outlier_test)
            % Kept at CV map time, so the records say how this CV map was
            % made, not what the CV tab says at projection time (as for the
            % pixel sizes)
            s.method = char(app.CV_method.Value);
            s.outlier_test = rabbit_cv_map.outlier_test(app);
        end

        function t = outlier_test(app)
            %% The outlier removal set on the CV tab in words: 'none', 'mean ± 2 SD' or 'median ± 3 MAD, edges too'
            t = 'none';
            try
                if app.CVoutlierexclusion.Value ~= 1, return; end
            catch
                return;
            end
            if strcmp(rabbit_cv_map.outlier_method(app), 'mad')
                t = sprintf('median %s 3 MAD, edges too', char(177));
            else
                t = sprintf('mean %s 2 SD', char(177));
            end
        end

        function S = pixel_um_map(app)
            %% Each pixel's size (um) as the CV map was made with it, [] when it cannot be given per pixel
            % The sizes kept in CV_settings (pixel_um_views), put on the
            % map's pixels by their view; an older CV map keeps none: the
            % sizes now (stale() refuses a map whose kept sizes differ from
            % them).
            S = [];
            try
                [S, V, why] = rabbit_calibration_scale.pixel_map(app);
                if ~isempty(why), S = []; return; end
                s = [];
                if isfield(app.processed_data, 'CV_settings'), s = app.processed_data.CV_settings; end
                if ~isstruct(s) || ~isfield(s, 'pixel_um_views') || isempty(s.pixel_um_views), return; end
                v = double(s.pixel_um_views(:)');
                if isscalar(v)
                    S = v * ones(size(S));                 % one size for the whole map
                elseif numel(v) == 4 && max(V(:)) > 1
                    in = V > 0;
                    S(in) = v(V(in));                      % each pixel with its view's kept size
                elseif numel(v) == 4
                    S = v(1) * ones(size(S));              % four equal sizes, the map without views
                end
            catch
                S = [];
            end
        end

        function [u, v] = arrows(cv, rows, cols, spacing, lim)
            %% The CV tab's arrows: column (u) and row (v) parts, length from the speed
            % The same formula as the 3-D arrows: the
            % unit direction (CV_map layers 2 and 1) times spacing x (0.4 +
            % 0.6 (s - lo) / (hi - lo)), clamped to 0.4-1 x spacing, s the
            % speed (layer 3), [lo hi] = lim, the colour range shown; NaN
            % (no arrow) where s is outside it or missing.
            idx = sub2ind([size(cv, 1) size(cv, 2)], rows, cols);
            c1 = cv(:, :, 1); c2 = cv(:, :, 2); sp = cv(:, :, 3);
            vr = c1(idx); vc = c2(idx); s = sp(idx);
            u = nan(size(idx)); v = nan(size(idx));
            q = double(lim(:)');
            if ~(numel(q) == 2 && q(2) > q(1)), return; end
            len = spacing * min(1, max(0.4, 0.4 + 0.6 * (s - q(1)) / (q(2) - q(1))));
            n = hypot(vr, vc);
            ok = isfinite(s) & s > 0 & n > 0 & s >= lim(1) & s <= lim(2);
            u(ok) = len(ok) .* vc(ok) ./ n(ok);
            v(ok) = len(ok) .* vr(ok) ./ n(ok);
        end

        function lim = display_range(cv)
            %% The CV tab's automatic colour range: [0, the 99th percentile of the speeds] (m/s)
            % [0, max] would let a few outliers (471 m/s on a map whose
            % median is 0.7 m/s) take the whole colour bar; the 3-D
            % panel's automatic range is its 1st to 99th percentile. The
            % speeds are layer 3, values above 0. Without any: [0 1].
            lim = [0 1];
            if ndims(cv) < 3 || size(cv, 3) < 3, return; end
            s = double(cv(:, :, 3));
            s = s(isfinite(s) & s > 0);
            if isempty(s), return; end
            hi = prctile(s, 99);
            if ~(hi > 0), hi = max(s); end
            lim = [0 hi];
        end

        function ms = MIN_TIME_WINDOW_MS()
            %% The shortest default time window (ms), chosen for the rabbit data, not taken from a reference
            % Two frame intervals alone shrink the window on a faster rig
            % (2 ms at 1 kHz), and a 0.5 m/s wave then reads several m/s.
            % At 204 fps the default is 10 ms instead of 9.80.
            ms = 10;
        end

        function ms = default_window(fps)
            %% The default time window: max(two frame intervals, 10 ms); [] without a frame rate
            ms = rabbit_cv_map.two_frames(fps);
            if ~isempty(ms), ms = max(ms, rabbit_cv_map.MIN_TIME_WINDOW_MS); end
        end

        function tf = is_default_source(src)
            %% A time window's source that is the default ('two frame intervals' in older settings)
            tf = any(strcmp(char(src), {'two frame intervals', 'two frame intervals, at least 10 ms'}));
        end

        function ms = two_frames(fps)
            %% The default time window: two frame intervals (ms); [] without a frame rate
            ms = [];
            if isnumeric(fps) && isscalar(fps) && isfinite(fps) && fps > 0
                ms = 2000 / double(fps);
            end
        end

        function controls(app)
            %% Smooth activation times (3x3 median) and the time window's default (two frames), on the CV tab
            % Made at runtime (createComponents is unchanged): the checkbox,
            % ticked by default, and the time window, which shows two frame
            % intervals of the loaded recording until a value is typed; a
            % typed value stays.
            % Cells of the CV tab's GridLayout22 used here (row, columns),
            % to be kept free in App Designer: the outlier test drop-down
            % (1, 6), the slowest speed resolved (2, 5-6), Smooth activation
            % times (5, 5-6), Leave out activation times above the display
            % limit (5, 7-9); rabbit_calibration_scale.show uses (3, 4),
            % (3, 5-6) and (4, 3-6). Without GridLayout22 (renamed in App
            % Designer, say) nothing is added and no error is raised.
            if ~isprop(app, 'GridLayout22') || isempty(app.GridLayout22) || ~isvalid(app.GridLayout22), return; end
            g = app.GridLayout22;
            box = findall(g, 'Tag', 'CvSmoothCheckBox');
            if isempty(box)
                box = uicheckbox(g, 'Tag', 'CvSmoothCheckBox', 'Value', true, ...
                    'Text', sprintf('Smooth activation times (3%s3 median)', char(215)), ...
                    'Tooltip', {['Bayly method: the activation times go through a 3 x 3 median first, ' ...
                    'NaN ignored, within the tissue and within each view (never across a view seam). ' ...
                    'Untick it to use the map as it is.']});
                box.Layout.Row = 5;
                box.Layout.Column = [5 6];
                app.timemax.ValueChangedFcn = @(src, ~) rabbit_cv_map.time_typed(app, src);
                setappdata(app.timemax, 'om_cv_time_default', app.timemax.Value);   % the value not set by hand
            end
            % The method dropdown says which method to
            % prefer (CV_method is made in createComponents; its tooltip is
            % set here, as Help says it)
            if isprop(app, 'CV_method') && ~isempty(app.CV_method) && isvalid(app.CV_method)
                app.CV_method.Tooltip = {['Bayly Method (preferred): a surface fitted over the distance max. ' ...
                    'Nearest Neighbour: the 3x3 pixels around each point, unsmoothed; it is noise-sensitive, ' ...
                    'and Bayly is preferred.']};
            end
            % The note on red streaks in a tooltip
            % by the CV map. Neither the colour bar nor the map's axes take
            % a tooltip (MATLAB ColorBar and axes have no Tooltip
            % property), so it goes on CV mean, the CV map's own summary,
            % whose message ends with the same note; set here, as
            % createComponents stays stock
            if isprop(app, 'CVmean') && ~isempty(app.CVmean) && isvalid(app.CVmean)
                note = rabbit_cv_map.ARTEFACT_NOTE();
                app.CVmean.Tooltip = {'Summarise the speeds of the CV map.'; ...
                    ['On the CV map: ' upper(note(1)) note(2:end) '.']};
            end
            % Beside Time max, the slowest speed
            % the window fully resolves (distance max / time max), kept up
            % to date when either is changed
            slow = findall(g, 'Tag', 'CvSlowestSpeedLabel');
            if isempty(slow)
                slow = uilabel(g, 'Tag', 'CvSlowestSpeedLabel', 'WordWrap', 'on', 'Text', '', ...
                    'Tooltip', {['Bayly method: a wave slower than this does not cross the distance max within the ' ...
                    'time max, so its speed is not fully resolved. distance max (mm) / time max (ms) = m/s.']});
                slow.Layout.Row = 2;
                slow.Layout.Column = [5 6];
                if isempty(app.distancemax.ValueChangedFcn)
                    app.distancemax.ValueChangedFcn = @(~, ~) rabbit_cv_map.time_label(app);
                end
            end
            % The activation cut at the display limit only when asked for,
            % off by default
            cut = findall(g, 'Tag', 'CvCutAtLimitCheckBox');
            if isempty(cut)
                cut = uicheckbox(g, 'Tag', 'CvCutAtLimitCheckBox', 'Value', false, 'Text', '', ...
                    'Tooltip', {['Off (the default): the CV map uses every activation time of the map. On: times ' ...
                    'above the Activation Map tab''s Upper Y limit are left out, as typed there, and on the mesh ' ...
                    'the faces whose projected activation is above it get no CV.']});
                cut.Layout.Row = 5;
                cut.Layout.Column = [7 9];
            end
            try
                cut(1).Text = sprintf('Leave out activation times above the display limit (%s ms)', num2str(app.upperylimit.Value, 4));
            catch
                cut(1).Text = 'Leave out activation times above the display limit';
            end
            % What Remove local outliers does, and what the arrows' length
            % means
            try
                % with the test chosen beside it
                app.CVoutlierexclusion.Tooltip = {['Blanks each CV pixel more than 2 SD from the mean of its ' ...
                    'distance-max window, within its own view (mean ' char(177) ' 2 SD, the default), or, with ' ...
                    '"median ' char(177) ' 3 MAD, edges too" chosen beside it, more than 3 scaled MAD from the median of the ' ...
                    'values its window has, so tissue-edge and seam pixels are tested too; repeats until none is ' ...
                    'removed. Off by default.']};
                app.IncludequiversButton.Tooltip = {['Arrows: the CV direction; arrow length 0.4' char(8211) '1 ' ...
                    char(215) ' spacing over the colour range (low to high); none outside it.']};
            catch
                % a test double without these buttons
            end
            % What Distance max is, and what the automatic colour range is
            % taken over
            try
                % The short label, the explanation in the tooltips (a long
                % label is cut off)
                app.DistancemaxmmEditFieldLabel.Text = 'Distance max (mm)';
                dtip = {['Bayly method: the half-width of the square fit window, in mm (in each view''s own ' ...
                    'pixels). A typed value is kept.']};
                app.DistancemaxmmEditFieldLabel.Tooltip = dtip;
                app.distancemax.Tooltip = dtip;
                tip = {['Colour limits of the CV map. Automatic (after CV map): 0 to the 99th percentile of the ' ...
                    'speeds of the 2-D map''s pixels; Visualise''s 3-D panel takes the 1st to 99th ' ...
                    'percentile of its faces. A typed value is kept.']};
                app.lowerylimit_traces.Tooltip = tip;
                app.upperylimit_traces.Tooltip = tip;
            catch
                % a test double without these fields
            end
            % The outlier test, the 2 SD one by default
            om = findall(g, 'Tag', 'CvOutlierMethodDropDown');
            if isempty(om)
                om = uidropdown(g, 'Tag', 'CvOutlierMethodDropDown', ...
                    'Items', {'mean ± 2 SD', 'median ± 3 MAD, edges too'}, 'ItemsData', {'sd', 'mad'}, 'Value', 'sd', ...
                    'Tooltip', {['Remove local outliers: mean ± 2 SD (the default) tests only pixels whose whole ' ...
                    'window has values; median ± 3 MAD, edges too, uses the values a window has, so pixels at the ' ...
                    'tissue edge and the view seams are tested as well.']});
                om.Layout.Row = 1;
                om.Layout.Column = 6;
            end
            if ~rabbit_cv_map.held(app) && isappdata(box, 'om_cv_smooth_held')
                % a new recording after a workspace that kept the old
                % settings: the defaults again
                box.Value = true;
                rmappdata(box, 'om_cv_smooth_held');
            end
            ms = rabbit_cv_map.default_window(rabbit_cv_map.fps_of(app));   % max(2 frames, 10 ms)
            if ~rabbit_cv_map.is_typed(app) && ~isempty(ms)
                app.timemax.Value = ms;
                setappdata(app.timemax, 'om_cv_time_default', ms);
            end
            rabbit_cv_map.time_label(app);
            % The SET LIMITS panel's last two rows (the colour limits and
            % New zero) take their controls' height, the histogram the
            % rest, so New zero is not cut off
            try
                app.GridLayout8_2.RowHeight = {'1x', '1x', '1x', '1x', 'fit', 'fit'};
            catch
                % a test double without the panel
            end
        end

        function t = speed_bar_label(app)
            %% The CV map's colour bar label: 'CV (m/s)', or 'apparent speed (m/s), not CV' when activation is nearly simultaneous
            % The near-simultaneous check of the map
            % shown (processed_data.CV_activation_spread.warning) fired
            t = 'CV (m/s)';
            try
                a = app.processed_data.CV_activation_spread;
                if isstruct(a) && isfield(a, 'warning') && ~isempty(a.warning)
                    t = 'apparent speed (m/s), not CV';
                end
            catch
            end
        end

        function t = ARTEFACT_NOTE()
            %% The 2-D CV map's note on red streaks (a note only; the colour map is not changed)
            t = 'red streaks along a view seam or edge are fitting artefacts, not fast tissue';
        end

        function workspace_loaded(app)
            %% After a workspace is loaded: its CV settings; one saved without them keeps the old ones
            % A workspace holds the settings its CV map was made with
            % (processed_data.CV_settings). An older one holds none: it
            % keeps the settings of its time, no smoothing and 6 ms, so that
            % making its CV map again does not change it silently. They hold
            % for this data only (app.data.cv_settings_held): a recording
            % loaded next gets the defaults.
            rabbit_cv_map.controls(app);
            s = [];
            if isfield(app.processed_data, 'CV_settings'), s = app.processed_data.CV_settings; end
            if isstruct(s)
                rabbit_cv_map.restore(app, s);
                return;
            end
            rabbit_cv_map.set_smooth(app, false);
            box = findall(app.GridLayout22, 'Tag', 'CvSmoothCheckBox');
            if ~isempty(box), setappdata(box(1), 'om_cv_smooth_held', true); end
            app.timemax.Value = 6;
            setappdata(app.timemax, 'om_cv_time_default', 6);
            setappdata(app.timemax, 'om_cv_time_typed', false);
            app.data.cv_settings_held = true;
            rabbit_cv_map.time_label(app);
            try
                app.history_field.Value{length(app.history_field.Value) + 1, 1} = sprintf(['Workspace from before ' ...
                    'the CV defaults changed: CV settings kept as they were (no smoothing, 6 ms). The new ' ...
                    'defaults are 3%s3 smoothing and 2 frames, at least 10 ms.'], char(215));
            catch
                % a test double without a History tab
            end
        end

        function tf = held(app)
            %% The data came from a workspace saved before the CV defaults changed (its settings are kept)
            % A workspace holds no raw image stack (save_workspace leaves it
            % out) and a recording loaded after it does; loading one does
            % not reset app.data after a workspace, so the stack, not the
            % marker alone, says that the workspace's data are still the ones
            % in use.
            tf = false;
            try
                tf = isfield(app.data, 'cv_settings_held') && isequal(app.data.cv_settings_held, true) && ...
                    isempty(app.data.image_stack);
            catch
            end
        end

        function fps = fps_of(app)
            fps = [];
            try
                fps = app.data.fps;
            catch
            end
        end

        function time_typed(app, src)
            %% The time window was typed: it stays as typed from now on
            setappdata(src, 'om_cv_time_typed', true);
            rabbit_cv_map.time_label(app);
        end

        function tf = is_typed(app)
            %% Typed, or set another way since the default was put in (a script, say)
            tf = isappdata(app.timemax, 'om_cv_time_typed') && isequal(getappdata(app.timemax, 'om_cv_time_typed'), true);
            tf = tf || rabbit_cv_map.held(app);   % an old workspace's 6 ms
            if ~tf && isappdata(app.timemax, 'om_cv_time_default')
                tf = abs(app.timemax.Value - getappdata(app.timemax, 'om_cv_time_default')) > 1e-9;
            end
        end

        function set_typed(app, tf)
            %% A workspace's own setting: typed, or the two-frame default
            setappdata(app.timemax, 'om_cv_time_typed', logical(tf));
            if ~tf, setappdata(app.timemax, 'om_cv_time_default', app.timemax.Value); end
            rabbit_cv_map.time_label(app);
        end

        function time_label(app)
            %% "Time max (ms), 2 frames, at least 10 ms" while the default is in use
            try
                ms = rabbit_cv_map.default_window(rabbit_cv_map.fps_of(app));
                if rabbit_cv_map.is_typed(app) || isempty(ms) || abs(app.timemax.Value - ms) > 1e-9
                    app.TimemaxmsEditFieldLabel.Text = 'Time max (ms)';
                    app.timemax.Tooltip = {'Bayly method: the time window. A typed value is kept.'};
                else
                    % The short label; "2 frames, at least 10 ms" is in the
                    % tooltip
                    app.TimemaxmsEditFieldLabel.Text = 'Time max (ms)';
                    % The formula and the value the field shows
                    % (max(2 frames, 10 ms)), with this recording's fps
                    fps = rabbit_cv_map.fps_of(app);
                    app.timemax.Tooltip = {sprintf(['Bayly method: max(2 frames, %g ms) = max(2000 / %.4g fps, %g ms) = ' ...
                        '%.1f ms at %.4g fps. A typed value is kept.'], rabbit_cv_map.MIN_TIME_WINDOW_MS, fps, ...
                        rabbit_cv_map.MIN_TIME_WINDOW_MS, ms, fps)};
                end
            catch
                % a test double without the Conduction Velocity tab
            end
            % The slowest speed fully resolved
            try
                slow = findall(app.GridLayout22, 'Tag', 'CvSlowestSpeedLabel');
                if ~isempty(slow)
                    % "= 0.3 m/s" kept on one line
                    % (non-breaking spaces), so "m/s" never wraps alone; the
                    % label cannot be wider (columns 7-9 are SET LIMITS)
                    txt = rabbit_cv_map.slowest_text(app.distancemax.Value, app.timemax.Value);
                    slow(1).Text = regexprep(txt, ' = (\S+) m/s$', [char(160) '=' char(160) '$1' char(160) 'm/s']);
                end
            catch
                % a test double without the Conduction Velocity tab
            end
        end

        function t = slowest_text(distance_mm, time_ms)
            %% 'slowest speed fully resolved (approx.) distance max / time max = 0.31 m/s' (mm / ms = m/s)
            t = '';
            d = double(distance_mm);
            ms = double(time_ms);
            if ~(isscalar(d) && isscalar(ms) && isfinite(d) && isfinite(ms) && d > 0 && ms > 0), return; end
            t = sprintf('slowest speed fully resolved %s distance max / time max = %s m/s', char(8776), num2str(d / ms, 2));
        end

        function tf = smooth_on(app)
            %% The checkbox (ticked when it is not made yet: the default)
            tf = true;
            box = findall(app.GridLayout22, 'Tag', 'CvSmoothCheckBox');
            if ~isempty(box), tf = logical(box(1).Value); end
        end

        function set_smooth(app, tf)
            box = findall(app.GridLayout22, 'Tag', 'CvSmoothCheckBox');
            if ~isempty(box), box(1).Value = logical(tf); end
        end

        function s = settings(app)
            %% The Bayly settings a CV map is made with, for History, the workspace and the run manifest
            s = struct('smooth_activation', rabbit_cv_map.smooth_on(app), ...
                'smooth_method', '3x3 median, NaN ignored, within the tissue and each view', ...
                'time_max_ms', double(app.timemax.Value), 'time_max_source', 'two frame intervals, at least 10 ms', ...
                'distance_max_mm', double(app.distancemax.Value));
            ms = rabbit_cv_map.default_window(rabbit_cv_map.fps_of(app));
            if rabbit_cv_map.held(app)
                s.time_max_source = 'kept from the workspace';
            elseif rabbit_cv_map.is_typed(app)
                s.time_max_source = 'typed';
            elseif isempty(ms) || abs(app.timemax.Value - ms) > 1e-9
                s.time_max_source = 'as set';
            end
            if ~s.smooth_activation, s.smooth_method = 'none'; end
        end

        function r = record_fields(s)
            %% The CV settings as the CV projection's records name them; [] without settings
            % cv_smoothing_3x3 (true/false), cv_time_max_ms, cv_distance_max_mm
            % from a CV map's settings (processed_data.CV_settings); the
            % nearest-neighbour method has no window: [] for those two.
            % The 3-D CV panel's caption reads them.
            r = [];
            if ~isstruct(s) || ~isfield(s, 'smooth_activation'), return; end
            r = struct('cv_smoothing_3x3', logical(s.smooth_activation), 'cv_time_max_ms', [], 'cv_distance_max_mm', []);
            if isfield(s, 'time_max_ms') && ~isempty(s.time_max_ms), r.cv_time_max_ms = double(s.time_max_ms); end
            if isfield(s, 'distance_max_mm') && ~isempty(s.distance_max_mm), r.cv_distance_max_mm = double(s.distance_max_mm); end
            % The pixel sizes the CV map was made
            % with (um per map pixel, View1 to View4 or one value) and
            % where each came from, when the settings keep them
            if isfield(s, 'pixel_um_views') && ~isempty(s.pixel_um_views)
                r.cv_pixel_um_views = double(s.pixel_um_views(:)');
                if isfield(s, 'pixel_sources'), r.cv_pixel_sources = cellstr(s.pixel_sources); end
            end
            % The method and the outlier test the CV
            % map was made with, when the settings keep them
            if isfield(s, 'method') && ~isempty(s.method), r.cv_method = char(s.method); end
            if isfield(s, 'outlier_test') && ~isempty(s.outlier_test), r.cv_outlier_test = char(s.outlier_test); end
        end

        function t = history_text(s)
            %% 'Smoothing: 3x3 median. Max time: 9.8 ms (2 frames).'
            if s.smooth_activation
                sm = sprintf('3%s3 median', char(215));
            else
                sm = 'none';
            end
            src = '';
            if strcmp(s.time_max_source, 'two frame intervals'), src = ' (2 frames)'; end
            if strcmp(s.time_max_source, 'two frame intervals, at least 10 ms'), src = ' (2 frames, at least 10 ms)'; end
            if strcmp(s.time_max_source, 'typed'), src = ' (typed)'; end
            if strcmp(s.time_max_source, 'kept from the workspace'), src = ' (kept from the workspace)'; end
            t = sprintf('Smoothing: %s. Max time: %s ms%s.', sm, num2str(s.time_max_ms, 3), src);
        end

        function restore(app, s)
            %% A workspace's CV settings, as they were saved with its CV map
            if ~isstruct(s) || ~isfield(s, 'time_max_source') || startsWith(char(s.time_max_source), 'not used'), return; end
            rabbit_cv_map.controls(app);
            if isfield(s, 'smooth_activation'), rabbit_cv_map.set_smooth(app, s.smooth_activation); end
            if isfield(s, 'time_max_ms') && isfield(s, 'time_max_source')
                app.timemax.Value = s.time_max_ms;
                rabbit_cv_map.set_typed(app, ~rabbit_cv_map.is_default_source(s.time_max_source));
            end
        end
    end
end
