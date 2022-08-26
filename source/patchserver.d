module patchserver;

import config : PatchServerConfig, LocalPatchInfo, getConfig;
import requests;

class PatchServer
{
    immutable PatchServerConfig patchConfig;
    immutable string name;
    LocalPatchInfo localPatchInfo;

    this(immutable PatchServerConfig patchConfig, immutable string patchServerName)
    {
        this.patchConfig = patchConfig;
        this.name = patchServerName;
    }

    void checkUpdates()
    {

    }

    void loadLocalPatchInfo()
    {
        import std.path : buildPath;

        immutable filename = buildPath(getConfig().localPatchInfoDirectory, name) ~ ".conf";

        import iniparser : parseLocalPatchInfo;

        localPatchInfo = parseLocalPatchInfo(filename);

    }

}

