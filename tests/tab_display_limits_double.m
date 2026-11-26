classdef tab_display_limits_double < rabbit_reconstruction_tab
    %% Probe-side double: run_pipeline with display_limits in its options
    % Collin Snitchler
    % 23.11.2026
    % The app's Reproject run button passes the app's own colour limits as
    % display_limits; this double replaces them with the property when it
    % is set (known values for the probe), and passes every call on to the
    % real tab otherwise. Used by probe_cv_arrows only.

    properties (Access = public)
        display_limits = [];
    end

    methods (Access = public)
        function [ok, err, failed_stage] = run_pipeline(obj, run_id, opts)
            if isstruct(obj.display_limits) && isstruct(opts)
                opts.display_limits = obj.display_limits;
            end
            [ok, err, failed_stage] = run_pipeline@rabbit_reconstruction_tab(obj, run_id, opts);
        end
    end
end
