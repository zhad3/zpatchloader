module config;

import zconfig;

struct Config
{
    @Section("ragnarok")
    {
        @Desc("Patch server of Ragnarok.")
        string patchHost = "ropatch.gnjoy.com";
        @Desc("Patch info path of Ragnarok.")
        string patchInfoPath = "/PatchInfo";
        @Desc("Patch path of Ragnarok.")
        string patchPath = "/Patch";
        @Desc("Patch info file.")
        string patchInfoFile = "patch2.txt";
    }

    @Section("ragnarokRE")
    {
        @Desc("Patch server of Ragnarok Renewal.")
        string patchHostRE = "ropatch.gnjoy.com";
        @Desc("Patch info path of Ragnarok Renewal.")
        string patchInfoPathRE = "/PatchInfo";
        @Desc("Patch path of Ragnarok Renewal.")
        string patchPathRE = "/Patch";
        @Desc("Patch info file.")
        string patchInfoFileRE = "patchRE2.txt";
    }
}

