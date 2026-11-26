function v = om_test_getenv(name)
%% Value of a test environment variable ('' when not set)
% Collin Snitchler
% 23.11.2026
% The probes read their data variables (OM_TEST_*) through this one
% function, so a change to how they are found is made in one place.
v = getenv(name);
end
