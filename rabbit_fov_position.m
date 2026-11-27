classdef rabbit_fov_position
    %% Where one recording's frame sits in another's, measured or typed in
    % Collin Snitchler
    % 19.11.2026
    % Purpose: the optical mapping, reconstruction and calibration
    %          recordings come from one camera that does not move, but the
    %          camera's area of interest (the frame size and position on the
    %          sensor) may change between them. This finds the shift between
    %          two frames, says how far it can be trusted, and asks the user
    %          when it cannot, so the cut, the reconstruction and the
    %          calibration all take the same sensor pixels.
    %          The area of interest is not read from the file: the Andor
    %          Solis headers of the reference rabbit data do not hold it
    %          (IMGRECT and SUBRECT count from the frame itself).
    %
    % How it measures. A single frame is not enough: the match follows the
    % heart, and frames of one recording matched each other at shifts of up
    % to 21 px with scores of 0.91-0.97. So each
    % recording is summarised by the median of up to 30 evenly spaced frames,
    % and only its still pixels count: those whose spread over the frames
    % (interquartile range) is at most three times the frame's median spread,
    % leaving out the darkest 5 %. On the reference rabbit data this gave the
    % optical mapping frame at row 192 of the reconstruction frame from every
    % optical mapping frame tried, and 0 for frames of one recording. The
    % position is measured three times, from all frames and from the odd and
    % the even ones; it is trusted when the three agree to 1 px and the
    % score is at least TRUSTED_SCORE. The halves share the still
    % background, so their agreement shows noise, not a systematic error,
    % and in a recording where nothing moves they are nearly the same
    % picture: a trusted position is offered, never taken without the
    % user's answer. The position is good to about 1 px: on the reference
    % rabbit data the
    % whole frames gave row 194 and a crop of the same pixels the
    % equivalent of row 193. A cube recording and the heart
    % recording do not look alike enough (reference rabbit data: 0.54-0.62
    % at wrong shifts,
    % and the halves disagree), so a calibration position usually has to be
    % typed in.
    % Sources: Padfield 2012 (masked normalised cross-correlation),
    % rabbit_stack_io.measure_fov_offset.

    properties (Constant)
        N_FRAMES = 30          % frames sampled from each recording
        TRUSTED_SCORE = 0.7    % reference rabbit data: 0.80-0.88 at the true position, still pixels only
    end

    methods (Static)

        function st = sample_frames(input, n)
            %% Up to n evenly spaced frames of a recording, rows as stored (single)
            if nargin < 2, n = rabbit_fov_position.N_FRAMES; end
            input = char(input);
            if isfolder(input)
                names = rabbit_stack_io.frame_names(input);
                pick = rabbit_fov_position.pick(numel(names), n);
                st = [];
                for k = 1:numel(pick)
                    fr = single(rabbit_stack_io.read_folder_frame(fullfile(input, names{pick(k)}), []));
                    if isempty(st), st = zeros([size(fr) numel(pick)], 'single'); end
                    st(:, :, k) = fr;
                end
                return;
            end
            [~, ~, ext] = fileparts(input);
            if any(strcmpi(ext, {'.fits', '.fit'}))
                sz = fitsinfo(input).PrimaryData.Size;
                if numel(sz) == 2
                    st = single(fitsread(input));
                    return;
                end
                pick = rabbit_fov_position.pick(sz(3), n);
                st = zeros(sz(1), sz(2), numel(pick), 'single');
                for k = 1:numel(pick)
                    st(:, :, k) = single(fitsread(input, 'primary', 'PixelRegion', ...
                        {[1 sz(1)], [1 sz(2)], [pick(k) pick(k)]}));
                end
            else
                info = imfinfo(input);
                pick = rabbit_fov_position.pick(numel(info), n);
                st = zeros(info(1).Height, info(1).Width, numel(pick), 'single');
                for k = 1:numel(pick)
                    st(:, :, k) = single(imread(input, pick(k)));
                end
            end
        end

        function k = pick(total, n)
            %% n evenly spaced frame numbers out of total (all when fewer)
            k = unique(round(linspace(1, total, min(n, total))));
        end

        function st = sample_stack(stack, n)
            %% Up to n evenly spaced frames of a stack already in memory
            if nargin < 2, n = rabbit_fov_position.N_FRAMES; end
            k = rabbit_fov_position.pick(size(stack, 3), n);
            st = single(stack(:, :, k));
        end

        function [med, still] = still(st)
            %% Median of the frames, and the pixels that stay still through them
            med = median(st, 3);
            if size(st, 3) < 3
                still = isfinite(med);   % too few frames to tell
            else
                spread = iqr(st, 3);
                still = spread <= max(2, 3 * median(spread(:), 'omitnan'));
            end
            still = still & isfinite(med) & med > prctile(med(:), 5);
        end

        function est = measure(a_st, b_st)
            %% Position of frame stack a in frame stack b, with a trust verdict
            % est: the fields of rabbit_stack_io.measure_fov_offset, plus
            % halves ([off cols_off] from the odd and the even frames),
            % consistent, trusted and why (plain words when not trusted).
            [ma, sa] = rabbit_fov_position.still(a_st);
            [mb, sb] = rabbit_fov_position.still(b_st);
            est = rabbit_stack_io.measure_fov_offset(ma, mb, sa, sb);
            est.halves = nan(2, 2);
            est.consistent = false;
            est.trusted = false;
            est.snapped = false;
            if ~isfinite(est.ncc)
                est.why = 'the two recordings share too few still pixels to compare';
                return;
            end
            if size(a_st, 3) >= 4 && size(b_st, 3) >= 4
                for h = 1:2
                    [ha, hsa] = rabbit_fov_position.still(a_st(:, :, h:2:end));
                    [hb, hsb] = rabbit_fov_position.still(b_st(:, :, h:2:end));
                    e = rabbit_stack_io.measure_fov_offset(ha, hb, hsa, hsb);
                    if isfinite(e.ncc)
                        est.halves(h, :) = [e.off e.cols_off];
                    end   % else stays NaN: a half that cannot be measured agrees with nothing
                end
                est.consistent = all(isfinite(est.halves(:))) && ...
                    all(abs(est.halves - [est.off est.cols_off]) <= 1, 'all');
            end
            est.trusted = est.consistent && est.ncc >= rabbit_fov_position.TRUSTED_SCORE && ~est.edge;
            % The position is good to about 1 px (reference rabbit data: the halves differ
            % by up to 1 px). Where frame b is large enough to hold frame a
            % in a direction but a sticks out by just 1 px, a is put inside:
            % areas of interest usually share an edge, and a box at that
            % edge would otherwise be refused for a pixel
            est.snapped = false;
            ha = size(a_st, 1); wa = size(a_st, 2); hb = size(b_st, 1); wb = size(b_st, 2);
            if est.trusted && hb >= ha && (est.off == -1 || est.off == hb - ha + 1)
                est.off = min(max(est.off, 0), hb - ha);
                est.snapped = true;
            end
            if est.trusted && wb >= wa && (est.cols_off == -1 || est.cols_off == wb - wa + 1)
                est.cols_off = min(max(est.cols_off, 0), wb - wa);
                est.snapped = true;
            end
            if est.trusted
                est.why = '';
            elseif ~est.consistent && all(isfinite(est.halves(:)))
                est.why = sprintf(['the odd and the even frames give different positions (rows %d and %d, ' ...
                    'columns %d and %d)'], est.halves(1, 1) + 1, est.halves(2, 1) + 1, ...
                    est.halves(1, 2) + 1, est.halves(2, 2) + 1);
            elseif ~est.consistent && size(a_st, 3) >= 4 && size(b_st, 3) >= 4
                est.why = 'half of the frames could not be compared';
            elseif ~est.consistent
                est.why = 'there are too few frames to check the position';
            elseif est.edge
                est.why = 'the search stopped at the edge of its range';
            else
                est.why = sprintf('the match is weak (score %.2f; %.2f or more is trusted)', est.ncc, ...
                    rabbit_fov_position.TRUSTED_SCORE);
            end
        end

        function res = ask_om_position(fig, which, om_hw, other_hw, est, alt)
            %% How the optical mapping recording lines up with another one, as the user accepts it
            % fig: the dialog's figure; which: 'reconstruction' or
            % 'calibration'; est: from measure (OM frames as a, the other
            % recording as b; [] when it could not be measured).
            % res.ok: false when the user cancelled; res.mapping: [] when
            % the two line up as they are, else an offset mapping with
            % position_source 'measured' or 'typed' and match_score.
            % The questions are in plain words; the numbers go only into
            % the record, and into the fields when the shift is typed in.
            % alt (optional): struct label, mapping, note: another
            % loaded recording of the same frame size whose alignment can be
            % reused (a calibration and a reconstruction recording made with
            % the same area of interest); offered first when the app is not
            % sure of its own measurement
            if nargin < 6, alt = []; end
            res = struct('ok', false, 'mapping', []);
            same_size = isequal(om_hw, other_hw);
            trusted = isstruct(est) && est.trusted;
            if trusted && same_size && est.off == 0 && est.cols_off == 0
                res.ok = true;   % they line up, measured
                return;
            end
            title = sprintf('Line up the %s recording', which);
            while true
                if trusted
                    msg = sprintf(['The %s recording and the optical mapping recording show different parts of ' ...
                        'the camera image. The app found where they overlap, and is sure of it.'], which);
                    over = rabbit_stack_io.overlap_text(om_hw(1), om_hw(2), other_hw(1), other_hw(2), est.off, est.cols_off);
                    if ~startsWith(over, 'the whole')
                        msg = [msg ' Only part of the optical mapping image is in the ' which ' recording, so the ' ...
                            'regions must stay inside that part (the ROI editor outlines it).'];
                    end
                    msg = [msg ' Use it?'];
                    options = {'Use it', 'Enter the shift...', 'Cancel'};
                    icon = 'question';
                elseif same_size
                    msg = sprintf(['The %s recording is the same size as the optical mapping recording, but the two ' ...
                        'look too different for the app to check that they line up. They are taken to line up ' ...
                        'unless you enter a shift.'], which);
                    options = {'They line up', 'Enter the shift...', 'Cancel'};
                    icon = 'warning';
                else
                    msg = sprintf(['The %s recording is a different size from the optical mapping recording, and ' ...
                        'the two look too different for the app to line them up itself. Enter the shift between ' ...
                        'them.'], which);
                    options = {'Enter the shift...', 'Cancel'};
                    icon = 'warning';
                end
                if isstruct(alt) && ~trusted
                    msg = sprintf(['The %s recording looks too different from the optical mapping recording for ' ...
                        'the app to line them up itself. %s'], which, alt.note);
                    options = [{alt.label}, options(~strcmp(options, 'They line up'))];
                elseif isstruct(alt)
                    % A sure measurement is never replaced by another
                    % recording's position; when the
                    % two disagree, say so
                    ao = [0 0];
                    if isstruct(alt.mapping)
                        ao = [alt.mapping.om_window_in_rec.off, rabbit_cut_tiffs.cols_off_of(alt.mapping)];
                    end
                    if any(abs(ao - [est.off est.cols_off]) > 1)
                        msg = [msg sprintf([' Note: %s, of the same size, was lined up %d px further down and %d px ' ...
                            'further right; if both were recorded with the same area of interest, that one is wrong: ' ...
                            'check it in the ROI editor''s colour view.'], lower(strrep(alt.label, 'Same area as the ', '')), ...
                            ao(1) - est.off, ao(2) - est.cols_off)];
                    end
                end
                answer = uiconfirm(fig, msg, title, 'Options', options, ...
                    'DefaultOption', 1, 'CancelOption', numel(options), 'Icon', icon);
                if isstruct(alt) && strcmp(answer, alt.label)
                    res.mapping = alt.mapping;
                    res.ok = true;
                    return;
                end
                switch answer
                    case 'Use it'
                        res.mapping = rabbit_fov_position.mapping(est.off, est.cols_off, om_hw, 'measured', est.ncc, ...
                            sprintf(['measured when the %s stack was loaded: the still pixels of up to %d frames ' ...
                            'of each recording match at row offset %d, column offset %d (score %.3f; the odd and ' ...
                            'the even frames agree; offsets in the row order stored in the files)'], which, ...
                            rabbit_fov_position.N_FRAMES, est.off, est.cols_off, est.ncc));
                        res.ok = true;
                        return;
                    case 'They line up'
                        res.ok = true;
                        return;
                    case 'Enter the shift...'
                        prefill = {'', ''};
                        if trusted, prefill = {num2str(est.off), num2str(est.cols_off)}; end
                        rc = rabbit_fov_position.ask_typed(fig, title, ...
                            rabbit_fov_position.shift_prompts('the optical mapping image', which), prefill);
                        if isempty(rc), continue; end   % back to the question
                        over = rabbit_stack_io.overlap_text(om_hw(1), om_hw(2), other_hw(1), other_hw(2), rc(1), rc(2));
                        if startsWith(over, 'no part')
                            uialert(fig, sprintf(['With that shift the optical mapping image lies outside the %s ' ...
                                'recording, so no region could be cut from it.'], which), 'Shift not used');
                            continue;
                        end
                        score = NaN;
                        if isstruct(est) && isfinite(est.ncc), score = est.ncc; end
                        res.mapping = rabbit_fov_position.mapping(rc(1), rc(2), om_hw, 'typed', score, ...
                            sprintf(['typed in by the user when the %s stack was loaded: the optical mapping image ' ...
                            'starts %d pixels down and %d right of the %s image''s top-left (row order stored in ' ...
                            'the files)'], which, rc(1), rc(2), which));
                        res.ok = true;
                        return;
                    otherwise
                        return;   % Cancel
                end
            end
        end

        function p = shift_prompts(what, which)
            %% The two questions for a shift typed in: down and right, in pixels
            % what is shifted inside the image of recording which; down and
            % right as the ROI editor's colour view shows the images (rows
            % as stored in the files)
            p = {sprintf(['Shift down, in pixels: how far below the top of the %s image %s starts (negative if ' ...
                'above). Take it from the areas of interest set in the camera software; the ROI editor''s ' ...
                'colour view shows afterwards whether it lines up.'], which, what), ...
                sprintf('Shift right, in pixels: how far right of the left edge of the %s image it starts (negative if left).', which)};
        end

        function rc = ask_typed(fig, title, prompts, prefill)
            %% Two whole numbers typed in, asked again after a mistake; [] when cancelled
            rc = [];
            while true
                answer = inputdlg(prompts, title, 1, prefill);
                if isempty(answer), return; end
                r = str2double(answer{1});
                c = str2double(answer{2});
                if isfinite(r) && isfinite(c) && r == round(r) && c == round(c)
                    rc = [r c];
                    return;
                end
                uialert(fig, 'Type two whole numbers of pixels, down and right.', 'Shift not used');
                prefill = answer(:)';
            end
        end

        function m = mapping(off, cols_off, om_hw, source, score, provenance)
            %% An offset mapping that records how its position was found
            m = rabbit_stack_io.offset_mapping(off, cols_off, provenance);
            m.om_window_in_rec.rows = sprintf('%d:%d', off, off + om_hw(1));
            m.om_window_in_rec.cols = sprintf('%d:%d', cols_off, cols_off + om_hw(2));
            m.position_source = source;
            m.match_score = score;
        end
    end
end
