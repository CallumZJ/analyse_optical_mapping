function probe_binned_map_projection
%% Probe: an activation map made after binning is projected onto the mesh
% Collin Snitchler
% 20.11.2026
% The user binned the optical mapping data 2x2 and made the activation map;
% the projection then stopped: "Activation canvas is 207x758 but the ROI
% JSON pins a 413x1515 canvas". A binned map is ceil(H/N) x ceil(W/N) of
% the regions' canvas; each of its pixels now goes over its N x N block.
%   B1  unbin_canvas: 207x758 back to 413x1515, factor 2, block for block
%   B2  split_canvas of a 2x2-binned map gives the views of the full map it
%       was binned from (a map constant over each 2x2 block), and says 2
%   B3  a map of another size is still refused (CanvasMismatch)
% Usage: matlab -batch "addpath('<repo>/tests'); probe_binned_map_projection"
repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
pass = 0; fail = 0;

%% B1
small = reshape(1:207 * 758, 207, 758);
[big, n] = rabbit_rhythm_reproject.unbin_canvas(small, 413, 1515);
ok1 = n == 2 && isequal(size(big), [413 1515]) && big(1, 1) == small(1, 1) && big(2, 2) == small(1, 1) && ...
    big(3, 3) == small(2, 2) && big(413, 1515) == small(207, 758) && big(412, 1514) == small(206, 757);
record('B1 207x758 back to 413x1515, factor 2, block for block', ok1, sprintf('n %d, %s', n, mat2str(size(big))));

%% B2 rotation 3 (the app's default): canvas max(widths) x sum(heights)
bounds = [11 101 210 300; 21 401 230 600; 31 1 220 190; 41 701 260 880];   % view2;view3;view1;view4
hh = bounds(:, 3) - bounds(:, 1) + 1; ww = bounds(:, 4) - bounds(:, 2) + 1;
H = max(ww); W = sum(hh);
rng(5, 'twister');
coarse = rand(ceil(H / 2), ceil(W / 2));
coarse(coarse < 0.1) = NaN;                                  % missing pixels stay missing
full = coarse(min(ceil((1:H) / 2), end), min(ceil((1:W) / 2), end));   % constant over each 2x2 block
[vf, ~, ~, nf] = rabbit_rhythm_reproject.split_canvas(full, bounds, 3);
[vb, ~, ~, nb] = rabbit_rhythm_reproject.split_canvas(coarse, bounds, 3);
record('B2 the binned map gives the full map''s views; factor 2 said', nf == 1 && nb == 2 && isequaln(vf, vb), ...
    sprintf('%d, %d', nf, nb));

%% B3
threw = '';
try
    rabbit_rhythm_reproject.split_canvas(rand(H - 7, W), bounds, 3);
catch ME
    threw = ME.identifier;
end
record('B3 another size is still refused', strcmp(threw, 'analyse_om:Reprojection:CanvasMismatch'), threw);

fprintf('\nPROBE_BINNED_MAP_PROJECTION RESULT: %d passed, %d failed\n', pass, fail);
if fail > 0
    error('%d check(s) failed.', fail);
end

    function record(name, ok, detail)
        if ok
            fprintf('PASS %s\n', name); pass = pass + 1;
        else
            fprintf('FAIL %s: %s\n', name, detail); fail = fail + 1;
        end
    end
end
