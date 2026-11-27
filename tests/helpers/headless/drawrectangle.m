function roi = drawrectangle(varargin)
%% Headless stand-in for drawrectangle
% Collin Snitchler
% 14.10.2026
% Test helper only (see uigetfile.m in this folder). A call with a
% 'Position' goes straight to MATLAB's drawrectangle. A call without one
% would wait for the mouse, so the rectangle the user would draw is taken
% from headless_push('drawrectangle', [x y w h]) instead; with nothing
% queued it fails rather than wait.
real_draw = headless_real_function('drawrectangle');
if ~isempty(headless_option(varargin(2:end), 'Position', [])) || ...
        ~isempty(headless_option(varargin, 'Position', []))
    roi = real_draw(varargin{:});
    return;
end
[found, value] = headless_pop('drawrectangle');
if ~found
    error('OM:Headless:NoRectangle', 'drawrectangle needs a queued rectangle when headless.');
end
headless_record('drawrectangle', 'Draw rectangle', mat2str(value), 'drawn');
roi = real_draw(varargin{:}, 'Position', value);
end
