-module(world_socket_controller).
-behavior(gen_server).

-record(state, {
	account_id,
  sess_key,
  parent_pid,
  send_pid,
	values
							 }).


-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).
-export([send/1]).
-compile([export_all]).


-include("include/binary.hrl").

send(Msg) ->
	routeData(self(), Msg).



start_link(ParentPid) ->
	gen_server:start_link(?MODULE, {ParentPid}, []).

init({ParentPid}) ->
	io:format("controller SERVER: started~n"),
	gen_server:cast(self(), init),
	{ok, #state{parent_pid=ParentPid}}.


%% receiver has accepted connection
%% start send process
handle_call({tcp_accept_socket, Socket, AccountId, KeyState}, _From, S = #state{parent_pid=ParentPid}) ->
	SendSupPid = get_sibling_pid(ParentPid, world_socket_send_sup),
	{ok, SendPid} = supervisor:start_child(SendSupPid, [Socket, KeyState]),
	{reply, ok, S#state{send_pid=SendPid, account_id=AccountId}};
handle_call(_E, _From, State) ->
	{reply, ok, State}.

%% initialize controller
%% start rcv process
handle_cast(init, State = #state{parent_pid=ParentPid}) ->
	RcvSupPid = get_sibling_pid(ParentPid, world_socket_rcv_sup),
	supervisor:start_child(RcvSupPid, [self()]),
	TotalCount = update_fields:fields('PLAYER_END'),
	Values = binary:copy(<<0?L>>, TotalCount),
	{noreply, State#state{values=Values}};
handle_cast({tcp_accept_challenge, Msg}, State) ->
	routeData(self(), Msg),
	{noreply, State};
handle_cast({tcp_packet_rcvd, <<Opcode?LB, Payload/binary>>}, S = #state{account_id=AccountId, values=Values}) ->
	%io:format("looking up opcode ~p~n", [Opcode]),
	{M, F} = opcode_patterns:getCallbackByNum(Opcode),
	Args = [{payload, Payload}, {account_id, AccountId}, {controller_pid, self()}, {values, Values}],
	NewValues = try M:F(Args) of
		ok -> Values;
		{Result} ->
			proplists:get_value(values, Result, Values)
		catch
			badarg -> Values
		end,
	{noreply, S#state{values=NewValues}};
handle_cast({send_to_client, Msg}, S=#state{send_pid = SendPid}) ->
	gen_fsm:send_event(SendPid, {send, Msg}),
	{noreply, S};
handle_cast(Msg, S) ->
	io:format("unknown casted message: ~p~n", [Msg]),
	{noreply, S}.

handle_info(upgrade, State) ->
	%% loads latest code
	?MODULE:handle_info(do_upgrade, State),
	{noreply, State};
handle_info(Msg, State) ->
	io:format("unknown message: ~p~n", [Msg]),
	{noreply, State}.


code_change(_OldVsn, State, _Extra) ->
	io:format("code change~n"),
	{ok, State}.

terminate(normal, _State) ->
	ok;
terminate(_Reason, _State) ->
	ok.


%% private

get_sibling_pid(ParentPid, SiblingId) ->
	ChildList = supervisor:which_children(ParentPid),
	[{_, Pid, _, _}] = lists:filter(fun({Id, _Child, _Type, _Modules}) ->
		Id == SiblingId
	end, ChildList),
	Pid.



%% takes a list of pids and a formatted message
%% routes the message to the pids
routeData([], _) -> ok;
routeData([Pid|Rest], Msg) ->
	routeData(Pid, Msg),
	routeData(Rest, Msg);
routeData(Pid, Msg) when erlang:is_pid(Pid) ->
	gen_server:cast(Pid, {send_to_client, Msg}).

