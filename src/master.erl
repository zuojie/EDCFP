-module(pmap).
-export([start/4, map/2]).

map(Func, List) ->
	Pid = self(),
	MasterRes = lists:map(fun(I) -> spawn(fun() -> do_work(Pid, Func, I) end) end, List),
	io:format("master free~n"),
	receive
		{finished, SlaveRes} ->
			Res = lists:append(MasterRes, SlaveRes)
	end,
	R = reduced(Res),
	lists:foreach(fun(X) -> print(X) end, R).

reduced([H|T]) ->
	receive
		{H, Res} ->
			[Res|reduced(T)]
	end;
reduced([]) ->
	[].

print(Element) ->
	io:format("~w~n", [Element]).

do_work(Parent, Func, I) ->
	Parent ! {self(), (catch Func(I))}.

start(SlaveNode, Func, List1, List2) ->
	register(master, spawn(pmap, map, [Func, List1])),
	spawn(SlaveNode, pmap, map, [Func, List2, master, node()]). %% 将master的节点名称传递过去
