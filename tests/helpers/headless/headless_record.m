function headless_record(kind, title, message, answer)
%% Keep and print a dialog that a headless run did not show
% Collin Snitchler
% 07.10.2026
% Test helper for the headless uialert/uiconfirm stand-ins. The dialogs are
% kept in the root object's appdata 'om_headless_dialogs', so a probe can
% check them, and printed so they appear in the probe's log.
if iscell(message) || isstring(message)
    message = strjoin(cellstr(message), ' ');
end
entry = struct('kind', kind, 'title', char(title), 'message', char(message), 'answer', char(answer));
dialogs = getappdata(groot, 'om_headless_dialogs');
if isempty(dialogs)
    dialogs = entry;
else
    dialogs(end + 1) = entry;
end
setappdata(groot, 'om_headless_dialogs', dialogs);
if isempty(answer)
    fprintf('Headless %s (not shown): %s - %s\n', kind, entry.title, entry.message);
else
    fprintf('Headless %s (not shown, answered "%s"): %s - %s\n', kind, answer, entry.title, entry.message);
end
end
