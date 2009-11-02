%% Author: Peter
%% Created: Apr 2, 2009
%% Description: TODO: Add description to test
-module(test).

%%
%% Include files
%%

-include("packet.hrl").

%%
%% Exported Functions
%%
-export([run/0]).

%%
%% API Functions
%%

run() ->
    spawn(fun() -> connect() end).

connect() ->
    {ok,Socket} = gen_tcp:connect("localhost",2345,[binary,{active, true},{nodelay, true}, {keepalive, true}, {packet,0}]),
    t:start(Socket), 
    t:login(),   

    loop(Socket).

%%
%% Local Functions
%%

loop(Socket) ->
    receive
        {tcp, Socket, Bin} ->			
            case packet:read(Bin) of
                #player_id{id = PlayerId} ->
                    io:fwrite("PlayerId: ~w~n", [PlayerId]),		
                    ok = gen_tcp:send(Socket, <<?CMD_CLIENTREADY>>),
                    loop(Socket);
                #map{tiles = Tiles } ->
                    io:fwrite("Tiles: ~w~n", [Tiles]),
                    loop(Socket);
                #perception{entities = Entities, tiles = Tiles} ->
                    io:fwrite("Perception: ~w ~w~n",[Entities, Tiles]),
                    loop(Socket);                
                _Any ->
                    io:fwrite("Do not recognize command.~n")
            end;							
        {error, closed} ->
            io:fwrite("Connection closed.");
        _Any ->
            io:fwrite("Epic failure.")
    end.
