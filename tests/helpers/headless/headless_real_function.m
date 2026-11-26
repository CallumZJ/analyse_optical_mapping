function f = headless_real_function(name)
%% Handle to MATLAB's own function that a stand-in here shadows
% Collin Snitchler
% 07.10.2026
% Test helper for the headless uialert/uiconfirm stand-ins. The handle is
% made while MATLAB's own folder is the current folder, where its file
% takes precedence over this folder, and is kept for later calls.
persistent cache
if isempty(cache)
    cache = containers.Map();
end
if isKey(cache, name)
    f = cache(name);
    return;
end
here = fileparts(mfilename('fullpath'));
found = which(name, '-all');
found = found(~startsWith(found, here) & endsWith(found, {'.m', '.p'}));
if isempty(found)
    error('OM:Headless:NoRealFunction', 'MATLAB''s own %s was not found.', name);
end
old = cd(fileparts(found{1}));
restore = onCleanup(@() cd(old));
f = str2func(name);
cache(name) = f;
end
