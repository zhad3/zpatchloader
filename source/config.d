module config;

import zconfig;

struct Config
{
    @Desc("Where to place fully downloaded patch files")
    string downloadDirectory = "downloaded";
    @Desc("Where to place info about which patch files have already been downloaded")
    string localPatchInfoDirectory = "patchinfo";
    @Desc("Where to place partial or incomplete downloaded patch files")
    string tempDirectory = "temp";
}

struct PatchServerConfig
{
    string host = "http://ropatch.gnjoy.com";
    string path = "/Patch";
    string infoPath = "/PatchInfo";
    string infoFile = "patch2.txt";
}


