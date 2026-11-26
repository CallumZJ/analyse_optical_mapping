function [file, path, index] = uiputfile(varargin)
%% Headless stand-in for uiputfile
% Collin Snitchler
% 14.10.2026
% Test helper only (see uigetfile.m in this folder). Returns the next full
% file path queued with headless_push('uiputfile', path); with nothing
% queued it answers Cancel.
% The call's filters and suggested name are kept for the probes
% (om_headless_last_uiputfile)
setappdata(groot, 'om_headless_last_uiputfile', varargin);
[found, value] = headless_pop('uiputfile');
index = 0;
if ~found
    file = 0; path = 0;
    headless_record('uiputfile', 'Save file', 'nothing queued', 'Cancel');
    return;
end
[folder, name, ext] = fileparts(char(value));
file = [name ext];
path = [folder filesep];
index = 1;
headless_record('uiputfile', 'Save file', char(value), 'Save');
end
