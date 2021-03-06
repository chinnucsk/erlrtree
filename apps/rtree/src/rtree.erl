-module(rtree).

-include("rtree.hrl").

-export([
    create_ets/1,
    load_to_ets/2,
    tree_from_ets/1,
    intersects/3
    ]).

%%% ----------------------------------------------------------------------------
%%% @doc Create ETS Table to hold elements for the RTree
%%% @spec create_ets(Table::atom) 
%%%     -> atom(ok, Table) || {atom(error), Reason::string()}
%%% @end
%%% ----------------------------------------------------------------------------
create_ets(Table) ->
    case ets:info(Table) of
        undefined -> ets:new(Table, [set, public, named_table,
            {keypos, 5}, %% first 4 values are header,srid,geos,wkb
            {read_concurrency, true}]),
            {ok, Table};
        _ -> {error,  "ETS table already exists"}
    end.

%%% ----------------------------------------------------------------------------
%%% @doc Load File into an rtree ETS named Name to be used by rtree as a 
%%% container for the geometry objects
%%% @spec load_to_ets(Dsn, Table) -> atom(ok) || {atom(error), atom()}
%%% @end
%%% ----------------------------------------------------------------------------
load_to_ets(Dsn, Table) ->
    WkbReader = erlgeom:wkbreader_create(),
    case erlogr:open(Dsn) of
        {ok, DataSource} ->
            {ok, Layer} = erlogr:ds_get_layer(DataSource, 0),
            {ok, FeatDefn} = erlogr:l_get_layer_defn(Layer),
            Header = lists:map(fun(Field) -> list_to_atom(Field) end,
                tuple_to_list(element(2, erlogr:fd_get_fields_name(FeatDefn)))),
            {ok, Count} = erlogr:l_get_feature_count(Layer),
            Records = [feature_to_tuple(WkbReader, Header,
                element(2, erlogr:l_get_next_feature(Layer))) %% {ok, Feature}
                || _ <- lists:seq(1, Count)],
            lists:foreach(fun(R) -> ets:insert(Table, R) end, Records),
            {ok, Table};
        undefined -> {error, "Not possible to open datasource"}
    end.

%%% ----------------------------------------------------------------------------
%%% @doc Create STRtree from rtree ETS
%%% @spec tree_from_ets(File, Name) 
%%%     -> atom(ok) || {atom(error), Reason::string()}
%%% @end
%%% ----------------------------------------------------------------------------
tree_from_ets(Table) ->
    case ets:info(Table, size) of
        Size when Size > 0  ->
            Tree = erlgeom:geosstrtree_create(),
            lists:foreach(
                fun(R) -> erlgeom:geosstrtree_insert(Tree, element(3, R), R)
                end,
                ets:match_object(Table, '$1')),
            {ok, Tree};
        Size when Size == 0 ->
            {error, "Empty table"};
        _ ->
            {error, "Bad arg"}
    end.

%%% ----------------------------------------------------------------------------
%%% @doc Helper to convert Feature from Layer into a Record for the ETS
%%% @spec feature_to_record(WkbReader, Feature Header) -> record(feature)
%%% @end
%%% ----------------------------------------------------------------------------
feature_to_tuple(WkbReader, Header, Feature) ->
    {ok, Geom} = erlogr:f_get_geometry_ref(Feature),
    {ok, Wkb} = erlogr:g_export_to_wkb(Geom),
    GeosGeom = erlgeom:wkbreader_read(WkbReader, Wkb),
    FieldsA = [Header, -1, GeosGeom, Wkb], % header, srid, geom, wkb
    {ok, Fields} = erlogr:f_get_fields(Feature),
    FieldsB = tuple_to_list(Fields),
    list_to_tuple(lists:append(FieldsA, FieldsB)).

%%% ----------------------------------------------------------------------------
%%% @doc Intersects X,Y point with Tree
%%% @spec intersects(Tree, float(), float()) -> [Element]
%%% @end
%%% ----------------------------------------------------------------------------
intersects(Tree, X, Y) ->
    io:format("intersects~n"),
    Point = erlgeom:to_geom({'Point', [X, Y]}),
    io:format("before query~n"),
    Elements = erlgeom:geosstrtree_query(Tree, Point),
    io:format("before intersects~n"),
    InElements = [E || E <- Elements,
        erlgeom:intersects(element(3, E), Point) == true],
    {ok, InElements}.




