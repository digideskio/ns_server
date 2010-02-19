% Copyright (c) 2010, NorthScale, Inc.
% All rights reserved.

-module(mc_ascii).

-include_lib("eunit/include/eunit.hrl").

-include("mc_constants.hrl").

-include("mc_entry.hrl").

-compile(export_all).

%% Functions to work with memcached ascii protocol messages.

%% @doc Send an iolist and receive a single line back.
send_recv(Sock, IoList) ->
    send_recv(Sock, IoList, undefined, undefined).

send_recv(Sock, IoList, RecvCallback, CBData) ->
    ok = send(Sock, IoList),
    {ok, Line} = recv_line(Sock),
    NCB = case is_function(RecvCallback) of
              true  -> RecvCallback(Line, undefined, CBData);
              false -> CBData
    end,
    {ok, Line, NCB}.

send({OutPid, CmdNum}, Data) ->
    OutPid ! {send, CmdNum, Data},
    ok;

send(undefined, _Data)              -> ok;
send(_Sock, undefined)              -> ok;
send(_Sock, <<>>)                   -> ok;
send(Sock, List) when is_list(List) -> send(Sock, iolist_to_binary(List));
send(Sock, Data)                    -> gen_tcp:send(Sock, Data).

%% @doc Receive binary data of specified number of bytes length.
recv_data(_, 0)           -> {ok, <<>>};
recv_data(Sock, NumBytes) -> gen_tcp:recv(Sock, NumBytes).

%% @doc Receive a binary CRNL terminated line, not including the CRNL.
recv_line(Sock) ->
    recv_line(Sock, <<>>).

recv_line(Sock, Acc) ->
    case gen_tcp:recv(Sock, 1) of
        {ok, B} ->
            Acc2 = <<Acc/binary, B/binary>>,
            {Line, Suffix} = split_binary_suffix(Acc2, 2),
            case Suffix of
                <<"\r\n">> -> {ok, Line};
                _          -> recv_line(Sock, Acc2)
            end;
        Err -> Err
    end.

%% @doc Returns the {body, suffix} binary parts for a binary;
%%      Returns {body, <<>>} if the binary is too short.
%%
split_binary_suffix(Bin, 0) -> {Bin, <<>>};
split_binary_suffix(Bin, SuffixLen) ->
    case size(Bin) >= SuffixLen of
        true  -> split_binary(Bin, size(Bin) - SuffixLen);
        false -> {Bin, <<>>}
    end.

% -------------------------------------------------

suffix_test() ->
    ?assertMatch({<<"hel">>, <<"lo">>}, split_binary_suffix(<<"hello">>, 2)),
    ?assertMatch({<<"hello">>, <<>>}, split_binary_suffix(<<"hello">>, 0)),
    ?assertMatch({<<>>, <<"lo">>}, split_binary_suffix(<<"lo">>, 2)),
    ?assertMatch({<<"o">>, <<>>}, split_binary_suffix(<<"o">>, 2)),
    ?assertMatch({<<>>, <<>>}, split_binary_suffix(<<>>, 2)),
    ?assertMatch({<<>>, <<>>}, split_binary_suffix(<<>>, 0)),
    ok.

recv_line_test() ->
    {ok, Sock} = gen_tcp:connect("localhost", 11211,
                                 [binary, {packet, 0}, {active, false}]),
    (fun () ->
        ok = gen_tcp:send(Sock, "version\r\n"),
        {ok, RB} = recv_line(Sock),
        R = binary_to_list(RB),
        ?assert(starts_with(R, "VERSION "))
    end)(),

    (fun () ->
        ok = gen_tcp:send(Sock, "not-a-command\r\n"),
        {ok, RB} = recv_line(Sock),
        ?assertMatch(RB, <<"ERROR">>)
    end)(),

    ok = gen_tcp:close(Sock).

recv_data_test() ->
    {ok, Sock} = gen_tcp:connect("localhost", 11211,
                                 [binary, {packet, 0}, {active, false}]),

    (fun () ->
        ok = gen_tcp:send(Sock, "not-a-command\r\n"),
        ExpectB = <<"ERROR\r\n">>,
        {ok, RB} = recv_data(Sock, size(ExpectB)),
        ?assertMatch(RB, ExpectB)
    end)(),

    (fun () ->
        ok = gen_tcp:send(Sock, "get not-a-key\r\n"),
        ExpectB = <<"END\r\n">>,
        {ok, RB} = recv_data(Sock, size(ExpectB)),
        ?assertMatch(RB, ExpectB)
    end)(),

    ok = gen_tcp:close(Sock).

send_recv_test() ->
    {ok, Sock} = gen_tcp:connect("localhost", 11211,
                                 [binary, {packet, 0}, {active, false}]),
    (fun () ->
        RB = send_recv(Sock, "not-a-command-srt\r\n", undefined, undefined),
        ?assertMatch(RB, {ok, <<"ERROR">>, undefined})
    end)(),
    (fun () ->
        {ok, RB, undefined} = send_recv(Sock, "get not-a-key-srt\r\n", undefined, undefined),
        ?assertMatch(RB, <<"END">>)
    end)(),
    ok = gen_tcp:close(Sock).

delete_send_recv_test() ->
    {ok, Sock} = gen_tcp:connect("localhost", 11211,
                                 [binary, {packet, 0}, {active, false}]),
    (fun () ->
        {ok, RB, undefined} = send_recv(Sock, "delete not-a-key-dsrt\r\n",
                             undefined, undefined),
        ?assertMatch(RB, <<"NOT_FOUND">>)
    end)(),
    ok = gen_tcp:close(Sock).

starts_with(S, Prefix) ->
    Prefix =:= string:substr(S, 1, string:len(Prefix)).

ends_with(S, Suffix) ->
    Suffix =:= string:substr(S, string:len(S) - string:len(Suffix) + 1,
                                string:len(Suffix)).
