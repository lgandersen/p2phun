-module(p2phun_utils_tests).

-include_lib("eunit/include/eunit.hrl").

id_conversion_test() ->
    <<"1HNeOiZe">> = p2phun_utils:bin(p2phun_utils:b64(<<"1HNeOiZe">>)),
    1337 = p2phun_utils:int(b64, p2phun_utils:b64(1337)),
    1337 = p2phun_utils:int(bin, p2phun_utils:bin(1337)).
