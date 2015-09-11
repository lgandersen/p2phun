-module(p2phun_node_configuration).

-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(MODULE_ID(Id), id2proc_name(?MODULE, Id)).
-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================

start_link({Id, ListeningPort}) ->
    gen_server:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Id, ListeningPort], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Id, ListeningPort]) ->
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

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
