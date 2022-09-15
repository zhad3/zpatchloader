module patchserver;

import config : PatchServerConfig, LocalPatchInfo, FailedPatch, getConfig;
import requests;
import std.typecons : Tuple;
import std.stdio : File, writeln, writefln, writef;
import std.algorithm : stripLeft, stripRight, map, filter, startsWith, endsWith, each;
import std.path : buildPath, baseName;
import std.file : exists, mkdirRecurse;

alias PatchFileEntity = Tuple!(int, "patchId", string, "uri");

class PatchServer
{
    immutable PatchServerConfig patchConfig;
    immutable string name;
    LocalPatchInfo localPatchInfo;
    PatchFileEntity[] patchFileEntities;

    private immutable(string) pathSeparator;

    this(immutable PatchServerConfig patchConfig, immutable string patchServerName)
    {
        this.patchConfig = patchConfig;
        this.name = patchServerName;

        this.pathSeparator = patchConfig.path.endsWith("/") ? "" : "/";
    }

    void update()
    {
        writefln("[%s] Loading local patch info:", name);
        loadLocalPatchInfo();
        writefln("[%s]    minPatchNumber=%d", name, localPatchInfo.minPatchNumber);
        writefln("[%s]    maxPatchNumber=%d", name, localPatchInfo.maxPatchNumber);

        addFailedPatchesToDownloadList();

        writefln("[%s] Checking for patches...", name);
        if (patchFileEntities.length > 0)
        {
            writefln("[%s] Found %d new patch(es) and %d previously failed patch(es)! Starting download...", name, patchFileEntities.length - localPatchInfo.failedPatches.length, localPatchInfo.failedPatches.length);
            downloadPatchFiles();
            saveLocalPatchInfo();
        }
        else
        {
            writefln("[%s] No new patches to download. Up-to-date.", name);
        }
    }

    bool checkForNewPatchFiles()
    {
        if (patchConfig.host == string.init || patchConfig.infoFile == string.init)
        {
            return false;
        }

        auto req = new Request();
        req.addHeaders(["User-Agent": "zpatchloader"]);
        if (localPatchInfo.etag != string.init)
        {
            req.addHeaders(["If-None-Match": localPatchInfo.etag]);
        }
        if (localPatchInfo.lastModified != string.init)
        {
            req.addHeaders(["If-Modified-Since": localPatchInfo.lastModified]);
        }

        auto patchInfoFileUri = patchConfig.host ~ patchConfig.infoFile;
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

        immutable filename = buildPath(getConfig().localPatchInfoDirectory, name) ~ ".conf";

        import iniparser : parseLocalPatchInfo;

        localPatchInfo = parseLocalPatchInfo(filename);

    }

    void saveLocalPatchInfo()
    {
        import std.format : formattedWrite;
        import std.array : appender;

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
            import std.algorithm : sort;

            app ~= "\n[failed-patches]\n";
            foreach (int failedPatchId; sort(localPatchInfo.failedPatches.keys))
            {
                immutable(FailedPatch) failedPatch = localPatchInfo.failedPatches[failedPatchId];
                app.formattedWrite("%d=%s|%d\n", failedPatch.patchId, failedPatch.filename, failedPatch.retries);
            }
        }
        file.write(app.data);
    }

    void extractPatchFileEntitiesFromPatchFile(immutable(string) responseData)
    {
        import std.array : split;
        import std.conv : to;
        import std.format : format;
        import std.regex : splitter, regex;

        responseData.splitter(regex("\n\r?"))
            .map!(line => line.stripLeft!(c => c == ' ' || c == '\t')())
            .filter!(line => line != string.init && !line.startsWith("//"))
            .map!(line => line.stripRight('\r').split(" "))
            .filter!((segments) {
                    int patchId = segments[0].to!int;
                    return patchId > localPatchInfo.maxPatchNumber && ((patchId in localPatchInfo.failedPatches) is null); // Failed patches are added in "addFailedPatchesToDownloadList()"
                })
            .map!(segments => PatchFileEntity(segments[0].to!int, buildDownloadUri(segments[1])))
            .each!(entity => patchFileEntities ~= entity);
    }

    void addFailedPatchesToDownloadList()
    {
        if (localPatchInfo.failedPatches.length == 0)
        {
            return;
        }

        import std.algorithm : sort;

        writefln("[%s] Adding %d previously failed patch(es):", name, localPatchInfo.failedPatches.length);
        int retriesExhausted = 0;

        foreach (int failedPatchId; sort(localPatchInfo.failedPatches.keys))
        {
            immutable failedPatch = localPatchInfo.failedPatches[failedPatchId];
            if (failedPatch.retries < patchConfig.maxRetries)
            {
                patchFileEntities ~= PatchFileEntity(failedPatch.patchId, buildDownloadUri(failedPatch.filename));
                writefln("[%s]   PatchId: %d, Filename: %s, Retries: %d.", name, failedPatch.patchId, failedPatch.filename, failedPatch.retries);
            }
            else
            {
                retriesExhausted++;
                writefln("[%s]   PatchId: %d, Filename: %s, Retries exhausted. Won't try again.", name, failedPatch.patchId, failedPatch.filename);
            }
        }
        if (retriesExhausted > 0)
        {
            writefln("[%s] Out of %d failed patch(es) %d have failed too often and won't be attempted to download again.", name, localPatchInfo.failedPatches.length, retriesExhausted);
        }
    }

    void downloadPatchFiles()
    {
        if (patchFileEntities.length == 0)
        {
            return;
        }

        import std.string : representation;
        import std.array : array, split;
        import std.conv : to, ConvException;

        immutable savedPath = buildPath(getConfig().tempDirectory, name);

        if (!exists(savedPath))
        {
            mkdirRecurse(savedPath);
        }

        Job[] jobs = patchFileEntities.map!(patchEntity => Job(patchEntity.uri).method("GET").opaque((patchEntity.patchId.to!string ~ "|" ~ baseName(patchEntity.uri)).representation).addHeaders(["User-Agent": "zpatchloader"])).array;

        jobs.pool(patchConfig.downloadPoolSize).each!((res) {
                import std.array : appender;
                import std.format : formattedWrite;

                auto patchEntity = (cast(string)res.opaque).split("|");
                int patchId = patchEntity[0].to!int;
                auto patchFilename = patchEntity[1];
                auto app = appender!string;

                if (res.code != 200 || res.flags != Result.OK)
                {
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
                            localPatchInfo.failedPatches[patchId] = FailedPatch(patchId, patchFilename, 0);
                        }
                    }
                }
                else
                {
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

    private string buildDownloadUri(immutable(string) filename)
    {
        return patchConfig.host ~ patchConfig.path ~ pathSeparator ~ filename;
    }

}

