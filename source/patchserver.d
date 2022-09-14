module patchserver;

import config : PatchServerConfig, LocalPatchInfo, FailedPatch, getConfig;
import requests;
import std.typecons : Tuple;

alias PatchFileEntity = Tuple!(int, "patchId", string, "uri");

class PatchServer
{
    immutable PatchServerConfig patchConfig;
    immutable string name;
    LocalPatchInfo localPatchInfo;
    PatchFileEntity[] patchFileEntities;

    this(immutable PatchServerConfig patchConfig, immutable string patchServerName)
    {
        this.patchConfig = patchConfig;
        this.name = patchServerName;
    }

    bool checkForNewPatchFiles()
    {
        if (patchConfig.host == string.init || patchConfig.infoFile == string.init)
        {
            return false;
        }

        auto req = new Request();
        if (localPatchInfo.etag != string.init)
        {
            req.addHeaders(["If-None-Match": localPatchInfo.etag]);
        }
        if (localPatchInfo.lastModified != string.init)
        {
            req.addHeaders(["If-Modified-Since": localPatchInfo.lastModified]);
        }

        auto patchInfoFileUri = patchConfig.host ~ patchConfig.infoFile;
        import std.stdio : writeln, writefln, writef;
        writef("[%s] GET %s => ", name, patchInfoFileUri);
        auto res = req.get(patchInfoFileUri);
        writeln(res.code);

        if ("etag" in res.responseHeaders)
        {
            localPatchInfo.etag = res.responseHeaders["etag"];
        }

        if ("last-modified" in res.responseHeaders)
        {
            localPatchInfo.lastModified = res.responseHeaders["last-modified"];
        }

        import std.stdio : File;
        import std.file : exists;
        import std.path : buildPath;

        immutable savedPatchInfoFilename = buildPath(getConfig().localPatchInfoDirectory, name ~ "_patchinfo.txt");
        if (res.code == 304 && exists(savedPatchInfoFilename))
        {
            import std.file : readText;
            immutable(string) savedPatchInfoData = readText(savedPatchInfoFilename);
            extractPatchFileEntitiesFromPatchFile(savedPatchInfoData);
            return patchFileEntities.length > 0;
        }

        if (res.code == 200)
        {
            immutable responseData = res.responseBody.toString();
            auto savedPatchInfo = File(savedPatchInfoFilename, "w+");
            scope(exit)
                savedPatchInfo.close();
            savedPatchInfo.rawWrite(res.responseBody.data!(ubyte[]));

            extractPatchFileEntitiesFromPatchFile(responseData);
            return patchFileEntities.length > 0;
        }
        return false;
    }

    void loadLocalPatchInfo()
    {
        import std.path : buildPath;

        immutable filename = buildPath(getConfig().localPatchInfoDirectory, name) ~ ".conf";

        import iniparser : parseLocalPatchInfo;

        localPatchInfo = parseLocalPatchInfo(filename);

    }

    void saveLocalPatchInfo()
    {
        import std.path : buildPath;
        import std.stdio : File;
        import std.format : formattedWrite;
        import std.array : appender;
        import std.file : exists, mkdirRecurse;

        immutable filename = buildPath(getConfig().localPatchInfoDirectory, name) ~ ".conf";

        if (!exists(getConfig().localPatchInfoDirectory))
        {
            mkdirRecurse(getConfig().localPatchInfoDirectory);
        }

        auto file = File(filename, "w+");
        scope(exit)
            file.close();

        auto app = appender!string;
        static foreach (memberName; __traits(allMembers, LocalPatchInfo))
        {
            static if (memberName != "failedPatches")
            {
                app.formattedWrite("%s=%s\n", memberName, __traits(getMember, localPatchInfo, memberName));
            }
        }

        if (localPatchInfo.failedPatches.length > 0)
        {
            app ~= "\n[failed-patches]\n";
            foreach (int key, immutable(FailedPatch) failedPatch; localPatchInfo.failedPatches)
            {
                app.formattedWrite("%d=%d\n", failedPatch.patchId, failedPatch.retries);
            }
        }
        file.write(app.data);
    }

