
%% IF
-define(IF(Cond, TrueVal, FalseVal), case Cond of true -> TrueVal; false -> FalseVal end).

%% Point
-define(p,         list_to_binary(io_lib:format("Mod:~w line:~w", [?MODULE,?LINE]))).
-define(p(Reason), list_to_binary(io_lib:format("Mod:~w line:~w ~100P", [?MODULE,?LINE, Reason, 300]))).

%% Error
-define(e(ErrCode), {err, {ErrCode, ?p}}).
-define(e(ErrCode, Reason), {err, {ErrCode, ?p(Reason)}}).

%% Logs
-define(stime, eqp_dh_date:format("Y-m-d H:i:s",{date(),time()})).
-define(INF(Str, Term), io:format("~p EQP: ~p:~p ~p ~100P~n", [?stime, ?MODULE, ?LINE, Str, Term, 300])).

% NOW time in seconds & milliseconds
-define(now,  erlang:system_time(second)).
-define(mnow, erlang:system_time(millisecond)).
