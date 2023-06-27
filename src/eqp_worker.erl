%%
%% Server worker manage 
%%

-module(eqp_worker).

-behaviour(gen_server).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("../include/eqp.hrl").

-define(CONN_TTL,     600).   % seconds
-define(CONN_MAX_REQ, 20000). % max requests due rotation


init(_Args = #{qp_pid := QPPid, start := {M,F,A}, stop := MFA2}) ->
  %process_flag(trap_exit, true),
  try apply(M,F,A) of
    {ok, C} ->
      Now = ?now,
      S = #{qp_pid  => QPPid,  %% QPPid
            start   => {M,F,A}, %%
            stop    => MFA2,    %%
            pack    => [],      %% Pack of requests
            conn    => C,       %% Conn reference
            count   => 0,       %% Num of requests
            idle    => 50000,   %% ms? idle timeout
            until   => Now + 300 + rand:uniform(100), %% sec worker time to live until
            init    => Now},   %% Init time
      link(QPPid),
      {ok, S};
    Else ->
      ?INF("Connect error", Else),
      Else
    catch
      E:R:T ->
        ?e(crash, #{E => R, t => T})
  end.

%
terminate(_Reason, #{qp_pid := QPPid, stop := {M, F, A}, conn := C}) ->
  unlink(QPPid),
  apply(M, F, [C|A]),
  ok.

%
code_change(_OldVersion, State, _Extra) ->
  {ok, State}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Gen Server api
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% infos
handle_info(timeout, State)       -> timeout_(State);
handle_info(Msg, S)               -> ?INF("Unk msg:", Msg), {noreply, S, 0}.
%% casts
handle_cast({pack, P}, S)         -> pack_(S, P);
handle_cast(_Req, S)              -> ?INF("Unknown cast", _Req), {noreply, S, 0}.
%% calls                           
handle_call(_Req, _From, S)       -> {reply, ?e(unknown_command), S, 0}.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%
pack_(S = #{pack := Pack}, AddPack) -> 
  NewPack = lists:append(Pack, AddPack),
  {noreply, S#{pack := NewPack}, 0}.


%
timeout_(S = #{pack := [], qp_pid := QPPid, until := U, count := Count, idle := Timeout}) ->
  %% If conn work too long or manage too many requests, close it
  case stop_or_not(Count, U) of
    true  -> gen_server:cast(QPPid, {stp, self()}), {stop, normal, S};
    false -> {noreply, S, Timeout}
  end;


%
timeout_(S = #{pack := Pack, qp_pid := QPPid, conn := C, count := Count, until := U, idle := Timeout}) ->
  %% Do pack and send answers to QPPid
  SendFun = fun
    (Fu, [{From, {Req, Params}}|RestPack], AnswerAcc) ->
        Answer = catch epgsql:equery(C, Req, Params),
        Fu(Fu, RestPack, [{From, Answer}|AnswerAcc]);
    (Fu, [{From, Req}|RestPack], AnswerAcc) ->
        Answer = catch epgsql:squery(C, Req),
        Fu(Fu, RestPack, [{From, Answer}|AnswerAcc]);
    (_F, [], AnswerAcc) -> 
        NewCount = Count + length(AnswerAcc),
        case stop_or_not(NewCount, U) of
          false -> gen_server:cast(QPPid, {ans_ret, self(), lists:reverse(AnswerAcc)}), {ans_ret, NewCount};
          true  -> gen_server:cast(QPPid, {ans_stp, self(), lists:reverse(AnswerAcc)}),  ans_stp
        end
  end,
  case SendFun(SendFun, Pack, []) of
    {ans_ret, NewCount} -> {noreply, S#{pack := [], count := NewCount}, Timeout};
    ans_stp             -> {stop, normal, S#{pack := []}}
  end.

stop_or_not(Count, Until) ->
  (?now - Until > 0) or (Count > 100000).

