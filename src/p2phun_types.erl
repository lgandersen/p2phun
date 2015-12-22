-module(p2phun_types).

-type id() :: non_neg_integer().
-type table() :: ets:tid() | atom().

-export_type([id/0, table/0]).
