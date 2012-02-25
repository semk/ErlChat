%% A distributed Message Store using Mnesia that stores
%% the offline chat messages

-module(message_store).

-compile(export_all).

-include_lib("stdlib/include/qlc.hrl").

-define(SERVER, message_store).

-record(chat_message,
	{addressee,
	 body,
	 created_on}).

start() ->
    server_util:start(?SERVER, {message_store, run, [true]}).

stop() ->
    server_util:stop(?SERVER).

save_message(Addressee, MessageBody) ->
    global:send(?SERVER, {save_msg, Addressee, MessageBody}).

find_messages(Addressee) ->
    global:send(?SERVER, {find_msg, Addressee, self()}),
    receive
	{ok, Messages} ->
	    Messages
    end.

run(FirstTime) ->
    if
	FirstTime == true ->
	    init_store(),
	    run(false);
	true ->
	    receive
		{save_msg, Addressee, MessageBody} ->
		    store_message(Addressee, MessageBody),
		    run(FirstTime);
		{find_msg, Addressee, Pid} ->
		    Messages = get_messages(Addressee),
		    Pid ! {ok, Messages},
		    run(FirstTime);
		shutdown ->
		    mnesia:stop(),
		    io:format("Sutting down....~n")
	    end
    end.

delete_messages(Messages) ->
    F = fun() ->
		lists:foreach(fun(Msg) -> mnesia:delete_object(Msg) end, Messages)
	end,
    mnesia:transaction(F).

get_messages(Addressee) ->
    F = fun() ->
		Query = qlc:q([M#chat_message.body || M <- mnesia:table(chat_message), 
						      M#chat_message.addressee =:= Addressee]),
		Results = qlc:e(Query),
		delete_messages(Results),
		Results
	end,
    {atomic, Messages} = mnesia:transaction(F),
    Messages.

store_message(Addressee, MessageBody) ->
    F = fun() ->
		{_, CreatedOn, _} = erlang:now(),
		mnesia:write(#chat_message{addressee=Addressee, body=MessageBody, created_on=CreatedOn})
	end,
    mnesia:transaction(F).

init_store() ->
    mnesia:create_schema([node()]),
    mnesia:start(),
    try
	mnesia:table_info(chat_message, type)
    catch
	exit: _ ->
	    mnesia:create_table(chat_message, [{attributes, record_info(fields, chat_message)},
					      {type, bag},
					      {disc_copies, [node()]}])
    end.
