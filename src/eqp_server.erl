%%
%% Server manage queue and pool
%%

%%
%% Out queue ordset
%% [{Until, con, Conn},  %% Return or starting connect wait
%%  {Until, req, From],  %% Req in queue
%% In queue proplist
%% [{From, Req}]         %% Req in queue
%% 

-module(eqp_server).

-behaviour(gen_server).

-export([start_link/2]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("../include/eqp.hrl").


%
start_link(QPName, Args) when is_atom(QPName) -> 
  gen_server:start_link({local, QPName}, ?MODULE, Args#{qp_name => QPName}, []);
start_link(_, _) -> 
  {error, wrong_args}.


init(Args = #{qp_name := QPName, start := MFA1, stop := MFA2}) ->
  ?INF("init QP server", Args),
  process_flag(trap_exit, true),

  S = #{qp_name => QPName,        %% QPName
        %% Queue
        out     => ordsets:new(), %% Until timeout queue
        in      => ordsets:new(), %% Incoming req queue
        %% Poll
        con     => [],            %% Connections
        fre     => [],            %% Free conns in pool
        min     => maps:get(min, Args, 2),  %% Min connections
        max     => maps:get(max, Args, 5),  %% Max connections
        adv     => maps:get(adv, Args, 1),  %% Advance connections
        ini     => [],            %% Pids spawned for init conns
        start   => MFA1,          %% MFA to start sub_worker process
        stop    => MFA2,          %% MFA to stop sub_worker process
        %% stat
        rcount  => 0,             %% request count
        rate    => eqp_mavg:new() %% mavg of requests
        },
  {ok, try_advance(S, ?mnow)}.

terminate(_Reason, #{qp_name := QPName}) -> 
  ?INF("terminate", {QPName, self()}),
  ok.

code_change(_OldVersion, State, _Extra) -> 
  {ok, State}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Gen Server api
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% infos
handle_info(timeout, State)         -> timeout_(State);
handle_info({'EXIT',Pid,R}, State)  -> somebody_exit_(State, Pid, R);
handle_info(Msg, S)                 -> ?INF("Unk msg:", Msg), {noreply, S, 0}.
%% casts                          
handle_cast({ans_ret, Conn, A}, S)  -> ans_ret_(S, Conn, A);
handle_cast({ans, Ans}, S)          -> ans_(S, Ans);
handle_cast({ans_stp, Conn, A}, S)  -> ans_stp_(S, Conn, A);
handle_cast({ret, From, Conn}, S)   -> ret_(S, From, Conn);
handle_cast({ret, Conn}, S)         -> ret_(S, Conn);
handle_cast({stp, Conn}, S)         -> stp_(S, Conn);
handle_cast(_Req, S)                -> ?INF("Unknown cast", _Req), {noreply, S, 0}.
%% calls                            
handle_call({req, Args}, From, S)   -> req_(S, From, Args);
handle_call(stat, _From, S)         -> stat_(S);
handle_call(_Req, _From, S)         -> {reply, ?e(unknown_command), S, 0}.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
stat_(S = #{in := In, out := Out}) ->
  Rate = maps:get(rate, S, eqp_mavg:new()),
  Stat = S#{in := length(In), out := length(Out), rate => eqp_mavg:rate(Rate)},
  Reply = {ok, Stat},
  {reply, Reply, S, 0}.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%





%% Request
req_(S = #{in := In, out := Out}, From, Args) ->
  NewIn  = [{From, Args}|In],
  Timeout = 5000,
  Until = ?mnow + Timeout,
  NewOut = ordsets:add_element({Until, req, From}, Out),
  Rcount = maps:get(rcount, S, 0), Rate = maps:get(rate, S, eqp_mavg:new()),
  {noreply, S#{in := NewIn, out := NewOut, rcount => Rcount+1, rate => eqp_mavg:event(Rate)}, 0}.

%% Answer
ans_(S = #{out := Out}, AnswerPack) ->
  NewOutFun = fun
    (Fu, [{From, Ans}|Rest], OutAcc) -> 
      case lists:keytake(From, 3, OutAcc) of
        {value, _, NewOutAcc} -> gen_server:reply(From, Ans), Fu(Fu, Rest, NewOutAcc);
        false -> Fu(Fu, Rest, OutAcc)
      end;
    (_F, [], OutAcc) -> OutAcc
  end,
  NewOut = NewOutFun(NewOutFun, AnswerPack, Out),

  {noreply, S#{out := NewOut}, 0}.


%% Answer and return connection from work
ans_ret_(S = #{out := Out, con := Cs, fre := Fre}, Conn, AnswerPack) ->
  NewOutFun = fun
    (Fu, [{From, Ans}|Rest], OutAcc) -> 
      case lists:keytake(From, 3, OutAcc) of
        {value, _, NewOutAcc} -> gen_server:reply(From, Ans), Fu(Fu, Rest, NewOutAcc);
        false -> Fu(Fu, Rest, OutAcc)
      end;
    (_F, [], OutAcc) ->
      case lists:keytake(Conn, 3, OutAcc) of
        {value, _, RestOut} -> RestOut;
        false -> OutAcc
      end
  end,
  NewOut = NewOutFun(NewOutFun, AnswerPack, Out),
  NewFre = case lists:member(Conn, Cs) of true -> [Conn|Fre]; false -> Fre end,
  {noreply, S#{out := NewOut, fre := NewFre}, 0}.


%% Answer and clean stoped worker
ans_stp_(S = #{out := Out, con := Cs}, Conn, AnswerPack) ->
  NewOutFun = fun
    (Fu, [{From, Ans}|Rest], OutAcc) -> 
      case lists:keytake(From, 3, OutAcc) of
        {value, _, NewOutAcc} -> gen_server:reply(From, Ans), Fu(Fu, Rest, NewOutAcc);
        false -> Fu(Fu, Rest, OutAcc)
      end;
    (_F, [], OutAcc) ->
      case lists:keytake(Conn, 3, OutAcc) of
        {value, _, RestOut} -> RestOut;
        false -> OutAcc
      end
  end,
  NewOut = NewOutFun(NewOutFun, AnswerPack, Out),
  NewCs  = lists:delete(Conn, Cs),
  {noreply, S#{out := NewOut, con := NewCs}, 0}.


%% Return connection from work
ret_(S = #{out := Out, con := Cs, fre := Fre}, Conn) -> 
  NewOut = case lists:keytake(Conn, 3, Out) of 
    {value, _, RestOut} -> RestOut;
    false -> Out
  end,
  NewFre = case lists:member(Conn, Cs) of true -> [Conn|Fre]; false -> Fre end,
  {noreply, S#{out := NewOut, fre := NewFre}, 0}.



%% Return connection from advance init
ret_(S = #{out := Out, con := Cs, ini := Ini, fre := Fre}, From, Conn) ->
  F = fun(V, Vs) -> case lists:member(V, Vs) of true -> Vs; false -> [V|Vs] end end,
  {NewCs, NewOut, NewIni, NewFre} = case lists:keytake(From, 3, Out) of
    {value, _, RestOut} -> {F(Conn, Cs), RestOut, lists:delete(From, Ini), F(Conn, Fre)};
    false -> do_nothing, {Cs, Out, Ini, Fre}
  end,
  {noreply, S#{out := NewOut, con := NewCs, ini := NewIni, fre := NewFre}, 0}.



%% Stop connection due rotate time
stp_(S = #{con := Cs, fre := Fre}, Conn) ->
  %% TODO delete from queues
  {noreply, S#{con := lists:delete(Conn, Cs), fre := lists:delete(Conn, Fre)}, 0}.




%% Manage request timeout and return connects timeouts
timeout_(S) ->
  Now = ?mnow,

  %% Manage out queue
  OutQFun = fun
    %% Timeouted request
    (Fu, AccS = #{out := [{U,req,From}|Rest], in := I}) when U =< Now ->
        ?INF("timeout_req", From),
        gen_server:reply(From, timeout),
        Fu(Fu, AccS#{out := Rest, in := lists:keydelete(From, 1, I)});
    %% Timeouted connection
    (Fu, AccS = #{out := [{U,con,Conn}|Rest], con := Cs}) when U =< Now ->
        ?INF("timeout_conn", Conn),
        Fu(Fu, AccS#{out := Rest, con := lists:delete(Conn, Cs)});
    %% Timeouted advance connection
    (Fu, AccS = #{out := [{U,adv,Conn}|Rest], ini := Ini}) when U =< Now ->
        ?INF("timeout_conn", Rest),
        Fu(Fu, AccS#{out := Rest, ini := lists:delete(Conn, Ini)});
    %% Manage in queue
    (_F, AccS = #{in  := []}) -> try_advance(AccS, Now);
    (_F, AccS)                -> try_send(AccS, Now)
  end,

  %?INF("timeout", Fre),
  case OutQFun(OutQFun, S) of
     NewS = #{out := [{Until,_,_}|_]} -> {noreply, NewS, Until - Now};
     NewS                             -> {noreply, NewS, 100*1000}
  end.

%%
somebody_exit_(S = #{fre := Fre, con := Con, ini := Ini}, Pid, Reason) ->
  case lists:member(Pid, Con) of true -> ?INF("Close conn", {Pid, Reason}); false -> do_nothing end,
  case lists:member(Pid, Ini) of true -> ?INF("Close init", {Pid, Reason}); false -> do_nothing end,
  case lists:member(Pid, Fre) of true -> ?INF("Close free", {Pid, Reason}); false -> do_nothing end,
  NewS = S#{
    con := lists:delete(Pid, Con),
    fre := lists:delete(Pid, Fre),
    ini := lists:delete(Pid, Ini)
  },
  {noreply, NewS, 0}. 
  

  

%% 
%% 1. send part of queued requests
-define(MAX_PACK_SIZE, 10).
try_send(S = #{in := In, fre := [C|RestFree], con := Cs, ini := Ini}, Now) ->
  PoolSize = length(Cs) + length(Ini),
  QLen     = length(In),
  Pack     = trunc(QLen/PoolSize)+1,
  PackLen  = min(?IF(Pack =< ?MAX_PACK_SIZE, Pack, ?MAX_PACK_SIZE), QLen),
  {P, RIn} = lists:split(?IF(PackLen =< ?MAX_PACK_SIZE, PackLen, ?MAX_PACK_SIZE), In),

  %% Send pack
  gen_server:cast(C, {pack, P}),
  NewS = S#{in := RIn, fre := RestFree},
  ?IF(RIn == [], try_advance(NewS, Now),
    ?IF(RestFree == [], try_advance(NewS, Now), try_send(NewS, Now)));
%
try_send(S = #{fre := []}, Now) ->
  try_advance(S, Now).
 

%%
%% 2. if need advance new connections
try_advance(S = #{ini := Ini, con := Cs,  fre := Fre,
                  min := Min, max := Max, adv := Adv}, Now) ->
  IniLen   = length(Ini),
  PoolSize = length(Cs) + length(Ini),
  FreLen   = length(Fre) + IniLen,
  ZerroFun = fun(V) when V >= 0 -> V; (_) -> 0 end, 
  % Min conns to be started
  MinMin  = ZerroFun(Min - PoolSize), 
  % Max conns to be started
  MinFree = ZerroFun(Adv - FreLen),
  MinMax  = ZerroFun(Max - PoolSize),
  MinAdv = min(MinFree, MinMax),
  % Start max possible connections
  start_worker(S, _WorkersToAddNum = max(MinAdv, MinMin), Now).
 



%%
-define(INIT_TIMEOUT, 5000).
start_worker(S, 0, _) -> 
  S;
start_worker(S = #{qp_name := QPName, start := MFA1, stop := MFA2}, WorkersToAddNum, Now) ->
  WorkerArgs = #{qp_name => QPName,
                 start   => MFA1,
                 stop    => MFA2},
  StartWorkerFun = fun() -> 
      case gen_server:start(eqp_worker, WorkerArgs, []) of 
        {ok, Pid} -> gen_server:cast(QPName, {ret, self(), Pid});
        Else      -> ?INF("Start worker err", Else), do_nothing
      end
    end,
  Start = fun
    (Fu, Acc = #{out := Out, ini := Ini}, N) when N > 0 ->
        IniPid  = spawn(StartWorkerFun),
        NewOut  = ordsets:add_element({Now + ?INIT_TIMEOUT, adv, IniPid}, Out),
        Fu(Fu, Acc#{out := NewOut, ini := [IniPid|Ini]}, N-1);
    (_F, Acc, _) -> Acc
  end,
  Start(Start, S, WorkersToAddNum).
  

