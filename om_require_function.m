function [ok, message] = om_require_function(name, package)
%% Find a function from an outside package; add the copy shipped in third_party
% Collin Snitchler
% 20.11.2026
% Sources: FilterM (Jan Simon, MATLAB File Exchange, BSD licence);
%          findfirst (Bruno Luong, MATLAB File Exchange).
% Some steps of analyse_optical_mapping call MATLAB File Exchange code:
% FiltFiltM (package FilterM, Jan Simon; temporal filtering) and findfirst
% (Bruno Luong; activation maps). A user's saved MATLAB path can miss them,
% or name a folder that was moved, and the step would then stop. FiltFiltM is
% shipped in third_party/FilterM (BSD licence, see NOTICE.md there): when it
% is not on the path, that folder is added to the end of the path for this
% MATLAB session (the saved path is not changed). For a function with no
% copy here, message says which function is missing and where it comes from.
%   ok       true when the function can be called
%   message  '' when ok, otherwise the text for an alert
if nargin < 2 || isempty(package)
    package = name;                                    % the package is named after the function
end
message = '';                                          % nothing to say when the function is found
ok = has_function(name);                               % already on the path (the user's own copy wins)
if ok
    return;
end
here = fileparts(mfilename('fullpath'));               % the repository folder (this file is at its top)
shipped = struct('FiltFiltM', {{'third_party', 'FilterM'}});   % function -> folder of the copy shipped here
if isfield(shipped, name)
    folder = fullfile(here, shipped.(name){:});        % e.g. <repo>/third_party/FilterM
    if isfolder(folder)
        addpath(folder, '-end');                       % after everything else: shadows nothing
        ok = has_function(name);                       % found now?
        if ok
            return;
        end
    end
    message = sprintf(['This step needs %s (package %s), which the repository ships in %s, ', ...
        'but that folder is missing or incomplete. Restore it from the repository, then try again.'], ...
        name, package, folder);
    return;
end
message = sprintf(['This step needs %s, which is not on the MATLAB path. Add the folder that ', ...
    'holds %s.m (package %s, from the MATLAB File Exchange) with Home > Set Path, then try again.'], ...
    name, name, package);
end

function found = has_function(name)
%% True when name is a function file (.m, .p or MEX) MATLAB can call
kind = exist(name, 'file');                            % 2 = .m/.p file, 3 = MEX, 6 = P-code
found = any(kind == [2 3 6]);
end
