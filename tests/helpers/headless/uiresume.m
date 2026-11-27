function uiresume(fig)
%% Headless stand-in for uiresume
% Collin Snitchler
% 14.10.2026
% Test helper only (see uiwait.m in this folder). Ends a headless uiwait on
% a hidden figure; for a visible figure it calls MATLAB's own uiresume.
if nargin < 1 || isempty(fig)
    fig = gcf;
end
if ~isvalid(fig)
    return;
end
if headless_figure_shown(fig)
    real_resume = headless_real_function('uiresume');
    real_resume(fig);
    return;
end
setappdata(fig, 'om_headless_waiting', false);
end
