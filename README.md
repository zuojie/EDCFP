# EDCFP

## Erlang Distributed Compute Framework Prototype    
____ 

选择erlang，多半是因为它便捷的分布式处理方式（当然，是针对其他fp语言）。现在笔者就利用erlang，来鼓捣一个实现了map-reduce思想的简易分布式计算框架。   

本文假设你了解erlang；  
本文假设你了解一些map-reduce的知识；   
本文着重介绍erlang分布式架构的搭建过程，代码细节不详细讨论   


首先介绍背景， erlang中有一个lists模块，其中包含一些群众喜闻乐见的方法，比如append，concat，delete等，还有一些不常见但是很有用的方法，比如all，any，foreach等。我们要说的是其中的map方法，erlang手册中这么介绍map：
map(Fun, List1) -> List2   

> Types:   
```erlang
Fun = fun((A) -> B) 
List1 = [A]  
List2 = [B]   
A = B = term()
```
Takes a function from As to Bs, and a list of As and produces a list of Bs by applying the function to every element in the list. This function is used to obtain the return values. The evaluation order is implementation dependent.   


简言之就是：lists:map(fun, List)函数返回List中的元素经过fun作用后的结果列表。   


试想如果我们把map放进erlang强大的spawn（用于产生“erlang进程”的方法）方法中，那就瞬间实现了分布式。于是erlang祖师爷Joe Armstrong 就开发了一个并行版的map：pmap（parallel map），实现过程套用了map-reduce思想。代码如下：   
```erlang
pmap(F, L) ->   
	S = self(),     
	Pids = lists:map(fun(I) ->   
	spawn(fun() -> do_f(S, F, I) end)   
	end, L),   
gather(Pids).   
gather([H|T]) ->   
receive   
{H, Ret} -> [Ret|gather(T)]   
end;   
gather([]) ->   
[].   
do_f(Parent, F, I) ->   
Parent ! {self(), (catch F(I))}.
```


简单，大方。   


其实这还只是简单实现了map-reduce思想，并没有真正的实现分布式。不过既然分布式最核心的东西实现了，搭一套分布式的框框还不是手到擒来。


* step 1：  
     准备2台机器，笔者采用虚拟机 + 主机的方式来进行分布式的模拟。   
虚拟机环境：Ubuntu，IP：192.168.225.132 主机名：hadoop 角色：slave   
主机环境：window7，IP：192.168.119.1 主机名：arvinpeng-PC2 角色：master + slave   
然后分别安装erlang环境（windows直接下载二进制安装文件，Linux的请搜教程，我[FYI](http://cryolite.iteye.com/blog/356419)一个），然后更改两台机器的host文件，Ubuntu的hosts文件增加一行：192.168.119.1 arvinpeng-PC2
windows 7的hosts文件增加一行：192.168.225.132 hadoop，然后互ping保证通畅即可。注意，如果是虚拟机，每次重启ip会发生变化。   


* step 2：   
     hadoop中运行task的机器称为节点，erlang的分布式系统也采用节点的称呼。不同的erlang节点怎么和master秘密接头呢？通过一个cookie文件，这是不同的节点互相识别的暗号。文件名固定：.erlang.cookie，文件内容随意，但必须都是小写字符，因为erlang中小写字符表示常量。可在master机器上建立.erlang.cookie文件，然后输入：test_erlang_mapred，将其放在HOME目录（以笔者为例，windows的在：C:\Users\arvinpeng， Linux的在：/usr/local/lib/erlang），并分别将其拷贝到其他slave机器上的HOME目录。注意，erlang的安全机制要求linux目录上的.erlang.cookie文件最好运行chmod 400命令，保证只有运行erlang的所属用户可读，任何用户不可写。   

* step 3：    
      准备工作差不多了，开始编写代码。master机器的代码如下：   
`-module(pmap).`   
`-export([start/4, map/2]).`   

`map(Func, List) ->`    
	`Pid = self(),`   
	`MasterRes = lists:map(fun(I) -> spawn(fun() -> do_work(Pid, Func, I) end) end, List),`   
	`io:format("master free~n"),`   
	`receive`   
		`{finished, SlaveRes} ->`    
			`Res = lists:append(MasterRes, SlaveRes)`   
	`end,`   
	`R = reduced(Res),`   
	`lists:foreach(fun(X) -> print(X) end, R).`   

`reduced([H|T]) ->`   
	`receive`   
		`{H, Res} ->`    
			`[Res|reduced(T)]`   
	`end;`   
`reduced([]) ->`   
	`[].`   

`print(Element) ->`    
	`io:format("~w~n", [Element]).`   
	
`do_work(Parent, Func, I) ->`   
	`Parent ! {self(), (catch Func(I))}.`   
	
`start(SlaveNode, Func, List1, List2) ->`   
	`register(master, spawn(pmap, map, [Func, List1])),`   
	`spawn(SlaveNode, pmap, map, [Func, List2, master, node()]). %% 将master的节点名称传递过去`   


其中，核心部分借鉴了pmap的实现。   
slave节点上代码如下：   
      `1 -module(pmap).`   
      `2 -export([map/4]).`   
      `3`    
      `4 map(Func, List, MasterName, MasterNode) ->`   
      `5         Res = lists:map(fun(I) -> spawn(fun() -> do_work(MasterName, MasterNode, Func, I) end) end, List),`   
      `6         io:format("slave free~n"),`   
      `7         {MasterName, MasterNode} ! {finished, Res}.`   
      `8`    
      `9 do_work(MasterName, MasterNode, Func, I) ->`   
      `10         {MasterName, MasterNode} ! {self(), (catch Func(I))}.`   

master和slave通过消息进行交互，通过节点名 + 进程名/进程ID进行互相识别，辅以.erlang.cookie完成安全认证。这就大体解决了分布式系统通信的问题。       

* step 4：   
      环境和代码都就位了，现在看下编译运行的过程，首先分别编译之：   
master   
![p1](http://zuojie.github.io/demo/edcfp_p1.png)   
         
首先用-sname参数指定erl节点名称：master，启动后master@arvinpeng-PC2就是master被其他slave初步找到的依据（还要配合进程相关的信息才能准确发现master进程）。
然后在Ubuntu上进行相似的过程：   
slave   
![p2](http://zuojie.github.io/demo/edcfp_p2.png)   
         
* step 5:   
       编写用户函数，这里以一个求阶乘的用户函数为例，代码如下：   
`-module(factorial).`   
`-export([fact/1]).`   

`fact(0) -> 1;`   
`fact(N) when N < 0 -> io:format("参数错误~n");`  
`fact(N) when N > 0 -> N * fact(N - 1).`   
同理，分别将factorial.erl放到master和slave的HOME目录，然后编译确保运行顺畅，正常。   


* step 6：   
      运行起这个简陋的分布式系统，如图所示   
![p3](http://zuojie.github.io/demo/edcfp_p3.png)   

在master上启动master的函数时，把slave节点位置传递了进去。   
红框中的提示表示master节点和slave节点计算完毕。从slave节点中进行标准输出只会在master的标准输出设备上显示。   
示例代码完成的功能是：   
将2个列表（你可以认为是一个大列表拆分成的2个列表）分别部署到2台机器上分别进行阶乘（map）计算，计算完毕之后汇总（reduced）到master机器上重新组合成一个list。   
