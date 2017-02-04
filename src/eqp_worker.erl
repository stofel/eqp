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


init(_Args = #{qp_name := QPName, start := {M,F,A}, stop := MFA2}) ->
  ?INF("init QP worker", {M,F,A}),
  %process_flag(trap_exit, true),
  case apply(M,F,A) of
    {ok, C} ->
      S = #{qp_name => QPName,  %% QPName
            start   => {M,F,A}, %%
            stop    => MFA2,    %%
            pack    => [],      %% Pack of requests
            conn    => C,       %% Conn reference
            count   => 0,       %% Num of requests
            init    => ?now},   %% Init time
      link(erlang:whereis(QPName)),
      {ok, S};
    Else ->
      ?INF("Connect error", Else),
      Else
  end.

%
terminate(_Reason, #{qp_name := QPName, stop  := {M, F, A}, conn  := C}) ->
  ?INF("terminate worker", {QPName, self()}),
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
timeout_(S = #{pack := []}) ->
  %% If conn work too long or manage too many requests, close it
  {noreply, S, 100*1000};


%
timeout_(S = #{pack := Pack, qp_name := QPName, conn := C}) ->
  %% Do pack and send answers to QPName
  SendFun = fun
    (Fu, [{From, Req}|RestPack], AnswerAcc) ->
        Answer = epgsql:squery(C, Req),
        Fu(Fu, RestPack, [{From, Answer}|AnswerAcc]);
    (_F, [], AnswerAcc) -> 
        gen_server:cast(QPName, {ans, lists:reverse(AnswerAcc)})
  end,
  SendFun(SendFun, Pack, []),
  gen_server:cast(QPName, {ret, self()}),
  %% If conn work too long or manage too many requests, close it
  {noreply, S#{pack := []}, 100*1000}.






