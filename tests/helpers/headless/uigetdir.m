function folder = uigetdir(varargin)
%% Headless stand-in for uigetdir
% Collin Snitchler
% 14.10.2026
% Test helper only (see uigetfile.m in this folder). Returns the next
% folder queued with headless_push('uigetdir', folder); with nothing queued
% it answers Cancel (0).
[found, value] = headless_pop('uigetdir');
if ~found
    folder = 0;
    headless_record('uigetdir', 'Folder selector', 'nothing queued', 'Cancel');
    return;
end
folder = char(value);
headless_record('uigetdir', 'Folder selector', folder, 'Select Folder');
end
