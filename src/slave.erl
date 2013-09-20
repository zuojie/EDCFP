-module(pmap).
-export([map/4]).

map(Func, List, MasterName, MasterNode) ->
	Res = lists:map(fun(I) -> spawn(fun() -> do_work(MasterName, MasterNode, Func, I) end) end, List),
	io:format("slave free~n"),
	{MasterName, MasterNode} ! {finished, Res}.

do_work(MasterName, MasterNode, Func, I) ->
	{MasterName, MasterNode} ! {self(), (catch Func(I))}.
