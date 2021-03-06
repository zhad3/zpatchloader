import zconfig;
import std.stdio;

import config;

enum usage = "zpatchloader - Download patch files of Ragnarok Online";

int main(string[] args)
{
    Config conf;
    bool helpWanted = false;

    import std.getopt : GetOptException;

    try
    {
        conf = getConfig(args, helpWanted);
    }
    catch (GetOptException e)
    {
        import std.stdio : stderr;
        stderr.writefln("Invalid argument: %s", e.msg);
        return 1;
    }

    if (helpWanted)
    {
        return 0;
    }

    // TODO implement logic

    return 0;
}

Config getConfig(string[] args, out bool helpWanted)
{
    string[] configArgs = getConfigArguments!Config("zpatcher.conf", args);

    if (configArgs.length > 0)
    {
        import std.array : insertInPlace;

        // Prepend them into the command line args
        args.insertInPlace(1, configArgs);
    }

    return initializeConfig!(Config, usage)(args, helpWanted);
}

