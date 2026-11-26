function out = rabbit_sauvola(img, window, k)
%% Sauvola binarisation of one image
% Collin Snitchler
% 19.11.2026
% Purpose: the default pre-processing of Ccube calibration tiles before
%          pyCamSet looks for the cube (rabbit_calibration.make_job).
% Each pixel is compared with a threshold from the mean m and standard
% deviation s of the window x window pixels around it:
%   T = m * (1 + k * (s / R - 1)),   R = 127.5
% (Sauvola and Pietikainen 2000, Pattern Recognition 33(2):225-236). R is
% half the 8-bit range, as in scikit-image's threshold_sauvola (van der
% Walt et al. 2014, PeerJ 2:e453), whose border handling this follows: the
% image is mirrored about its edge pixels ('reflect', the edge pixel not
% repeated). With k = 0 the threshold is the local mean. The defaults are
% chosen for the rabbit data, not taken from a reference: on the reference
% rabbit ccube1 calibration recordings, window 7 and k 0 was the only
% setting tried (CLAHE alone, Sauvola alone with windows 5-51 and k 0-0.15,
% and both) with which all three passed the calibration gates; without it
% one recording's tile 4 never placed the cube.
% Inputs:
%   img: a 2-D image of any numeric class; it is first scaled to whole
%       numbers 0-255 between its own minimum and maximum
%   window: odd window size in pixels (an even one is made odd, + 1)
%   k: Sauvola's k
% Output:
%   out: uint8, 255 where the scaled image is above T, else 0
if ndims(img) ~= 2
    error('analyse_om:Calibration:Not2D', 'rabbit_sauvola needs a 2-D image.');
end
window = double(window);
if mod(window, 2) == 0
    window = window + 1;   % an odd window, so the pixel sits in its middle
end
x = double(img);
lo = min(x(:));
hi = max(x(:));
if hi > lo
    x = round((x - lo) * (255 / (hi - lo)));   % whole numbers 0-255, as an 8-bit image
else
    x = zeros(size(x));
end
h = floor(window / 2);
[nr, nc] = size(x);
if nr <= h || nc <= h
    error('analyse_om:Calibration:Small', 'The image (%d x %d) is smaller than the window (%d).', nr, nc, window);
end
% Mirror about the edge pixels: rows h+1..2, the image, then nr-1..nr-h
ri = [h + 1:-1:2, 1:nr, nr - 1:-1:nr - h];
ci = [h + 1:-1:2, 1:nc, nc - 1:-1:nc - h];
p = x(ri, ci);
% Window sums of the values and their squares from cumulative sums
s1 = box_sum(p, window);
s2 = box_sum(p .^ 2, window);
n = window * window;
m = s1 / n;
s = sqrt(max(s2 / n - m .^ 2, 0));   % rounding can leave a tiny negative variance
T = m .* (1 + k * (s / 127.5 - 1));
out = uint8(x > T) * 255;
end

function s = box_sum(p, w)
%% Sum over every w x w window of a padded image (the 'valid' part)
c = cumsum(cumsum(p, 1), 2);
c = [zeros(1, size(c, 2) + 1); zeros(size(c, 1), 1), c];   % a zero row and column in front
s = c(w + 1:end, w + 1:end) - c(1:end - w, w + 1:end) - c(w + 1:end, 1:end - w) + c(1:end - w, 1:end - w);
end
