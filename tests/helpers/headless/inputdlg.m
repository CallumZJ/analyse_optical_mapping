function answer = inputdlg(prompt, title, varargin)
%% Headless stand-in for inputdlg
% Collin Snitchler
% 14.10.2026
% Test helper only (see uigetfile.m in this folder). Returns the next cell
% array of typed values queued with headless_push('inputdlg', {...}); with
% nothing queued it answers Cancel ({}). The prompt is recorded so a probe
% can check what the user was asked.
if nargin < 2, title = ''; end
[found, value] = headless_pop('inputdlg');
if ~found
    answer = {};
    headless_record('inputdlg', title, prompt, 'Cancel');
    return;
end
answer = cellstr(value);
answer = answer(:);
headless_record('inputdlg', title, prompt, strjoin(answer', ' | '));
end
