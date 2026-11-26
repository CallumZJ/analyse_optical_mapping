classdef rabbit_segmentation_core
    %% Shared segmentation steps
    % Collin Snitchler
    % 03.09.2026
    % Sources: the thresholding of segmentationAssist.mlapp (this repository,
    %          Callum Zgierski-Johnston and Teo Puig Walz), taken out so the
    %          reconstruction masks use the same step.
    % The segmentation used by both the assisted-segmentation apply step
    % (segmentationAssist.threshold_and_plot) and the reconstruction
    % preview (rabbit_segmentation_preview), so the two give the same
    % result. It matches segmentationAssist:
    %   I0 = image .* keep_mask            (NaN = excluded)
    %   I0 = I0 ./ max(I0(:))              (normalise)
    %   I_blur = imgaussfilt(I0, sigma)    (smoothen slider)
    %   I_thr = imbinarize(I_blur, 1 - threshold)   (threshold slider)
    % prepare_frame does the first two lines, segment the last two.
    % Excluded pixels are NaN in the keep-area mask. prepare_frame sets
    % NaN to 0 before normalising, otherwise max() would make the whole
    % frame NaN. In the app the keep mask is all ones at this point, so
    % the result is unchanged.

    methods (Static)

        function I0 = prepare_frame(frame, keep_mask)
            %% Mask and normalise a frame for thresholding
            % frame .* keep_mask with NaN set to 0, divided by its maximum
            % (as segmentationAssist does to app.I0). An empty or
            % non-positive maximum gives an all-zero I0, which segments
            % to an empty mask.
            if nargin < 2 || isempty(keep_mask)
                keep_mask = true(size(frame));
            end
            if ~isequal(size(keep_mask), size(frame))
                error('analyse_om:Segmentation:MaskDims', ...
                    'keep_mask %dx%d does not match frame %dx%d.', ...
                    size(keep_mask, 1), size(keep_mask, 2), ...
                    size(frame, 1), size(frame, 2));
            end
            I0 = double(frame) .* double(keep_mask);
            I0(isnan(I0)) = 0;   % excluded (NaN) -> 0
            mx = max(I0(:));
            if isempty(mx) || ~isfinite(mx) || mx <= 0
                I0 = zeros(size(I0));
                return;
            end
            I0 = I0 ./ mx;
        end

        function I_thr = segment(I0, threshold, sigma_gauss)
            %% Smooth and binarise a prepared frame
            % Gaussian blur with the smoothen sigma, then binarise at
            % 1 - threshold. Returns the logical mask (1 = foreground),
            % as segmentationAssist.threshold_and_plot sets app.I_thr.
            if nargin < 3 || isempty(sigma_gauss)
                sigma_gauss = 4;   % segmentationAssist default
            end
            if nargin < 2 || isempty(threshold)
                threshold = 0.83;  % segmentationAssist default
            end
            I_blur = imgaussfilt(I0, sigma_gauss);
            I_thr = imbinarize(I_blur, 1 - threshold);
        end

    end
end
