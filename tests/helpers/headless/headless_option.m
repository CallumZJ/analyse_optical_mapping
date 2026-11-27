function value = headless_option(args, name, default)
%% Value of a name-value option, or the default
% Collin Snitchler
% 07.10.2026
% Test helper for the headless uialert/uiconfirm stand-ins. Names match
% without regard to case, as in MATLAB's own dialogs.
value = default;
for k = 1:2:numel(args) - 1
    if (ischar(args{k}) || isstring(args{k})) && strcmpi(char(args{k}), name)
        value = args{k + 1};
    end
end
end
