% Copyright (c) 2010 András Veres-Szentkirályi
%
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
%
% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
% THE SOFTWARE.

-module(main).
-compile(export_all).

-define(PORT, 7283).
-define(TIMEOUT, 500).
-define(MAXCLIENTS, 500).

main() ->
	{ok, Socket} = gen_udp:open(?PORT, [list]),
	register(hsapi_listener, self()),
	io:format("Starting up...\n"),
	mainloop(Socket, dict:new()).

unixts() ->
	{Mega, Secs, _} = now(),
	Mega * 1000000 + Secs.

ip_valid(_, TS) ->
	TS >= unixts() - ?TIMEOUT.

ip_filter(In) ->
	dict:filter(fun ip_valid/2, In).

ip_fresh(Con = {IP, Port}, PreFilter, Socket) ->
	io:format("HELO from ~p\n", [Con]),
	In = ip_filter(PreFilter),
	{Msg, List} = case dict:size(In) == ?MAXCLIENTS
		andalso dict:find(Con, In) == error of
		true ->
			{"500 Too many clients\n", In};
		false ->
			{"200 OK\n", dict:store(Con, unixts(), In)}
	end,
	gen_udp:send(Socket, IP, Port, Msg),
	List.

ip_del(Con, In) ->
	io:format("STOP from ~p\n", [Con]),
	dict:erase(Con, In).

notify_client({IP, Port}, _, Socket) ->
	gen_udp:send(Socket, IP, Port, "100 State changed\n"),
	Socket.

mainloop(Socket, Notify) ->
	N1 = receive
		{udp, Socket, IP, Port, [$S, $T, $O, $P | _]} ->
			ip_del({IP, Port}, Notify);
		{udp, Socket, IP, Port, [$H, $E, $L, $O | _]} ->
			ip_fresh({IP, Port}, Notify, Socket);
		hsapi_kill -> quit;
		{udp, Socket, _, _, _} -> Notify;
		hsapi_changed ->
			io:format("State changed, notifying clients..."),
			dict:fold(fun notify_client/3, Socket, Notify),
			io:format(" done\n"),
			Notify
		after ?TIMEOUT * 1000 ->
			ip_filter(Notify)
	end,
	case N1 of
		quit ->
			io:format("Quitting...\n"),
			unregister(hsapi_listener),
			gen_udp:close(Socket);
		_ -> ?MODULE:mainloop(Socket, N1)
	end.
