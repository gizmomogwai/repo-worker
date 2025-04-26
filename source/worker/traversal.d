module worker.traversal;

import std.algorithm : filter, find, map;
import std.array : array;
import std.array : appender, empty, front, popFront;
import std.file : dirEntries, exists, SpanMode;
import std.path : asAbsolutePath, asNormalizedPath;
import std.range : chain;
import std.stdio : File;
import std.string : endsWith, format;
import std.typecons : Tuple;
import worker.common : Project;

alias Work = Tuple!(string, "base", Project[], "projects");

enum TraversalMode
{
    REPO,
    WALK,
    HERE,
}

auto findGits(TraversalMode mode, string baseDirectory)
{
    final switch (mode)
    {
    case TraversalMode.REPO:
        return findProjectsFromManifest(baseDirectory);
    case TraversalMode.WALK:
        return findProjectsByWalking(baseDirectory);
    case TraversalMode.HERE:
        return findProjectByDominatingGit(baseDirectory);
    }
}

auto findProjectByDominatingGit(string baseDirectory)
{
    auto all = baseDirectory.getRulingDirectories;
    auto candidates = all.find!((string a, string b) => exists("%s/%s".format(a, b)))(".git");
    if (candidates.empty)
    {
        throw new Exception("cannot find .git repository");
    }
    return Work(baseDirectory, [Project(candidates.front, ".")]);
}

auto findProjectsByWalking(string baseDirectory)
{
    string base = baseDirectory.asAbsolutePath.asNormalizedPath.array;
    return Work(base, dirEntries(base, ".git", SpanMode.depth)
            .filter!(f => f.isDir && f.name.endsWith(".git"))
            .map!(f => Project(base, "%s/..".format(f)))
            .array);
}

auto findProjectsFromManifest(string baseDirectory)
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
