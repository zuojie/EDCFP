-module(factorial).
-export([fact/1]).
fact(0) -> 1;
fact(N) when N < 0 -> io:format("参数错误~n");
fact(N) when N > 0 -> N * fact(N - 1).
