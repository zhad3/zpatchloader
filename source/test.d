module test;

unittest
{
    import std.conv : to;
    import serveriniparser;

    auto servers = parseServerConfigs("test/servers.test.conf");

    assert(servers.length == 3);

    assert(servers[0].name == "server-0");
    assert(servers[0].config.host == "foobar");
    assert(servers[0].config.infoPath == "/info", servers[0].config.infoPath);
    assert(servers[0].config.path == "/path");
    assert(servers[0].config.infoFile == "patch.txt");

    assert(servers[1].name == "server-1");
    assert(servers[1].config.host == "overwrite");
    assert(servers[1].config.infoPath == "/original");

    assert(servers[2].name == "server-2");
}

