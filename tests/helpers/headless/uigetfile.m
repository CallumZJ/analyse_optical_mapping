function [file, path, index] = uigetfile(varargin)
%% Headless stand-in for uigetfile
% Collin Snitchler
% 14.10.2026
% Test helper only. tests/helpers/headless goes on the path only when
% OM_APP_HEADLESS=1. Returns the next full file path queued with
% headless_push('uigetfile', path), split as uigetfile returns it (the
% folder ends with a separator). With nothing queued it answers as if the
% user pressed Cancel, so no window can open.
[found, value] = headless_pop('uigetfile');
index = 0;
if ~found
    file = 0; path = 0;
    headless_record('uigetfile', 'File selector', 'nothing queued', 'Cancel');
    return;
end
[folder, name, ext] = fileparts(char(value));
file = [name ext];
path = [folder filesep];
index = 1;
headless_record('uigetfile', 'File selector', char(value), 'Open');
end
