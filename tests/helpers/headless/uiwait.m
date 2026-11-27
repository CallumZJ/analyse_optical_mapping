function uiwait(fig, timeout)
%% Headless stand-in for uiwait
% Collin Snitchler
% 14.10.2026
% Test helper only. tests/helpers/headless goes on the path only when
% OM_APP_HEADLESS=1. MATLAB's uiwait does not block when MATLAB runs with
% -noFigureWindows, so for a hidden figure this waits until uiresume (the
% stand-in in this folder) is called for it or the figure is deleted.
% Timers keep running while it waits, which is how a probe answers the
% dialog. It gives up after the timeout (default 900 s) with an error, so a
% probe cannot hang. For a visible figure it calls MATLAB's own uiwait.
if nargin < 1 || isempty(fig)
    fig = gcf;
end
if headless_figure_shown(fig)
    real_wait = headless_real_function('uiwait');
    if nargin < 2
        real_wait(fig);
    else
        real_wait(fig, timeout);
    end
    return;
end
if nargin < 2
    timeout = 900;
end
setappdata(fig, 'om_headless_waiting', true);
t0 = tic;
while isvalid(fig) && isappdata(fig, 'om_headless_waiting') && getappdata(fig, 'om_headless_waiting')
    pause(0.05);   % lets timer callbacks run
    if toc(t0) > timeout
        if isvalid(fig), setappdata(fig, 'om_headless_waiting', false); end
        error('OM:Headless:WaitTimeout', 'uiwait on "%s" was not resumed within %g s.', char(fig.Name), timeout);
    end
end
end
