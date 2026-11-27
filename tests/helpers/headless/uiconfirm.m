function choice = uiconfirm(fig, message, title, varargin)
%% Headless stand-in for uiconfirm
% Collin Snitchler
% 07.10.2026
% Test helper only. tests/helpers/headless goes on the path only when
% OM_APP_HEADLESS=1 (headless scripts and probes). MATLAB's uiconfirm needs
% a visible figure, so for a hidden figure this records the question and
% answers with the default option, as if the user pressed Enter. With a
% CloseFcn the answer goes to the CloseFcn instead. For a visible figure it
% calls MATLAB's own uiconfirm. An answer queued with headless_push
% ('uiconfirm', option) is used instead of the default.
if headless_figure_shown(fig)
    real_uiconfirm = headless_real_function('uiconfirm');
    if nargout > 0
        choice = real_uiconfirm(fig, message, title, varargin{:});
    else
        real_uiconfirm(fig, message, title, varargin{:});
    end
    return;
end
options = cellstr(headless_option(varargin, 'Options', {'OK', 'Cancel'}));
default = headless_option(varargin, 'DefaultOption', 1);
if ischar(default) || isstring(default)
    index = find(strcmp(options, char(default)), 1);
else
    index = default;
end
if isempty(index), index = 1; end
% A probe can queue the option the user would pick with
% headless_push('uiconfirm', 'Yes'); otherwise the default is taken
[queued, pick] = headless_pop('uiconfirm');
if queued
    picked = find(strcmp(options, char(pick)), 1);
    if isempty(picked)
        error('OM:Headless:NoSuchOption', 'Queued answer "%s" is not an option of "%s".', char(pick), char(title));
    end
    index = picked;
end
answer = options{index};
headless_record('uiconfirm', title, message, answer);
close_fcn = headless_option(varargin, 'CloseFcn', []);
if ~isempty(close_fcn)
    event = struct('DialogTitle', char(title), 'SelectedOption', answer, ...
        'SelectedOptionIndex', index, 'Source', fig, 'EventName', 'ConfirmDialogClosed');
    feval(close_fcn, fig, event);
end
if nargout > 0
    choice = answer;
end
end
