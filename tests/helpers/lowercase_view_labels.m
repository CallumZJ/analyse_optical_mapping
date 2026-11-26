function hits = lowercase_view_labels(texts)
%% Lowercase view labels ("view1".."view4") in shown texts, outside file names and paths
% Collin Snitchler
% 24.11.2026
% The screens write the views View1 to View4; files and folders keep their names (_view1, view2/...). A
% hit is "view<k>" not joined to a file name or path: no letter, digit,
% "_", "/", "\" or "." right before it, and no letter, digit, "_", "/",
% "\" or file extension (".tif") right after it. texts: char, string or a (nested)
% cell of them; hits: the texts with a hit, each with the label found.
hits = {};
texts = flatten(texts);
for k = 1:numel(texts)
    t = texts{k};
    m = regexp(t, '(?<![\w/\\.])view[1-4](?![\w/\\]|\.\w)', 'match');
    if ~isempty(m)
        hits{end + 1} = sprintf('"%s" in: %s', strjoin(unique(m), ', '), t(1:min(end, 160))); %#ok<AGROW>
    end
end
end


function out = flatten(x)
% Every text in x as a 1 x N cell of char
out = {};
if ischar(x)
    out = {x};
elseif isstring(x)
    out = cellstr(x(:))';
elseif iscell(x)
    for k = 1:numel(x)
        out = [out, flatten(x{k})]; %#ok<AGROW>
    end
end
end
