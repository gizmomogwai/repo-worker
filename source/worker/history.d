module worker.history;

import terminal;
import colored;
import worker.common : Project;
import worker.arguments : Log;
import core.time : dur;
import std.datetime : SysTime, unixTimeToStdTime, SimpleTimeZone;
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

// copied from phobos std.datetime.timezone.d as its package protected
static immutable(SimpleTimeZone) simpleTimeZonefromISOString(S)(S isoString) @safe pure
{
    import std.algorithm.searching : startsWith;
    import std.conv : text, to, ConvException;
    import std.datetime.date : DateTimeException;
    import std.exception : enforce;

    auto whichSign = isoString.startsWith('-', '+');
    enforce!DateTimeException(whichSign > 0, text("Invalid ISO String ", isoString));

    isoString = isoString[1 .. $];
    auto sign = whichSign == 1 ? -1 : 1;
    int hours;
    int minutes;

    try
    {
        // cast to int from uint is used because it checks for
        // non digits without extra loops
        if (isoString.length == 2)
        {
            hours = cast(int) to!uint(isoString);
        }
        else if (isoString.length == 4)
        {
            hours = cast(int) to!uint(isoString[0 .. 2]);
            minutes = cast(int) to!uint(isoString[2 .. 4]);
        }
        else
        {
            throw new DateTimeException(text("Invalid ISO String ", isoString));
        }
    }
    catch (ConvException)
    {
        throw new DateTimeException(text("Invalid ISO String ", isoString));
    }

    enforce!DateTimeException(hours < 24 && minutes < 60, text("Invalid ISO String ", isoString));

    return new immutable SimpleTimeZone(sign * (dur!"hours"(hours) + dur!"minutes"(minutes)));
}

auto parseGitDateTime(string[] epochAndZone) {
    auto tz = epochAndZone[1].simpleTimeZonefromISOString;
    return SysTime(unixTimeToStdTime(epochAndZone[0].to!long), tz);
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
    this(Project project, string sha) {
        this.project = project;
        this.sha = sha;
    }
    this(Project project,
         string sha,
         string author,
         SysTime authorDate,
         string comitter,
         SysTime committerDate,
         string title,
         string message) {
        this.project = project;
        this.sha = sha;
        this.author = author;
        this.authorDate = authorDate;
        this.committer = committer;
        this.committerDate = committerDate;
        this.title = title;
        this.message = message;
    }

    static auto parseCommits(Project project, string rawCommits) {
        GitCommit[] result = [];
        auto lines = rawCommits.split("\n");
        GitCommit current = null;
        while (!lines.empty) {
            auto line = lines.front;
            if (line.startsWith("commit ")) {
                if (current !is null) {
                    result ~= current;
                }
                current = new GitCommit(project, line.split[1]);
            }
            if (line.startsWith("parent ")) {
                // ignore
            }
            if (line.startsWith("tree ")) {
                // ignore
            }
            if (line.startsWith("author ")) {
                auto components = line.split(" ").array;
                current.author = components[1..$-2].join(" ");
                current.authorDate = components[$-2..$].parseGitDateTime;
            }
            if (line.startsWith("committer ")) {
                auto components = line.split(" ").array;
                current.committer = components[1..$-2].join(" ");
                current.committerDate = components[$-2..$].parseGitDateTime;
            }

            if (line.startsWith("gpgsig ")) {
                // skip till next
                while (!lines.front.empty) {
                    lines.popFront;
                }
            }
            if (line.startsWith("    ")) {
                if (current.title == null) {
                    current.title = line.drop(4).to!string;
                } else {
                    if (!current.message.empty) {
                        current.message ~= "\n";
                    } else {
                        current.message ~= line.drop(4).to!string;
                    }
                }
            }
            lines.popFront;
        }
        if (current !is null) {
            result ~= current;
        }
        return result;
    }
    override string toString() {
        return "GitCommit(project: %s, sha: %s, committer: %s, committerDate: %s, author: %s, authorDate: %s, title: %s, message: %s)".format(project, sha, committer, committerDate, author, authorDate, title, message);
    }
}

@("GitCommit.parse")
unittest {
    import unit_threaded;
    import std.file;
    auto commits = GitCommit.parseCommits(Project(".", "blub"), readText("test/commits.txt"));
    commits.length.should == 7;

    commits[6].sha.should == "e6b26dad781c97aacb53df639ac4ce7a1c52cfc1";
    commits[6].committer.should == "GitHub <noreply@github.com>";
    commits[6].title.should == "Initial commit";
    commits[6].message.should == "";
}

