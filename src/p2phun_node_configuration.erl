-module(p2phun_node_configuration).

-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(MODULE_ID(Id), p2phun_utils:id2proc_name(?MODULE, Id)).
-record(state, {my_id, listening_port}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Id, ListeningPort) ->
    lager:info("AAAWWWW YIIIIIIIIIZZZ"),
    gen_server:start_link({local, ?MODULE_ID(Id)}, ?MODULE, [Id, ListeningPort], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Id, ListeningPort]) ->
    {ok, #state{my_id=Id, listening_port=ListeningPort}}.

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
