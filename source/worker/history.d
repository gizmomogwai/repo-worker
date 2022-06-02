module worker.history;

import screen;
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
import std.algorithm : map, filter, sort, joiner;

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
        return "GitCommit(%s, %s, %s, %s, %s)".format(project, sha, committerDate, author, message);
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



struct State
{
    bool finished;
}

State state =
{
    finished: false,
};

class HistoryUi : Ui!(State) {
    this(Screen screen, Component root) {
        super(screen, root);
    }
    /// handle input events
    override State handleKey(KeyInput input, State state)
    {
        if (input.specialKey)
        {
            switch (input.key)
            {
            case Key.up:
                root.up;
                render;
                break;
            case Key.down:
                root.down;
                render;
                break;
            case Key.resize:
                root.resize(0, 0, screen.width, screen.height);
                render;
                break;
            default:
                break;
            }
        }
        else
        {
            switch (input.input)
            {
            case [10]:
            case [127]:
                state.finished = true;
                break;
            case "j":
                root.up;
                render;
                break;
            case "k":
                root.down;
                render;
                break;
            default:
                break;
            }
        }
        return state;
    }

    void resize() {
        root.resize(0, 0, screen.width, screen.height);
    }
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
            .joiner
            .array
            .sort!((a, b) => a.committerDate > b.committerDate)
            .array;
        taskPool.finish();

        KeyInput keyInput;
        Screen screen = new Screen("/dev/tty");
        scope (exit)
        {
            screen.destroy;
        }

        auto ui = new HistoryUi(screen,
                                new VSplit(0.6,
                                           new List!(GitCommit, gitCommit => "%s %s %s".format(gitCommit.committerDate, gitCommit.project.shortPath, gitCommit.author))(results),
                                           new Filled("b")));
        ui.resize();
        while (!state.finished)
        {
            try
            {
                ui.render();
                state = ui.handleKey(screen.getWideCharacter, state);
            }
            catch (NoKeyException e)
            {
            }
        }
    }
}
