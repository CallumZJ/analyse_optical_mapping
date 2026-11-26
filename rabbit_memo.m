function varargout = rabbit_memo(action, kind, key, value)
%% Small in-memory cache for checks whose result depends only on content
% Collin Snitchler
% 20.11.2026
% Purpose: keep the result of a pure check (a PLY validation, a JSON parse,
%          a decoded record) so that the same check on the same content is
%          not repeated within a session. The caller builds the key from
%          the content itself (its SHA-256), so a changed file is a new key
%          and is checked again.
%   [hit, value] = rabbit_memo('get', kind, key)
%   rabbit_memo('put', kind, key, value)
%   rabbit_memo('clear')
persistent store order                             % the cache and the order its entries were added
if isempty(store)
    store = containers.Map('KeyType', 'char', 'ValueType', 'any');   % text key -> cached value
    order = {};                                    % oldest first, for eviction
end
max_entries = 48;                                  % enough for a few runs' files, small in memory
switch action
    case 'get'
        k = [kind '|' key];                        % one key space per kind of check
        if isKey(store, k)
            varargout = {true, store(k)};          % a hit: the stored result
        else
            varargout = {false, []};               % a miss: the caller computes it
        end
    case 'put'
        k = [kind '|' key];
        if ~isKey(store, k)
            order{end + 1} = k;                    % remember when it was added
        end
        store(k) = value;                          % keep the result
        while numel(order) > max_entries           % drop the oldest beyond the limit
            remove(store, order{1});
            order(1) = [];
        end
    case 'clear'
        store = containers.Map('KeyType', 'char', 'ValueType', 'any');   % forget everything
        order = {};
    otherwise
        error('rabbit_memo:action', 'Unknown action %s (get, put or clear).', action);
end
end
