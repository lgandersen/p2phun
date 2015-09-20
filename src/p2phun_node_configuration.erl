-module(p2phun_node_configuration).

-behaviour(gen_server).

-include("peer.hrl").
%% API
-export([start_link/2, listening_port/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {my_id, listening_port}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Id, ListeningPort) ->
    gen_server:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Id, ListeningPort], []).

listening_port(Id) ->
    gen_server:call(?MODULE_ID(Id), listening_port).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Id, ListeningPort]) ->
    {ok, #state{my_id=Id, listening_port=ListeningPort}}.

handle_call(listening_port, _From, State) ->
    {reply, State#state.listening_port, State};
handle_call(_Request, _From, State) ->
    {reply, error, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
