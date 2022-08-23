module serveriniparser;

import config : PatchServerConfig;
import patchserver : PatchServer, PatchInfo;

alias IniEntryCallback = void delegate(immutable(string) section, lazy immutable(string) key, lazy immutable(string) value);

void parseIni(const string filename, IniEntryCallback callback)
{
    import std.stdio : File;
    import std.exception : ErrnoException;

    File iniFile;
    try
    {
        iniFile = File(filename, "r");
    }
    catch (ErrnoException e)
    {
        import std.stdio : writeln;
        writeln(e.message);
        return;
    }
    scope(exit)
        iniFile.close();

    string currentSection = "global";

    foreach (line; iniFile.byLine())
    {
        import std.algorithm : splitter, each, findSplit;
        import std.array : empty;

        if (line.empty || line[0] == ';')
        {
            continue;
        }

        if (line.length > 2 && line[0] == '[' && line[$ - 1] == ']')
        {
            currentSection = cast(immutable string) line[1 .. $ - 1].dup;
            continue;
        }

        if (auto splitted = line.findSplit("="))
        {
            callback(currentSection, cast(immutable string) splitted[0].dup, cast(immutable string) splitted[2].dup);
        }
        else
        {
            callback(currentSection, string.init, cast(immutable string) line.dup);
        }
    }

}


PatchServer[] parseServerConfigs(const string filename)
{
    PatchServer[] servers;

    PatchServerConfig[string] serverConfigMap;
    PatchServerConfig* currentPatchServerConfig = null;
    string[] orderedConfigs;

    parseIni(filename, (immutable(string) section, lazy immutable(string) key, lazy immutable(string) value)
            {
                if (!(section in serverConfigMap))
                {
                    serverConfigMap[section] = PatchServerConfig.init;
                    orderedConfigs ~= section.dup;
                }
                currentPatchServerConfig = &serverConfigMap[section];
                if (currentPatchServerConfig is null)
                {
                    return;
                }

                import std.conv : to;

setter_switch: switch (key)
                {
                static foreach (memberName; __traits(allMembers, PatchServerConfig))
                {
                    case memberName:
                        __traits(getMember, currentPatchServerConfig, memberName) = value.to!(typeof(__traits(getMember, currentPatchServerConfig, memberName)));
                        break setter_switch;
                }
                    default:
                        break setter_switch;
                }
            });

    foreach (section; orderedConfigs)
    {
        auto config = serverConfigMap[section];
        servers ~= new PatchServer(config, section);
    }

    return servers;
}

