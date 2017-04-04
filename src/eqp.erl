-module(eqp).

-include("../include/eqp.hrl").

-export([
    t/1, 
    create/2,
    delete/1,
    list/0,
    stat/1,
    stat/0,

    req/2,

    update/3
  ]).

-type err() :: {err, {Code::atom(), Reason::binary}}.
-export_type([err/0]).

t(1) -> 
  % {ok, C} = epgsql:connect("localhost", "general", "Maf6eepiecai", [{database, "puzzles"}, {timeout, 4000}]),
  % ...
  % ok = epgsql:close(C).
  %
  QPName = test_qp,
  MFA1   = {epgsql, connect, ["localhost", "general", "Maf6eepiecai", [{database, "puzzles"}, {timeout, 4000}]]},
  MFA2   = {epgsql, close, []},
  Args   = #{
      start => MFA1, 
      stop  => MFA2},
  create(QPName, Args);

t(2) ->
  QPName = test_qp,
  req(QPName, "select * from pg_table");

t(3) ->
  QPName = test_qp,
  delete(QPName).



%
-spec create(QPName::atom(), Args::map()) -> ok | err().
create(QPName, Args) -> 
  Child = #{id        => QPName,
            start     => {eqp_server, start_link, [QPName, Args]},
            restart   => permanent,
            shutdown  => 10000,
            type      => worker,
            modules   => [eqp_server]},
  case supervisor:start_child(eqp_sup, Child) of
    {ok, _Pid} -> ok;
    Else       -> Else
  end.


%
delete(QPName) -> 
  case supervisor:terminate_child(eqp_sup, QPName) of
    ok -> supervisor:delete_child(eqp_sup, QPName);
    Else -> Else
  end.

%
list() ->
  [Name || {Name,_,_,_} <- supervisor:which_children(eqp_sup)].

%
stat() -> 
  list().
stat(QPName) ->
  gen_server:call(QPName, stat).


%
req(QPName, Req) -> 
  gen_server:call(QPName, {req, Req}).



update(_QPName, max_conns,  _Num) -> ok;
update(_QPName, min_conns,  _Num) -> ok;
update(_QPName, free_conns, _Num) -> ok.

