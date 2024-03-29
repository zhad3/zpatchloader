module test;

unittest
{
    import std.conv : to;
    import iniparser;

    auto servers = parseServerConfigs("test/servers.test.conf");

    assert(servers.length == 3);

    assert(servers[0].name == "server-0");
    assert(servers[0].patchConfig.host == "foobar");
    assert(servers[0].patchConfig.path == "/path");
    assert(servers[0].patchConfig.infoFile == "/info/patch.txt");

    assert(servers[1].name == "server-1");
    assert(servers[1].patchConfig.host == "overwrite");
    assert(servers[1].patchConfig.path == "/original");

    assert(servers[2].name == "server-2");
}

unittest
{
    import iniparser;

    auto patchInfo = parseLocalPatchInfo("test/localpatchinfo.test.conf");

    assert(patchInfo.etag == "EAF024");
    assert(patchInfo.lastModified == string.init);
    assert(patchInfo.failedPatches.length == 2);

    assert(patchInfo.failedPatches[124].patchId == 124);
    assert(patchInfo.failedPatches[124].retries == 0);
    assert(patchInfo.failedPatches[124].filename == "filename");
    assert(patchInfo.failedPatches[555].patchId == 555);
    assert(patchInfo.failedPatches[555].retries == 2);
    assert(patchInfo.failedPatches[555].filename == "name");
}

