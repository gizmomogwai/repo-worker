module worker.history;

import worker.common : Project;

import std.datetime : SysTime, unixTimeToStdTime, UTC;
import std.typecons : Tuple, tuple;
import std.conv : to;
import std.string : split, startsWith, join, format;
import std.array : empty, front, popFront, array;
import std.experimental.logger : trace, error, info;
import profiled : theProfiler;
import std.process;
import std.parallelism : TaskPool;
import std.algorithm : map, filter, sort;

auto parseGitDateTime(string[] epochAndZone) {
    return SysTime(unixTimeToStdTime(epochAndZone[0].to!long), UTC());
}

class GitCommit {
    Project project;
    string sha;
    string author;
    SysTime authorDate;
    string committer;
    SysTime committerDate;
    string message;
    this(Project project, string sha, string author, SysTime authorDate, string comitter, SysTime committerDate, string message) {
        this.project = project;
        this.sha = sha;
        this.author = author;
        this.authorDate = authorDate;
        this.committer = committer;
        this.committerDate = committerDate;
        this.message = message;
    }

    static auto parse(Project project, string rawCommit) {
        GitCommit[] result = [];
        try {
            auto lines = rawCommit.split("\n");
            while (!lines.empty && lines.front.startsWith("commit")) {
                string sha = lines.front.split(" ")[1];
                lines.popFront;
                // auto tree =lines.front... // not needed
                lines.popFront;
                while (lines.front.startsWith("parent")) {
                    // auto parent = lines.front... // not needed
                    lines.popFront;
                }
                auto authorLine = lines.front.split(" ").array;
                auto author = authorLine[1..$-2].join(" ");
                auto authorDate = authorLine[$-2..$].parseGitDateTime;
                lines.popFront;
                auto committerLine = lines.front.split(" ").array;
                auto committer = committerLine[1..$-2].join(" ");
                auto committerDate = committerLine[$-2..$].parseGitDateTime;
                lines.popFront; // skip line before git commit description

                string message;
                while (!lines.empty && !lines.front.startsWith("commit")) {
                    message ~= "\n";
                    message ~= lines.front;
                    lines.popFront;
                }
                result ~= new GitCommit(project, sha.to!string, author, authorDate, committer, committerDate, message);
            }
            return result;
        }
        catch (Throwable t) {
            "Problem with %s at %s, %s".format(project, rawCommit, t).error;
        }
        return null;
    }
    override string toString() {
        return "GitCommit(%s, %s, %s, %s)".format(project, sha, author, message);
    }
}

auto historyOfProject(Tuple!(Project, "project", string, "gitTimeSpec") projectAndTimeSpec)
{
    Project project = projectAndTimeSpec.project;
    string gitTimeSpec = projectAndTimeSpec.gitTimeSpec;
    "Working on: %s".format(project.path).trace;
    auto trace = theProfiler.start("git log of project '%s'".format(project.path));
    auto command = "git log --since='%s' --pretty=raw".format(gitTimeSpec);
    auto result = command.executeShell(null, std.process.Config.none, size_t.max, project.path);
    if (result.status != 0) {
        throw new Exception("'%s' failed in '%s' with '%s', output '%s'".format(command, project.path, result.status, result.output));
    }
    auto r = GitCommit.parse(project, result.output);
    "Project: %s commits: %s".format(project.path, r.length).trace;
    return r;
}

void history(T)(T work, string gitTimeSpec) {
    {
        theProfiler.start("Collecting history of gits");
        auto taskPool = new TaskPool();
        auto projects = work.projects.map!(project => tuple!("project", "gitTimeSpec")(project, gitTimeSpec)).array;
        "History for %s projects".format(projects.length).trace();
        /+
         auto results = projects.map!(historyOfProject).array;
         +/
        auto results = taskPool
            .amap!(historyOfProject)(projects)
            .filter!(commits => commits.length > 0)
            .array
            .sort!((a, b) => a.length > b.length);
        taskPool.finish();
        import asciitable;
        auto table = new AsciiTable(2);
        foreach (GitCommit[] commits; results) {
            auto commit = commits[0];
            auto projectShortPath = commit.project.shortPath;
            table.row().add(projectShortPath).add(commits.length.to!string);
        }
        table.format.info;
    }
//    writeln(results);
    //auto executeResults = work.projects.parallel.map!();
    /*
      if (res.status != 0)
      {
      status = res.status;
      }
      auto output = std.string.strip(res.output);
      if (output != null)
      {
      LogLevel.info.log(output);
      }
      }
    */
}
