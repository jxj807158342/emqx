%%--------------------------------------------------------------------
%% Copyright (c) 2020-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_mgmt_api_routes).

-include_lib("emqx/include/emqx.hrl").
-include_lib("typerefl/include/types.hrl").

%% API
-behaviour(minirest_api).

-export([ api_spec/0
        , paths/0
        , schema/1
        , fields/1
        ]).

-export([ routes/2
        , route/2
        ]).

-export([ query/4]).

-define(TOPIC_NOT_FOUND, 'TOPIC_NOT_FOUND').

-define(ROUTES_QSCHEMA, [{<<"topic">>, binary}, {<<"node">>, atom}]).


api_spec() ->
    emqx_dashboard_swagger:spec(?MODULE, #{check_schema => true, translate_body => true}).

paths() ->
    ["/routes", "/routes/:topic"].

schema("/routes") ->
    #{
        'operationId' => routes,
        get => #{
            description => <<"EMQX Topics List">>,
            parameters => [
                topic_param(query),
                node_param(),
                hoconsc:ref(emqx_dashboard_swagger, page),
                hoconsc:ref(emqx_dashboard_swagger, limit)
            ],
            responses => #{
                200 => [
                    {data, hoconsc:mk(hoconsc:array(hoconsc:ref(topic)), #{})},
                    {meta, hoconsc:mk(hoconsc:ref(meta), #{})}
                ]
            }
        }
    };
schema("/routes/:topic") ->
    #{
        'operationId' => route,
        get => #{
            description => <<"EMQX Topic List">>,
            parameters => [topic_param(path)],
            responses => #{
                200 => hoconsc:mk(hoconsc:ref(topic), #{}),
                404 =>
                    emqx_dashboard_swagger:error_codes(['TOPIC_NOT_FOUND'],<<"Topic not found">>)
            }
        }
    }.

fields(topic) ->
    [
        {topic, hoconsc:mk(binary(), #{
            desc => <<"Topic Name">>,
            required => true})},
        {node, hoconsc:mk(binary(), #{
            desc => <<"Node">>,
            required => true})}
    ];
fields(meta) ->
    emqx_dashboard_swagger:fields(page) ++
        emqx_dashboard_swagger:fields(limit) ++
        [{count, hoconsc:mk(integer(), #{example => 1})}].

%%%==============================================================================================
%% parameters trans
routes(get, #{query_string := Qs}) ->
    do_list(generate_topic(Qs)).

route(get, #{bindings := Bindings}) ->
    lookup(generate_topic(Bindings)).

%%%==============================================================================================
%% api apply
do_list(Params) ->
    Response = emqx_mgmt_api:node_query(
        node(), Params, emqx_route, ?ROUTES_QSCHEMA, {?MODULE, query}),
    emqx_mgmt_util:generate_response(Response).

lookup(#{topic := Topic}) ->
    case emqx_mgmt:lookup_routes(Topic) of
        [] ->
            {404, #{code => ?TOPIC_NOT_FOUND, message => <<"Topic not found">>}};
        [Route] ->
            {200, format(Route)}
    end.

%%%==============================================================================================
%% internal
generate_topic(Params = #{<<"topic">> := Topic}) ->
    Params#{<<"topic">> => uri_string:percent_decode(Topic)};
generate_topic(Params = #{topic := Topic}) ->
    Params#{topic => uri_string:percent_decode(Topic)};
generate_topic(Params) -> Params.

query(Tab, {Qs, _}, Continuation, Limit) ->
    Ms = qs2ms(Qs, [{{route, '_', '_'}, [], ['$_']}]),
    emqx_mgmt_api:select_table_with_count(Tab, Ms, Continuation, Limit, fun format/1).

qs2ms([], Res) -> Res;
qs2ms([{topic,'=:=', T} | Qs], [{{route, _, N}, [], ['$_']}]) ->
    qs2ms(Qs, [{{route, T, N}, [], ['$_']}]);
qs2ms([{node,'=:=', N} | Qs], [{{route, T, _}, [], ['$_']}]) ->
    qs2ms(Qs, [{{route, T, N}, [], ['$_']}]).

format(#route{topic = Topic, dest = {_, Node}}) ->
    #{topic => Topic, node => Node};
format(#route{topic = Topic, dest = Node}) ->
    #{topic => Topic, node => Node}.

topic_param(In) ->
    {
        topic, hoconsc:mk(binary(), #{
            desc => <<"Topic Name">>,
            in => In,
            required => (In == path),
            example => <<"">>
        })
    }.

node_param()->
    {
        node, hoconsc:mk(binary(), #{
            desc => <<"Node Name">>,
            in => query,
            required => false,
            example => node()
        })
    }.
