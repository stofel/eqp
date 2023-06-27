-module(eqp).

-include("../include/eqp.hrl").

-export([
    create/2,
    delete/1,
    list/0,
    stat/1,
    stat/0,

    req/2, req/3,

    update/3
  ]).

-type err() :: {err, {Code::atom(), Reason::binary}}.
-export_type([err/0]).


%
-spec create(QPName::{not_register, term()}|atom(), Args::map()) -> ok | {ok, pid()} | err().
create(QPName, Args) -> 
  {IsRegister, Id} = case QPName of
    {not_register, Term} -> {false, Term};
    Atom when is_atom(Atom) -> {true, Atom}
  end,
  Child = #{id        => Id,
            start     => {eqp_server, start_link, [QPName, Args]},
            restart   => permanent,
            shutdown  => 10000,
            type      => worker,
            modules   => [eqp_server]},
  case supervisor:start_child(eqp_sup, Child) of
    {ok, Pid} ->
      case IsRegister of
        true -> ok;
        false -> {ok, Pid}
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
  [{Name, Pid} || {Name,Pid,_,_} <- supervisor:which_children(eqp_sup)].

%
stat() -> 
  list().
stat(QPPid) when is_pid(QPPid) ->
  gen_server:call(QPPid, stat);
stat(QPName) ->
  case [Pid || {Name,Pid,_,_} <- supervisor:which_children(eqp_sup), Name == QPName] of
    [Pid] when is_pid(Pid) -> gen_server:call(Pid, stat);
    _ -> ?e(not_exists)
  end.


%
req(QPPid, Req) ->
  req(QPPid, Req, 8000).
req(QPPid, {Req, []}, Timeout) -> 
  req(QPPid, Req, Timeout);
req(QPPid, Req, Timeout) -> 
  try gen_server:call(QPPid, {req, Req}, Timeout)
  catch
    E:R -> 
      ?INF("req err", {E,R}), 
      ?e(timeout)
  end.



update(_QPName, max_conns,  _Num) -> ok;
update(_QPName, min_conns,  _Num) -> ok;
update(_QPName, free_conns, _Num) -> ok.

