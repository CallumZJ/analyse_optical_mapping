classdef cut_app_double < handle
    %% Stand-in for the main app in probes of the TIFF cut with its window
    % Collin Snitchler
    % 20.11.2026
    % Test helper only: om_app_double plus the app's (hidden) window, which
    % the cut's progress dialog and alerts use.
    properties
        data = struct()
        file_info = struct('file', '', 'name', '', 'path', '', 'type', '')
        processed_data = struct()
        opticalmappingUIFigure
    end
end
