module config;

import zconfig;

struct Config
{
    @Desc("Config file") @ConfigFile
    string configFile;
    @Desc("Server config file")
    string serverConfigFile = "servers.conf";
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
    string infoFile = "/PatchInfo/patch2.txt";
    int downloadPoolSize = 6;
    int maxRetries = 2;
}

import std.typecons : Tuple;
alias FailedPatch = Tuple!(int, "patchId", string, "filename", int, "retries");

struct LocalPatchInfo
{
    string etag;
    string lastModified;
    int minPatchNumber;
    int maxPatchNumber;
    FailedPatch[int] failedPatches;
}


private Config globalConfig;

immutable(Config) getConfig()
{
    return globalConfig;
}

void setConfig(Config conf)
{
    if (globalConfig == Config.init)
    {
        globalConfig = conf;
    }
}

