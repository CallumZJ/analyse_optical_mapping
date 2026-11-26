function [found, value] = headless_pop(name)
%% Next queued answer for a headless stand-in
% Collin Snitchler
% 14.10.2026
% Test helper for the headless stand-ins. A probe queues the answers a user
% would give (file choices, typed values, rectangles) in the root object's
% appdata 'om_headless_queue', a struct with one cell array per stand-in
% name. This takes the first answer for name; found is false when none is
% queued, so the stand-in can cancel instead of opening a window.
found = false;
value = [];
queue = getappdata(groot, 'om_headless_queue');
if isempty(queue) || ~isstruct(queue) || ~isfield(queue, name) || isempty(queue.(name))
    return;
end
found = true;
value = queue.(name){1};
queue.(name)(1) = [];
setappdata(groot, 'om_headless_queue', queue);
end
