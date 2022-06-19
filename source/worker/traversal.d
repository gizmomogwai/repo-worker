module worker.traversal;

import std.path : asAbsolutePath, asNormalizedPath;
import std.array : array;
import std.algorithm : map, filter, find;
import std.typecons : Tuple;
import worker.common : Project;
import std.file : dirEntries, SpanMode, exists;
import std.string : endsWith, format;
import std.stdio : File;
import std.range : chain;
import std.array : appender, empty, front, popFront;

alias Work = Tuple!(string, "base", Project[], "projects");

enum TraversalMode
{
    REPO,
    WALK,
}

auto findGitsByWalking(string baseDirectory)
{
    string base = baseDirectory.asAbsolutePath.asNormalizedPath.array;
    return Work(base, dirEntries(base, ".git", SpanMode.depth)
            .filter!(f => f.isDir && f.name.endsWith(".git"))
            .map!(f => Project(base, "%s/..".format(f)))
            .array);
}

auto findGitsFromManifest(string baseDirectory)
{
    auto manifestDir = findProjectList(baseDirectory);
    if (manifestDir == null)
    {
        throw new Exception("cannot find .repo/project.list");
    }
    auto f = File("%s/.repo/project.list".format(manifestDir), "r");
    // dfmt off
    return Work(manifestDir,
                f.byLine().map!(line => Project(manifestDir, "%s/%s".format(manifestDir, line.dup)))
                .chain([Project(manifestDir, "%s/%s".format(manifestDir, ".repo/manifests"))])
                .array);
    // dfmt on
}

auto getRulingDirectories(string start)
{
    auto res = appender!(string[])();
    auto oldDir = "";
    string dir = start.asAbsolutePath.asNormalizedPath.array;
    while (true)
    {
        oldDir = dir;
        res.put(dir);
        dir = "%s/..".format(dir).asAbsolutePath.asNormalizedPath.array;
        if (dir == oldDir)
        {
            break;
        }
    }
    return res.data;
}

@("getRulingDirectories") unittest
{
    import unit_threaded;

    "test/without_repo/test".getRulingDirectories.length.shouldBeGreaterThan(3);
}

string findProjectList(string start)
{
    auto all = start.getRulingDirectories;
    auto existing = all.find!((string a, string b) => exists("%s/%s".format(a,
            b)))(".repo/project.list");

    if (existing.empty)
    {
        return null;
    }

    return existing.front;
}

@("find projectlist without repo") unittest
{
    import unit_threaded;

    "test/without_repo/test".findProjectList.shouldBeNull;
}

@("find projectlist with repo") unittest
{
    import unit_threaded;

    "test/with_repo/test".findProjectList.shouldEqual(
            "test/with_repo".asAbsolutePath.asNormalizedPath.array);
}
