module serveriniparser;

import config : PatchServerConfig;
import patchserver : PatchServer;

PatchServer[] parseServerConfigs(const string filename)
{
    import std.stdio : File;
    import std.exception : ErrnoException;

    PatchServer[] servers;

    File serverFile;
    try
    {
        serverFile = File(filename, "r");
    }
    catch (ErrnoException e)
    {
        import std.stdio : writeln;
        writeln(e.message);
        return [];
    }

    scope(exit)
        serverFile.close();

    bool[string] identifierMap;
    PatchServerConfig[string] serverConfigMap;
    PatchServerConfig* currentPatchServerConfig = null;
    string[] orderedConfigs;

    foreach (memberName; __traits(allMembers, PatchServerConfig))
    {
        identifierMap[memberName] = true;
    }

    foreach (line; serverFile.byLine())
    {
        import std.algorithm : splitter, each, findSplit;
        import std.array : empty;

        if (line.empty || line[0] == ';')
        {
            continue;
        }

        if (line.length > 2 && line[0] == '[' && line[$ - 1] == ']')
        {
            auto section = line[1 .. $ - 1];
            if (!(section in serverConfigMap))
            {
                serverConfigMap[cast(string) section.dup] = PatchServerConfig.init;
                orderedConfigs ~= section.dup;
            }
            currentPatchServerConfig = &serverConfigMap[section];
        }

        if (currentPatchServerConfig is null)
        {
            continue;
        }

        if (auto splitted = line.findSplit("="))
        {
            if (cast(const string) splitted[0] in identifierMap)
            {
                const key = splitted[0];
                const value = splitted[2];

                import std.conv : to;

setter_switch: final switch (key)
                {
                static foreach (memberName; __traits(allMembers, PatchServerConfig))
                {
                    case memberName:
                        __traits(getMember, currentPatchServerConfig, memberName) = value.to!(typeof(__traits(getMember, currentPatchServerConfig, memberName)));
                        break setter_switch;
                }
                }
            }
        }
    }

    foreach (section; orderedConfigs)
    {
        auto config = serverConfigMap[section];
        servers ~= new PatchServer(config, section);
    }

    return servers;
}

