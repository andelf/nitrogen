% Nitrogen Web Framework for Erlang
% Copyright (c) 2008-2009 Rusty Klophaus
% See MIT-LICENSE for licensing information.

% This is a "simple as possible" session handler. Unfortunately,
% due to time constraints, had to leave out some great code
% contributed by Dave Peticolas that fit Nitrogen sessions
% into a gen_server. My code below is far inferior. 
% Someone please make it better! - Rusty

-module (simple_session_handler).
-include ("wf.inc").
-behaviour (session_handler).
-export ([
	init/1, 
	finish/1,
	get_value/3, 
	set_value/3, 
	clear_value/2, 
	clear_all/1
]).

-define(TIMEOUT, 20000).

init(_State) -> 
	% Check if a session exists for the user. If not, start one.
	Unique = case wf:depickle(wf:cookie("wf")) of
		undefined -> erlang:md5(term_to_binary({now(), erlang:make_ref()}));
		Other -> Other
	end,
	ok = wf:cookie("wf", wf:pickle(Unique), "/", ?TIMEOUT),
	{ok, {session, Unique}}.

finish(_State) -> 
	{ok, []}.
	
get_value(Key, DefaultValue, SessionName) -> 
	{ok, Pid} = get_session_pid(SessionName),
	Pid!{get_value, Key, self()},
	Value = receive 
		{ok, undefined} -> DefaultValue;
		{ok, Other} -> Other
	end,
	Value.
	
set_value(Key, Value, SessionName) -> 
	{ok, Pid} = get_session_pid(SessionName),
	Pid!{set_value, Key, Value, self()},
	receive ok -> ok end,	
	{ok, SessionName}.
	
clear_value(Key, SessionName) ->
	{ok, Pid} = get_session_pid(SessionName),
	Pid!{clear_value, Key, self()},
	receive ok -> ok end,	
	{ok, SessionName}.

clear_all(SessionName) -> 
	{ok, Pid} = get_session_pid(SessionName),
	Pid!{clear_all, self()},
	receive ok -> ok end,	
	{ok, SessionName}.
	
get_session_pid(SessionName) ->
	{ok, _Pid} = process_cabinet_handler:get_pid(SessionName, fun() -> session_loop([]) end).

session_loop(Session) ->
	receive
		{get_value, Key, Pid} ->
			Value = case lists:keysearch(Key, 1, Session) of
				{value, {Key, V}} -> V;
				false -> undefined
			end,
			Pid!{ok, Value},
			session_loop(Session);
			
		{set_value, Key, Value, Pid} ->
			Session1 = lists:keystore(Key, 1, Session, {Key, Value}),
			Pid!ok,
			session_loop(Session1);			
			
		{clear_value, Key, Pid} ->	
			Session1 = lists:keydelete(Key, 1, Session),
			Pid!ok,
			session_loop(Session1);
			
		{clear_all, Pid} ->
			Pid!ok,
			session_loop([])	
				
	after ?TIMEOUT -> 
			exit(timed_out)
	end.
