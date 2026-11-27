classdef headless_progress < handle
    %% Progress dialog stand-in for headless runs
    % Collin Snitchler
    % 14.10.2026
    % Test helper for the uiprogressdlg stand-in. Holds the properties the
    % app writes; close() only marks it closed. The newest one is kept in
    % getappdata(groot, 'om_headless_last_progress'). A probe can press
    % Cancel: setappdata(groot, 'om_headless_cancel_after', n) makes the
    % n-th read of CancelRequested (and every later one) true.
    properties (Dependent)
        CancelRequested
        Message
    end
    properties (Access = private)
        cancel_set = false
        reads = 0
        message_now = ''
    end
    properties
        MessageHistory = {}   % every Message written, in order
    end
    properties
        Title = ''
        Value = 0
        Indeterminate = 'off'
        Cancelable = 'off'
        CancelText = 'Cancel'
        ShowPercentage = 'off'
        Icon = ''
        Interpreter = 'none'
        closed = false
    end
    methods
        function obj = headless_progress()
            setappdata(groot, 'om_headless_last_progress', obj);
        end
        function tf = get.CancelRequested(obj)
            obj.reads = obj.reads + 1;
            n = getappdata(groot, 'om_headless_cancel_after');
            tf = obj.cancel_set || (~isempty(n) && obj.reads >= n);
        end
        function set.CancelRequested(obj, v)
            obj.cancel_set = logical(v);
        end
        function m = get.Message(obj)
            m = obj.message_now;
        end
        function set.Message(obj, m)
            obj.message_now = m;
            obj.MessageHistory{end + 1} = char(m);
        end
        function close(obj)
            obj.closed = true;
        end
        function delete(~)
        end
    end
end
