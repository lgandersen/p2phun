-module(p2phun_app).

-behaviour(application).

-include("peer.hrl").

%% Application callbacks
-export([start/0, start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================
start() -> application:ensure_all_started(p2phun).

start(_StartType, _StartArgs) ->
    {ok, JsonApiPort} = application:get_env(p2phun, json_api_port),
    lager:info("JSON API listening on port ~p", [JsonApiPort]),
    {ok, SupPid} = p2phun_sup:start_link(JsonApiPort),
    {ok, SupPid}.

stop(_State) -> ok.
