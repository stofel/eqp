%%%-------------------------------------------------------------------
%% @doc eqp top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(eqp_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    SupFlags = #{strategy => simple_one_for_one, intensity => 100, period => 1},
    ChildSpecs = #{
      id       => eqp,
      start    => {eqp_server, start_link, []},
      restart  => permanent,
      shutdown => 10000,
      type     => worker,
      modules  => [eqp_server]
    },
    {ok, {SupFlags, ChildSpecs}}.

%%====================================================================
%% Internal functions
%%====================================================================
