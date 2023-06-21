eqp
=====

Erlang Queue Pool
App for pretty good control data flows tru database connectoins.


Usage
-----

    1> eqp:create().
    2> eqp:stat().
    3> eqp:req().
    4> eqp:delete().

Example
-------

```
test\_connect(1) ->
  % {ok, C} = epgsql:connect("localhost", "dbuser", "dbpwd", [{database, "dbname"}, {timeout, 4000}]),
  % ...
  % ok = epgsql:close(C).
  %
  QPName = test_qp,
  MFA1   = {epgsql, connect, ["localhost", "dbuser", "dbuser", [{database, "dbname"}, {timeout, 4000}]]},
  MFA2   = {epgsql, close, []},
  Args   = #{
      start => MFA1,
      stop  => MFA2},
  eqp:create(QPName, Args);

test_request(2) ->
  QPName = test_qp,
  eqp:req(QPName, "select * from pg_table");

t(3) ->
  QPName = test_qp,
  eqp:delete(QPName).
```
