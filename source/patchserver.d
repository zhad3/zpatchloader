module patchserver;

import config : PatchServerConfig;
import requests;

struct PatchInfo
{
    string etag;
    string lastModified;
    int minPatchNumber;
    int maxPatchNumber;
}

class PatchServer
{
    immutable PatchServerConfig config;
    immutable string name;

    this(immutable PatchServerConfig config, immutable string patchServerName)
    {
        this.config = config;
        this.name = patchServerName;
    }

    void checkUpdates()
    {

    }

    void loadLocalPatchInfo()
    {

    }

}

