module worker.history;

import terminal;
import colored;
import worker.common : Project;

import std.datetime : SysTime, unixTimeToStdTime, UTC;
import std.typecons : Tuple, tuple;
import std.conv : to;
import std.string : split, startsWith, join, format, leftJustify;
import std.array : empty, front, popFront, array;
import std.experimental.logger : trace, error, info;
import profiled : theProfiler;
import std.process;
import std.parallelism : TaskPool;
import std.algorithm : map, filter, sort, joiner;
import std.range : take, drop;

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
    string title;
    string message;
    this(Project project, string sha, string author, SysTime authorDate, string comitter, SysTime committerDate, string title, string message) {
        this.project = project;
        this.sha = sha;
        this.author = author;
        this.authorDate = authorDate;
        this.committer = committer;
        this.committerDate = committerDate;
        this.title = title;
        this.message = message;
    }

    static auto parse(Project project, string rawCommit) {
        GitCommit[] result = [];
        try {
            import std.stdio; writeln("rawCommit: ", rawCommit);
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
                lines.popFront;
                lines.popFront; // skip line before git commit description
                string title;
                if (!lines.empty && !lines.front.startsWith("commit")) {
                    title = lines.front.drop(4).to!string;
                    lines.popFront;
                }
                string message;
                while (!lines.empty && !lines.front.startsWith("commit")) {
                    if (!message.empty)
                    {
                        message ~= "\n";
                    }
                    message ~= lines.front.drop(4);
                    lines.popFront;
                }
                result ~= new GitCommit(project, sha.to!string, author, authorDate, committer, committerDate, title, message);
            }
            return result;
        }
        catch (Throwable t) {
            "Problem with %s at %s, %s".format(project, rawCommit, t).error;
        }
        return null;
    }
    override string toString() {
        return "GitCommit(%s, %s, %s, %s, %s)".format(project, sha, committerDate, author, title, message);
    }
}

auto historyOfProject(Tuple!(Project, "project", string, "gitTimeSpec") projectAndTimeSpec)
{
    Project project = projectAndTimeSpec.project;
    string gitTimeSpec = projectAndTimeSpec.gitTimeSpec;
    "Working on: %s".format(project.path).info;
    auto trace = theProfiler.start("git log of project '%s'".format(project.shortPath));
    auto command = "git log --since='%s' --pretty=raw".format(gitTimeSpec);
    auto result = command.executeShell(null, std.process.Config.none, size_t.max, project.path);
    if (result.status != 0) {
        throw new Exception("'%s' failed in '%s' with '%s', output '%s'".format(command, project.path, result.status, result.output));
    }
    auto r = GitCommit.parse(project, result.output);
    "Project: %s commits: %s".format(project.path, r.length).info;
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
    this(Terminal terminal, Component root) {
        super(terminal, root);
    }
    /// handle input events
    override State handleKey(KeyInput input, State state)
    {
        /*
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
                resize();
                render;
                break;
            default:
                break;
            }
        }
        else
        */
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
        with (terminal.dimension) {
            root.resize(0, 0, width, height);
        }
    }
}

class Details : Component {
    GitCommit commit;
    void newSelection(GitCommit commit) {
        this.commit = commit;
    }
    override void render(Terminal t) {
        if (commit !is null) {
            t.xy(left, top).putString("Project: " ~ commit.project.shortPath);
            t.xy(left, top+1).putString("SHA: " ~ commit.sha);
            t.xy(left, top+2).putString("Author: " ~ commit.author);
            t.xy(left, top+3).putString("Title: " ~ commit.title);
            t.xy(left, top+4).putString("Message: " ~ commit.message);
        }
    }
}

void history(T)(T work, string gitTimeSpec) {
    {
        theProfiler.start("Collecting history of gits");
        auto taskPool = new TaskPool();
        auto projects = work.projects.map!(project => tuple!("project", "gitTimeSpec")(project, gitTimeSpec)).array;
        "History for %s projects".format(projects.length).info();

        // auto results = projects.map!(historyOfProject).joiner.array;
        auto results = taskPool
            .amap!(historyOfProject)(projects)
            .filter!(commits => commits.length > 0)
            .joiner
            .array
            .sort!((a, b) => a.committerDate > b.committerDate)
            .array;

        taskPool.finish();

        KeyInput keyInput;
        scope terminal = new Terminal();

        auto details = new Details();
        auto list =  new List!(GitCommit,
                               gitCommit => "%s %s %s %s"
                               .format(gitCommit.committerDate.to!string.leftJustify(21).take(21).to!string.blue,
                                       gitCommit.project.shortPath.leftJustify(20).take(20).to!string.red,
                                       gitCommit.author.leftJustify(50).take(50).to!string.green,
                                       gitCommit.title.leftJustify(30).take(30).to!string,
                               ))(results);
        list.selectionChanged.connect(&details.newSelection);
        auto ui = new HistoryUi(terminal,
                                new VSplit(127, // (+ 21 20 50 30 4 ) => 124
                                           list,
                                           details));
        ui.resize();
        while (!state.finished)
        {
            try
            {
                ui.render();
                state = ui.handleKey(terminal.getInput(), state);
            }
            catch (NoKeyException e)
            {
            }
        }
    }
}
