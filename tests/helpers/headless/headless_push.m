function headless_push(name, value)
%% Queue an answer for a headless stand-in
% Collin Snitchler
% 14.10.2026
% Test helper for the headless stand-ins (see headless_pop). Answers are
% taken in the order they were queued.
queue = getappdata(groot, 'om_headless_queue');
if isempty(queue) || ~isstruct(queue)
    queue = struct();
end
if ~isfield(queue, name)
    queue.(name) = {};
end
queue.(name){end + 1} = value;
setappdata(groot, 'om_headless_queue', queue);
end
