-module(eqp).

-include("../include/eqp.hrl").

-export([
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


%
-spec create(QPName::not_register|atom(), Args::map()) -> ok | {ok, pid()} | err().
create(QPName, Args) -> 
  case supervisor:start_child(eqp_sup, [QPName, Args]) of
    {ok, Pid} ->
      case QPName == not_register of
        true -> {ok, Pid};
        false -> ok
      end;
    Else ->
      Else
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
  try gen_server:call(QPName, {req, Req}, 8000)
  catch
    E:R -> 
      ?INF("req err", {E,R}), 
      ?e(timeout)
  end.



update(_QPName, max_conns,  _Num) -> ok;
update(_QPName, min_conns,  _Num) -> ok;
update(_QPName, free_conns, _Num) -> ok.

