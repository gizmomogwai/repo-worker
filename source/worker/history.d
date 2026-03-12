module worker.history;

import colored;
import core.time : dur;
import profiled : theProfiler;
import std.algorithm : filter, joiner, map, sort;
import std.array : appender, array, empty, front, popFront, replicate;
import std.conv : to;
import std.datetime : Clock, SimpleTimeZone, SysTime, unixTimeToStdTime;
import std.experimental.logger : error, info, trace;
import std.parallelism : TaskPool;
import std.process;
import std.range : drop;
import std.string : format, join, leftJustify, split, startsWith;
import std.typecons : Tuple, tuple;
import tui : Terminal, Ui, Component, Context, KeyInput, ScrollPane, List, VSplit, Text, HSplit;
import worker.arguments : Log;
import worker.common : Command, Project;

// copied from phobos std.datetime.timezone.d as its package protected
static immutable(SimpleTimeZone) simpleTimeZonefromISOString(S)(S isoString) @safe pure
{
    import std.algorithm.searching : startsWith;
    import std.conv : ConvException, text, to;
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

auto parseGitDateTime(string[] epochAndZone)
{
    auto tz = epochAndZone[1].simpleTimeZonefromISOString;
    return SysTime(unixTimeToStdTime(epochAndZone[0].to!long), tz);
}

string relativeTime(SysTime time)
{
    auto diff = Clock.currTime() - time;
    long minutes = diff.total!"minutes";
    if (minutes < 1) {
        return "just now";
    }
    if (minutes < 60) {
        return "%sm ago".format(minutes);
    }
    long hours = diff.total!"hours";
    if (hours < 24) {
        return "%sh ago".format(hours);
    }
    long days = diff.total!"days";
    if (days < 30) {
        return "%sd ago".format(days);
    }
    if (days < 365) {
        return "%smo ago".format(days / 30);
    }
    return "%sy ago".format(days / 365);
}

string fitTo(string s, size_t width)
{
    if (s.length <= width) {
        return s.leftJustify(width).take(width).to!string;
    }
    if (width <= 3) {
        return "..."[0 .. width];
    }
    // width > 3
    return s[0 .. width - 3] ~ "...";
}

string dateGroup(SysTime commitDate)
{
    auto diff = Clock.currTime() - commitDate;
    long days = diff.total!"days";
    if (days < 1)
        return "Today";
    if (days < 2)
        return "Yesterday";
    if (days < 7)
        return "This week";
    if (days < 14)
        return "Last week";
    if (days < 30)
        return "This month";
    return "Older";
}

struct ListItem
{
    GitCommit commit;
    string separator;

    bool isSeparator() const
    {
        return commit is null;
    }
}

ListItem[] withSeparators(GitCommit[] commits)
{
    auto result = appender!(ListItem[]);
    string lastGroup;
    foreach (c; commits)
    {
        auto group = dateGroup(c.committerDate);
        if (group != lastGroup)
        {
            result ~= ListItem(null, group);
            lastGroup = group;
        }
        result ~= ListItem(c, "");
    }
    return result.data;
}

class GitCommit
{
    Project project;
    string sha;
    string author;
    SysTime authorDate;
    string committer;
    SysTime committerDate;
    string title;
    string message;
    this(Project project, string sha)
    {
        this.project = project;
        this.sha = sha;
    }

    this(Project project, string sha, string author, SysTime authorDate,
            string committer, SysTime committerDate, string title, string message)
    {
        this.project = project;
        this.sha = sha;
        this.author = author;
        this.authorDate = authorDate;
        this.committer = committer;
        this.committerDate = committerDate;
        this.title = title;
        this.message = message;
    }

    static auto parseCommits(Project project, string rawCommits)
    {
        auto result = appender!(GitCommit[]);
        auto lines = rawCommits.split("\n");
        GitCommit current = null;
        while (!lines.empty)
        {
            auto line = lines.front;
            if (line.startsWith("commit "))
            {
                if (current !is null)
                {
                    result ~= current;
                }
                current = new GitCommit(project, line.split[1]);
            }
            else if (line.startsWith("author "))
            {
                auto components = line.split(" ").array;
                current.author = components[1 .. $ - 2].join(" ");
                current.authorDate = components[$ - 2 .. $].parseGitDateTime;
            }
            else if (line.startsWith("committer "))
            {
                auto components = line.split(" ").array;
                current.committer = components[1 .. $ - 2].join(" ");
                current.committerDate = components[$ - 2 .. $].parseGitDateTime;
            }
            else if (line.startsWith("gpgsig "))
            {
                // skip till next
                while (!lines.front.empty)
                {
                    lines.popFront;
                }
            }
            else if (line.startsWith("    "))
            {
                if (current.title == null)
                {
                    current.title = line.drop(4).to!string;
                }
                else
                {
                    if (!current.message.empty)
                    {
                        current.message ~= "\n";
                    }
                    else
                    {
                        current.message ~= line.drop(4).to!string;
                    }
                }
            }
            lines.popFront;
        }
        if (current !is null)
        {
            result ~= current;
        }
        return result.data;
    }

    override string toString()
    {
        return "GitCommit(project: %s, sha: %s, committer: %s, committerDate: %s, author: %s, authorDate: %s, title: %s, message: %s)"
            .format(project, sha, committer, committerDate, author, authorDate, title, message);
    }
}

@("GitCommit.parse")
unittest
{
    import std.file;
    import unit_threaded;

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
    auto trace = theProfiler.start("git log of project '%s'".format(project.relativePath));
    string[] args = [
        "log", "--pretty=raw", "--since=%s".format(gitDurationSpec),
    ];
    if (!projectAndParameters.log.author.empty)
    {
        args ~= "--author=%s".format(projectAndParameters.log.author);
    }
    return project.git(args).message("Get logs")
        .run.map!(output => GitCommit.parseCommits(project, output)).front;
}

struct State
{
    bool finished;
}

State state = {finished: false,};

class StatusBar : Component
{
    string statusText;
    string helpText;

    this(string statusText, string helpText)
    {
        this.statusText = statusText;
        this.helpText = helpText;
    }

    override void render(Context context)
    {
        string line;
        if (context.width >= statusText.length + helpText.length + 1)
        {
            auto padding = context.width - statusText.length - helpText.length;
            line = (statusText ~ " ".replicate(padding) ~ helpText);
        }
        else
        {
            line = statusText.fitTo(context.width);
        }
        context.putString(0, 0, line.white.onBlue.to!string);
    }

    override bool handlesInput()
    {
        return false;
    }
}

class Details : Component
{
    GitCommit commit;
    void newSelection(ListItem item)
    {
        this.commit = item.isSeparator ? null : item.commit;
    }

    override void render(Context context)
    {
        if (commit !is null)
        {
            int line = 0;
            context.putString(0, line++, "Project: ".bold ~ commit.project.relativePath);
            context.putString(0, line++, "SHA: ".bold ~ commit.sha);
            context.putString(0, line++, "Author: ".bold ~ commit.author);
            context.putString(0, line++, "Author date: ".bold ~ commit.authorDate.to!string);
            context.putString(0, line++, "Committer: ".bold ~ commit.committer);
            context.putString(0, line++, "Committer date: ".bold ~ commit.committerDate.to!string);
            context.putString(0, line++,
                    "Δ: ".bold ~ (commit.committerDate - commit.authorDate).to!string);
            context.putString(0, line++, "Title: ".bold ~ commit.title);
            if (!commit.message.empty)
            {
                context.putString(0, line++, "Message: ".bold ~ commit.message);
            }
        }
    }

    override bool handlesInput()
    {
        return false;
    }
}

auto collectData(T)(T work, Log log)
{
    auto process = theProfiler.start("Collecting history of gits");
    auto taskPool = new TaskPool();
    scope (exit)
    {
        taskPool.finish;
    }
    auto projects = work.projects.map!(project => tuple!("project", "log")(project, log)).array;
    "History for %s projects".format(projects.length).info();

    // auto results = projects.map!(historyOfProject).joiner.array;
    return taskPool.amap!(historyOfProject)(projects).filter!(commits => commits.length > 0)
        .joiner
        .array
        .sort!((a, b) => a.committerDate > b.committerDate)
        .array;
}

void historyTui(T, Results)(T work, Log log, Results results)
{
    KeyInput keyInput;
    scope terminal = new Terminal();

    auto details = new Details();
    auto scrolledDetails = new ScrollPane(details);
    // dfmt off
    auto items = results.withSeparators;
    auto list = new List!(
        ListItem,
        (ListItem item, size_t width) {
            if (item.isSeparator) {
                return ("-- " ~ item.separator ~ " ").leftJustify(width, '-').cyan.to!string;
            }
            auto c = item.commit;
            return "%s %s %s %s".format(
                c.committerDate.relativeTime.fitTo(8).yellow,
                c.project.relativePath.fitTo(20).red,
                c.author.fitTo(50).green,
                c.title.fitTo(30),
            );
        })(items);
    // dfmt on
    list.selectionChanged.connect(&details.newSelection);
    if (!items.empty)
    {
        list.select();
    }
    list.setInputHandler((input) {
        auto item = list.getSelection();
        if (item.isSeparator)
            return false;
        auto commit = item.commit;
        switch (input.input)
        {
        case "1":
            {
                auto command = [
                    "gitk", "--all", "--select-commit=%s".format(commit.sha)
                ];
                Command(command).workdir(commit.project.absolutePath).spawn.wait;
                return true;
            }
        case "2":
            {
                auto command = ["tig", commit.sha];
                Command(command).workdir(commit.project.absolutePath).spawn.wait;
                return true;
            }
        case "3":
            {
                auto command = [
                    "magit", commit.project.absolutePath, commit.sha
                ];
                Command(command).spawn.wait;
                return true;
            }
        case "q":
            {
                state.finished = true;
                return true;
            }
        default:
            {
                return false;
            }
        }
    });
    auto listAndDetails = new VSplit(113, // (+ 8 20 50 30 3 2) // age, repo, author, title, space between colums, list cursor
            list, scrolledDetails);
    string statusString = "Found %s commits in %s repositories matching criteria since='%s'".format(
            results.length, work.projects.length, log.gitDurationSpec);
    if (!log.author.empty)
    {
        statusString ~= " and author='%s'".format(log.author);
    }
    auto globalStatus = new StatusBar(statusString, "1:gitk  2:tig  3:magit  q:quit  ESC:exit");
    auto root = new HSplit(-1, listAndDetails, globalStatus);
    root.setInputHandler((input) {
        if (input.input == "\x1B")
        {
            state.finished = true;
            return true;
        }
        return false;
    });

    auto ui = new Ui(terminal);
    ui.push(root);
    ui.resize();

    while (!state.finished)
    {
        ui.render();
        auto input = terminal.getInput();
        if (input.ctrlC)
        {
            break;
        }
        if (!input.empty)
        {
            ui.handleInput(cast() input);
        }
    }
}

void history(T)(T work, Log log)
{
    auto results = collectData(work, log);
    historyTui(work, log, results);
}
