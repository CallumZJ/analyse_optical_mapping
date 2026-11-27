function uialert(fig, message, title, varargin)
%% Headless stand-in for uialert
% Collin Snitchler
% 07.10.2026
% Test helper only. tests/helpers/headless goes on the path only when
% OM_APP_HEADLESS=1 (headless scripts and probes). MATLAB's uialert refuses
% a hidden figure, so for a hidden figure this records the alert, prints it
% and calls its CloseFcn, if one is given. For a visible figure it calls
% MATLAB's own uialert.
if headless_figure_shown(fig)
    real_uialert = headless_real_function('uialert');
    real_uialert(fig, message, title, varargin{:});
    return;
end
close_fcn = headless_option(varargin, 'CloseFcn', []);
headless_record('uialert', title, message, '');
if ~isempty(close_fcn)
    event = struct('DialogTitle', char(title), 'Source', fig, 'EventName', 'AlertDialogClosed');
    feval(close_fcn, fig, event);
end
end
