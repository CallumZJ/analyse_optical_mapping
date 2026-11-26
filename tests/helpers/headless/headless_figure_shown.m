function shown = headless_figure_shown(fig)
%% True when fig is a valid figure that is on screen
% Collin Snitchler
% 07.10.2026
% Test helper for the headless uialert/uiconfirm stand-ins.
shown = ~isempty(fig) && isscalar(fig) && isgraphics(fig) && strcmp(char(fig.Visible), 'on');
end
