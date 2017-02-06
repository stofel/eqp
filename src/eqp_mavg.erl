%%%----------------------------------------------------------------------
%%% File    : eqp_mavg.erl
%%% Author  : Aleksey S. Kluchnikov <alexs@ximad.com>
%%% Purpose : Moving average calculation
%%% Created : 01 Feb 2016
%%%----------------------------------------------------------------------

-module(eqp_mavg).

-export([new/0, event/1, event/2, rate/1, rate/2]).

-include("../include/eqp.hrl").

%
new() -> 
  new(#{}).
new(MA) ->
  SmoothingWindow = maps:get(<<"period">>, MA, 60),
  Avg             = maps:get(<<"avg">>,    MA, 0),

  #{<<"avg">>     => Avg,
    <<"period">>  => SmoothingWindow,
    <<"last">>    => ?now,
    <<"log">>     => 0}.


%
event(MA) -> 
  event(MA, 1).

%
event(MA = #{<<"avg">>    := Avg,
             <<"period">> := Period,
             <<"last">>   := Last,
             <<"log">>    := Log}, Count) ->
  Now = ?now,
  case Now - Last of
    Elapsed when Elapsed == 0 ->
      MA#{<<"log">> := Log + Count};
    Elapsed when Elapsed > 0 andalso Elapsed < Period * 8 ->
      Cur = (Avg - Log) * math:exp(-1/Period) + Log,
      NewAvg = Cur * math:exp((1-Elapsed)/Period),
      MA#{<<"avg">> := NewAvg, <<"last">> := Now, <<"log">> := Count};
    _Elapsed ->
      MA#{<<"avg">> := 0, <<"last">> := Now, <<"log">> := Count}
  end.

%
rate(MA) -> #{<<"avg">> := Avg} = event(MA, 0), Avg.

%
rate(MA, PerPeriod) -> PerPeriod * rate(MA).