auto historyOfProject(Tuple!(Project, "project", Log, "log") projectAndParameters)
{
    Project project = projectAndParameters.project;
    string gitDurationSpec = projectAndParameters.log.gitDurationSpec;
    auto trace = theProfiler.start("git log of project '%s'".format(project.shortPath));
    string[] args = [
      "log",
      "--pretty=raw",
      "--since=%s".format(gitDurationSpec),
    ];
    if (!projectAndParameters.log.author.empty)
    {
        args ~= "--author=%s".format(projectAndParameters.log.author);
    }
    return project
        .git(args)
        .message("Get logs")
        .run
        .map!(output => GitCommit.parseCommits(project, output))
        .front;
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
        switch (input.input) {
        case "\x1B":
            state.finished = true;
            break;
        default:
            root.handleInput(input);
            break;
        }
        return state;
    }

    void resize() {
        with (terminal.dimension) {
            root.resize(0, 0, width, height);
        }
    }
}

class Details : Component
{
    GitCommit commit;
    void newSelection(GitCommit commit)
    {
        this.commit = commit;
    }
    override void render(Context context)
    {
        if (commit !is null)
        {
            int line = 0;
            context.putString(0, line++, "Project: ".bold ~ commit.project.shortPath);
            context.putString(0, line++, "SHA: ".bold ~ commit.sha);
            context.putString(0, line++, "Author: ".bold ~ commit.author);
            context.putString(0, line++, "Author date: ".bold ~ commit.authorDate.to!string);
            context.putString(0, line++, "Committer: ".bold ~ commit.committer);
            context.putString(0, line++, "Committer date: ".bold ~ commit.committerDate.to!string);
            context.putString(0, line++, "Δ: ".bold ~ (commit.committerDate-commit.authorDate).to!string);
            context.putString(0, line++, "Title: ".bold ~ commit.title);
            if (!commit.message.empty)
            {
                context.putString(0, line++, "Message: ".bold ~ commit.message);
            }
        }
    }
    override bool handlesInput() {
        return false;
    }
}

auto collectData(T)(T work, Log log) {
    auto process = theProfiler.start("Collecting history of gits");
    auto taskPool = new TaskPool();
    scope (exit)
    {
        taskPool.finish;
    }
    auto projects = work.projects.map!(project => tuple!("project", "log")(project, log)).array;
    "History for %s projects".format(projects.length).info();

    // auto results = projects.map!(historyOfProject).joiner.array;
    return taskPool
        .amap!(historyOfProject)(projects)
        .filter!(commits => commits.length > 0)
        .joiner
        .array
        .sort!((a, b) => a.committerDate > b.committerDate)
        .array;
}

void tui(T, Results)(T work, Log log, Results results)
{

    KeyInput keyInput;
    scope terminal = new Terminal();
    /+
    while (true) {
        import std.stdio;
        auto i = terminal.getInput();
        writeln(i);
        if (i.input == "a") {
            break;
        }
        
    }
+/
    auto details = new Details();
    auto list =  new List!(GitCommit,
                           gitCommit => "%s %s %s %s"
                           .format(gitCommit.committerDate.to!string.leftJustify(26).take(26).to!string.yellow,
                                   gitCommit.project.shortPath.leftJustify(20).take(20).to!string.red,
                                   gitCommit.author.leftJustify(50).take(50).to!string.green,
                                   gitCommit.title.leftJustify(30).take(30).to!string,
                           ))(results);
    list.selectionChanged.connect(&details.newSelection);
    if (!results.empty) {
        list.select();
    }
//    auto list2 = new List!(string,
//                           s => s)(["abc", "def"]);
    auto listAndDetails = new VSplit(132, // (+ 26 20 50 30 4 2)
                                     list,
                                     details);
    string statusString = "Found %s commits in %s repositories matching criteria since='%s'".format(results.length, work.projects.length, log.gitDurationSpec);
    if (!log.author.empty) {
        statusString ~= " and author='%s'".format(log.author);
    }
    auto globalStatus = new Text(statusString);
    auto root = new HSplit(-1, listAndDetails, globalStatus);

    auto ui = new HistoryUi(terminal,
                            root);
    list.requestFocus();
    ui.resize();
    while (!state.finished)
    {
        try
        {
            ui.render();
            auto input = terminal.getInput();
            import std.file : append; "key.log".append("read input: %s\n".format(input));
            state = ui.handleKey(input, state);
        }
        catch (NoKeyException e)
        {
        }
    }
}

void history(T)(T work, Log log)
{
    auto results = collectData(work, log);
    tui(work, log, results);
}
