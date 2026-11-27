classdef seg_main_double < handle
    %% Stand-in for the main app that the assisted area segmentation window reads and writes
    % Collin Snitchler
    % 20.11.2026
    % Test helper only: the window reads processed_data and display, writes
    % processed_data and ui_resume, and resumes opticalmappingUIFigure.
    properties
        processed_data = struct()
        display = struct('normalisation', 1, 'inversion', 0)
        opticalmappingUIFigure
        ui_resume = false
        history_field = struct('Value', {{}})
    end
end
