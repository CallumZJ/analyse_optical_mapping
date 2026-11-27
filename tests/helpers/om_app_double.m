classdef om_app_double < handle
    %% Stand-in for the main app in probes that need no window
    % Collin Snitchler
    % 02.11.2026
    % Test helper only. Holds the two properties the cut, the ROI editor and
    % the segmentation tools read and write, as a handle, so a probe sees
    % what they stored in data.
    properties
        data = struct()
        file_info = struct('file', '', 'name', '', 'path', '', 'type', '')
        processed_data = struct()
    end
end
