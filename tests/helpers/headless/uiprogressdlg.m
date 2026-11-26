function dlg = uiprogressdlg(fig, varargin)
%% Headless stand-in for uiprogressdlg
% Collin Snitchler
% 14.10.2026
% Test helper only. tests/helpers/headless goes on the path only when
% OM_APP_HEADLESS=1. MATLAB's uiprogressdlg refuses a hidden figure, so for
% a hidden figure this returns a headless_progress object that takes the
% same property writes and close() and is never cancelled. For a visible
% figure it calls MATLAB's own uiprogressdlg.
if headless_figure_shown(fig)
    real_dlg = headless_real_function('uiprogressdlg');
    dlg = real_dlg(fig, varargin{:});
    return;
end
dlg = headless_progress();
for k = 1:2:numel(varargin) - 1
    name = char(varargin{k});
    if isprop(dlg, name)
        dlg.(name) = varargin{k + 1};
    end
end
end
