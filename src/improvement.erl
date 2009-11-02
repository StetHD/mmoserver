%%% -------------------------------------------------------------------
%%% Author  : Peter
%%% Description : Improvements Process
%%%
%%% Created : Oct 3, 2009
%%% -------------------------------------------------------------------
-module(improvement).

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

-include("common.hrl").
-include("game.hrl").
-include("schema.hrl").

%% --------------------------------------------------------------------
%% External exports
-export([start/0, create/6]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(module_data, {}).
%% ====================================================================
%% External functions
%% ====================================================================

start() ->
    gen_server:start({global, improve_pid}, improvement, [], []).

create(ImprovementId, X, Y, PlayerId, CityId, Type) ->
    gen_server:cast(global:whereis_name(improve_pid), {'BUILD_IMPROVEMENT', ImprovementId, X, Y, PlayerId, CityId, Type}).

%% ====================================================================
%% Server functions
%% ====================================================================

init([]) ->
    Data = #module_data {},
    {ok, Data}.

handle_cast({'BUILD_IMPROVEMENT', ImprovementId, X, Y, PlayerId, CityId, Type}, Data) ->
    
    TileIndex = map:convert_coords(X, Y),
    Improvement = #improvement{id = ImprovementId,
                               tile_index = TileIndex,
                               player_id = PlayerId, 
                               city_id = CityId,
                               type = Type,                                
                               state = ?STATE_CONSTRUCTING,
                               observed_by = []},
    
    io:fwrite("Improvement: ~w~n", [Improvement]), 
    db:dirty_write(Improvement),
    
    %% Add completion event 
    game:add_event(self(), ?EVENT_IMPROVEMENT_COMPLETED, ImprovementId, 10),
    
    {noreply, Data};

handle_cast({'ADD_VISIBLE', _ImprovementId, _EntityId, _EntityPid}, Data) ->    
    %Do nothing atm 
    %[Improvement] = db:dirty_read(improvement, ImprovementId),
    {noreply, Data};

handle_cast({'REMOVE_VISIBLE', _ImprovementId, _EntityId, _EntityPid}, Data) ->
    %Do nothing atm	
    {noreply, Data};

handle_cast({'ADD_OBSERVED_BY', ImprovementId, EntityId, EntityPid}, Data) ->    
    
    EntityType = gen_server:call(EntityPid, {'GET_TYPE'}),
        
    case EntityType of
        ?OBJECT_ARMY ->
            add_observed_by(ImprovementId, EntityId, EntityPid);
        ?OBJECT_CITY ->
            add_observed_by(ImprovementId, EntityId, EntityPid)
    end, 

    {noreply, Data};

handle_cast({'REMOVE_OBSERVED_BY', ImprovementId, EntityId, EntityPid}, Data) ->    
    
    remove_observed_by(ImprovementId, EntityId, EntityPid),
    
    {noreply, Data};

handle_cast({'PROCESS_EVENT', ImprovementId, EventType}, Data) ->
    
    case EventType of
        ?EVENT_IMPROVEMENT_COMPLETED ->  
            [Improvement] = db:dirty_read(improvement, ImprovementId),
            state_completed(Improvement),
            update_observers(Improvement)
    end,      
    
    {noreply, Data};

handle_cast(stop, Data) ->
    {stop, normal, Data}.

handle_call('GET_IMPROVEMENTS', _From, Data) ->
    
    [Improvements] = db:dirty_read(improvement),
    
    F = fun(Improvement, Rest) ->
                [{Improvement#improvement.id, self()} | Rest]
        end,
    
    ImprovementsIdPid = lists:foldr(F, [], Improvements),
    
    {reply, ImprovementsIdPid, Data};

handle_call({'GET_STATE', ImprovementId}, _From, Data) ->
    
    [Improvement] = db:dirty_read(improvement, ImprovementId),
    
    case db:dirty_read(improvement, ImprovementId) of
        [Improvement] ->
            {TileX, TileY} = map:convert_coords(Improvement#improvement.tile_index),			
            State = #state {id = ImprovementId,
                            player_id = Improvement#improvement.player_id,
                            type = ?OBJECT_IMPROVEMENT,
                            state = Improvement#improvement.state,
                            x = TileX,
                            y = TileY};			
        _ ->
            State = #state {id = ImprovementId,
                            player_id = none,
                            type = ?OBJECT_IMPROVEMENT,
                            state = ?STATE_DEAD,
                            x = 10000000,
                            y = 10000000}
    end,
    
    {reply, State, Data};


handle_call(Event, From, Data) ->
    error_logger:info_report([{module, ?MODULE}, 
                              {line, ?LINE},
                              {self, self()}, 
                              {message, Event}, 
                              {from, From}
                             ]),
    {noreply, Data}.

handle_info(Info, Data) ->
    error_logger:info_report([{module, ?MODULE}, 
                              {line, ?LINE},
                              {self, self()}, 
                              {message, Info}]),
    {noreply, Data}.

code_change(_OldVsn, Data, _Extra) ->
    {ok, Data}.

terminate(_Reason, _) ->
    ok.

%% ====================================================================
%% Internal functions
%% ====================================================================

state_completed(Improvement) ->
    log4erl:info("Improvement completed"),
    NewImprovement = Improvement#improvement{state = ?STATE_COMPLETED},
    db:dirty_write(NewImprovement).

update_observers(Improvement) ->
    ObservedByList = Improvement#improvement.observed_by, 
    
    F = fun({_EntityId, EntityPid}) ->                
                PlayerId = gen_server:call(EntityPid, {'GET_PLAYER_ID'}),                
                game:update_perception(PlayerId)
        end,  
    
    lists:foreach(F, ObservedByList).

add_observed_by(ImprovementId, EntityId, EntityPid) ->
    [Improvement] = db:dirty_read(improvement, ImprovementId),
    NewObservedByList = [{EntityId, EntityPid} | Improvement#improvement.observed_by],
    NewImprovement = Improvement#improvement { observed_by = NewObservedByList},
    db:dirty_write(NewImprovement).

remove_observed_by(ImprovementId, EntityId, EntityPid) ->
    [Improvement] = db:dirty_read(improvement, ImprovementId),
    NewObservedByList = lists:delete({EntityId, EntityPid}, Improvement#improvement.observed_by),
    NewImprovement = Improvement#improvement { observed_by = NewObservedByList},
    db:dirty_write(NewImprovement).                                  

%% check_queue(Improvement) ->
%%     [ImprovementQueue] = db:dirty_read(improvement_queue, Improvement#improvement.id),
%%     
%%     CurrentTime = util:get_time_seconds(),
%%     
%%     if
%%         ImprovementQueue#improvement_queue.end_time =< CurrentTime ->
%%             log4erl:info("Improvement Complete"),
%%             
%%             NewImprovement = Improvement#improvement {state = ?STATE_COMPLETE},			
%%             db:dirty_delete(improvement_queue, Improvement#improvement.id),
%%             db:dirty_write(NewImprovement);
%%         true ->
%%             ok
%%     end.