    void extractPatchFileEntitiesFromPatchFile(immutable(string) responseData)
    {
        import std.algorithm : stripLeft, stripRight, map, filter, startsWith, endsWith, each;
        import std.array : split;
        import std.conv : to;
        import std.stdio : File, writeln;
        import std.format : format;
        import std.regex : splitter, regex;

        immutable(string) seperator = patchConfig.path.endsWith("/") ? "" : "/";

        responseData.splitter(regex("\n\r?"))
            .map!(line => line.stripLeft!(c => c == ' ' || c == '\t')())
            .filter!(line => line != string.init && !line.startsWith("//"))
            .map!(line => line.stripRight('\r').split(" "))
            .filter!(segments => segments[0].to!int > localPatchInfo.maxPatchNumber)
            .map!(segments => PatchFileEntity(segments[0].to!int, patchConfig.host ~ patchConfig.path ~ seperator ~ segments[1]))
            .each!(entity => patchFileEntities ~= entity);
    }

    void downloadPatchFiles()
    {
        if (patchFileEntities.length == 0)
        {
            return;
        }

        import std.algorithm : map, each;
        import std.path : baseName, buildPath;
        import std.string : representation;
        import std.array : array, split;
        import std.conv : to, ConvException;
        import std.file : exists, mkdirRecurse;

        immutable savedPath = buildPath(getConfig().tempDirectory, name);

        if (!exists(savedPath))
        {
            mkdirRecurse(savedPath);
        }

        Job[] jobs = patchFileEntities.map!(patchEntity => Job(patchEntity.uri).method("GET").opaque((patchEntity.patchId.to!string ~ "|" ~ baseName(patchEntity.uri)).representation).addHeaders(["User-Agent": "zpatchloader"])).array;

        jobs.pool(3).each!((res) {
                import std.array : appender;
                import std.stdio : writeln;
                import std.format : formattedWrite;

                auto patchEntity = (cast(string)res.opaque).split("|");
                int patchId = patchEntity[0].to!int;
                auto patchFilename = patchEntity[1];
                auto app = appender!string;

                if (res.code != 200 || res.flags != Result.OK)
                {
                    import std.format : formattedWrite;
                    if (res.flags != Result.OK)
                    {
                        app.formattedWrite("[%s][PatchId: %d] GET %s. Exception: %s\n", name, patchId, patchFilename, cast(string)res.data);
                    }
                    else
                    {
                        app.formattedWrite("[%s][PatchId: %d] GET %s. HTTPStatus: %d. \nBody: %s\n", name, patchId, patchFilename, res.code, cast(string)res.data);
                    }

                    synchronized
                    {
                        auto failedPatch = patchId in localPatchInfo.failedPatches;
                        if (failedPatch !is null)
                        {
                            localPatchInfo.failedPatches[patchId].retries += 1;
                        }
                        else
                        {
                            localPatchInfo.failedPatches[patchId] = FailedPatch(patchId, 0);
                        }
                    }
                }
                else
                {
                    import std.stdio : File;
                    auto savedFile = File(buildPath(savedPath, patchId.to!string ~ "_" ~ patchFilename), "w+");
                    scope(exit)
                        savedFile.close();
                    savedFile.rawWrite(res.data);
                    synchronized
                    {
                        if (patchId > localPatchInfo.maxPatchNumber)
                        {
                            localPatchInfo.maxPatchNumber = patchId;
                        }
                        if (patchId < localPatchInfo.minPatchNumber || localPatchInfo.minPatchNumber == 0)
                        {
                            localPatchInfo.minPatchNumber = patchId;
                        }
                        if (localPatchInfo.failedPatches.length > 0)
                        {
                            // Does nothing if the patchId is not among the failed ones
                            localPatchInfo.failedPatches.remove(patchId);
                        }
                    }
                    app.formattedWrite("[%s][PatchId: %d] GET %s. Success!\n", name, patchId, patchFilename);
                }

                writeln(app.data);
        });
    }

}

