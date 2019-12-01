/++
 + Copyright: Copyright © 2016, Christian Köstlin
 + Authors: Christian Koestlin
 + License: MIT
 +/
module worker;

public import worker.packageversion;

import androidlogger;
import option;
import unit;
import std.algorithm;
import std.concurrency;
import std.datetime.stopwatch;
import std.experimental.logger;
import std.file;
import std.getopt;
import std.parallelism;
import std.path;
import std.process;
import std.range;
import std.regex;
import std.stdio;
import std.string;
import std.traits;
import std.typecons;

struct Shutdown
{
}

struct Reschedule
{
}

struct ReportForDuty
{
}

alias Work = Tuple!(string, "base", Project[], "projects");

/++
 + direntries -> queue -> scheduler ----> checker ----> queue -> review
 +                                   \--> checker --/
 +                                    \-> checker -/
 + checker -> git status
 + review -> magit
 +/
void review(string command)
{
    bool finished = false;
    "reviewer: started with command '%s'".format(command).trace;
    while (!finished)
    {
        // dfmt off
        receive(
            (Project project)
            {
                string h = command.replace("%s", project.path);
                "reviewer: running review: '%s'".format(h).info;
                auto res = executeShell(h);
            },
            (Shutdown s)
            {
                finished = true;
            }
        );
        // dfmt on
    }
}

enum State
{
    clean,
    dirty
}

auto dirty(string output)
{
    return output.indexOf("modified") != -1 || output.indexOf("deleted") != -1
        || output.indexOf("Untracked") != -1 || output.indexOf("Changes") != -1
        ? State.dirty : State.clean;
}

void checker(Tid scheduler, Tid reviewer)
{
    bool finished = false;

    scheduler.send(thisTid(), ReportForDuty());
    while (!finished)
    {
        // dfmt off
        receive(
            (Project project)
            {
                auto cmd = project.git("status").message("checker: getting status for '%s'".format(project.shortPath)).run;
                if (cmd.isDefined)
                {
                    auto dirty = cmd.get.dirty;
                    "checker: '%s' is %s".format(project.shortPath, dirty).info;
                    if (dirty == State.dirty)
                    {
                        reviewer.send(project);
                    }
                }
                scheduler.send(thisTid(), ReportForDuty());
            },
            (Shutdown s)
            {
                finished = true;
            });
        // dftm on
    }
}

void scheduler(int nrOfCheckers)
{
    bool finished = false;
    bool shuttingDown = false;
    Tid[] availableCheckers;
    Project[] availableWork;
    while (!finished)
    {
        // dfmt off
        receive(
            (Project work)
            {
                availableWork ~= work;
                thisTid().send(Reschedule());
            },
            (Tid checker, ReportForDuty _)
            {
                availableCheckers ~= checker;
                thisTid().send(Reschedule());
            },
            (Reschedule r)
            {
                if (availableWork.empty())
                {
                    if (shuttingDown)
                    {
                        foreach (checker; availableCheckers)
                        {
                            checker.send(Shutdown());
                            nrOfCheckers--;
                        }
                        availableCheckers = [];
                        if (nrOfCheckers == 0)
                        {
                            finished = true;
                        }
                    }
                }
                else
                {
                    if (!availableCheckers.empty())
                    {
                        auto work = availableWork.front;
                        availableWork.popFront();

                        auto checker = availableCheckers.front;
                        availableCheckers.popFront();

                        checker.send(work);

                        thisTid().send(Reschedule());
                    }
                }
            },
            (Shutdown s)
            {
                shuttingDown = true;
                thisTid().send(Reschedule());
            }
        );
        // dfmt on
    }
}

struct Commit
{
    string sha1;
    string comment;
    this(string line)
    {
        auto idx = line.indexOf(' ');
        sha1 = line[0 .. idx];
        comment = line[idx + 1 .. $];
    }

    this(string sha1, string comment)
    {
        this.sha1 = sha1;
        this.comment = comment;
    }
}

struct UploadInfo
{
    Branch branch;
    Commit[] commits;
    this(Branch branch, string info)
    {
        this.branch = branch;
        this.commits = info.strip.split("\n").map!(s => Commit(s)).array;
    }

    this(Branch branch, Commit commit)
    {
        this.branch = branch;
        this.commits = [commit];
    }
}

struct Command
{
    // names end with _ because the fluid api needs methods with the same name
    string[] command_;
    bool dry_ = false;
    string message_;
    this(string[] cmd)
    {
        this.command_ = cmd;
    }

    this(string[] cmd, bool dry, string message)
    {
        command_ = cmd;
        dry_ = dry;
        message_ = message;
    }

    Command message(string message)
    {
        return Command(this.command_, this.dry_, message);
    }

    Command dry(bool dry = true)
    {
        return Command(this.command_, dry, this.message_);
    }

    auto run()
    {
        trace("%s: executing %s".format(message_, command_));

        if (dry_)
        {
            return None!string();
        }
        auto res = execute(command_);
        if (res.status == 0)
        {
            return Some(res.output);
        }
        else
        {
            "Problem working on: %s".format(command_).error;
            res.output.error;
            return None!string();
        }
    }
}

struct Project
{
    string base;
    string path;
    this(string base, string s)
    {
        this.base = base.asAbsolutePath.asNormalizedPath.array;
        if (s[0] == '/')
        {
            this.path = s;
        }
        else
        {
            this.path = this.base ~ "/" ~ s;
        }
    }

    auto git(string[] args...)
    {
        auto workTree = this.path;
        auto gitDir = "%s/.git".format(workTree);
        auto cmd = ["git", "--work-tree", workTree, "--git-dir", gitDir].chain(args).array;
        return Command(cmd);
    }

    string shortPath()
    {
        return path.replace(base, "")[1 .. $];
    }
}

struct Branch
{
    Project project;
    string localBranch;
    string remote;
    string remoteBranch;

    this(Project project, string localBranch, string remote, string remoteBranch)
    {
        this.project = project;
        this.localBranch = localBranch;
        this.remote = remote;
        this.remoteBranch = remoteBranch;
    }

    auto getUploadInfo()
    {
        auto log = project.git("log", "--pretty=oneline", "--abbrev-commit",
                "%s...%s/%s".format(localBranch, remote, remoteBranch)).message(
                "GetUploadInfo").run();
        return log.map!(o => UploadInfo(this, o));
    }
}

auto parseTrackingBranches(Project project, string s)
{
    Branch[] res;
    auto lines = s.strip.split("\n");

    string branch = null;
    string remote = null;
    string remoteBranch = null;
    auto remoteRegex = ctRegex!("branch\\.(.+?)\\.remote (.+)");
    auto mergeRegex = ctRegex!("branch\\.(.+?)\\.merge (.+)");
    foreach (line; lines)
    {
        auto remoteCaptures = line.matchFirst(remoteRegex);
        if (!remoteCaptures.empty)
        {
            branch = remoteCaptures[1];
            remote = remoteCaptures[2];
        }

        auto mergeCapture = line.matchFirst(mergeRegex);
        if (!mergeCapture.empty)
        {
            remoteBranch = mergeCapture[2];
        }

        if (branch != null && remote != null && remoteBranch != null)
        {
            string cleanUpRemoteBranchName(string s)
            {
                return s.replace("refs/heads/", "");
            }

            res ~= Branch(project, branch, remote, cleanUpRemoteBranchName(remoteBranch));
            branch = null;
            remote = null;
            remoteBranch = null;
        }
    }
    return res;
}

@("parseTrackingBranches") unittest
{
    import unit_threaded;

    auto res = parseTrackingBranches(Project("base", "test"),
            "branch.default.remote gerrit\nbranch.default.merge refs/heads/master\n");
    res.length.shouldEqual(1);
    res[0].localBranch.shouldEqual("default");
    res[0].remote.shouldEqual("gerrit");
    res[0].remoteBranch.shouldEqual("master");

    res = parseTrackingBranches(Project("base", "test"),
            "branch.default.remote gerrit\nbranch.default.merge refs/heads/master\nbranch.default.rebase false\n");
    res.length.shouldEqual(1);
    res[0].localBranch.shouldEqual("default");
    res[0].remote.shouldEqual("gerrit");
    res[0].remoteBranch.shouldEqual("master");
}

auto getTrackingBranches(Project project)
{
    info("getTrackingBranches");
    auto tracking = project.git("config", "--get-regex", "branch")
        .message("GetTrackingBranches").run();
    if (tracking.isDefined)
    {
        return parseTrackingBranches(project, tracking.get);
    }
    Branch[] res;
    return res;
}

auto parseUpload(string base, string edit)
{
    auto pathRegex = ctRegex!(".*?PROJECT (.*)");
    auto branchRegex = ctRegex!(".*?BRANCH (.+?) -> (.+?)/(.+)");
    auto commitRegex = ctRegex!(".*?(.*?) - (.*)");

    UploadInfo[] res;
    string path;

    Branch branch;
    bool foundCommit = false; // flag to search only for first commits in a branch
    foreach (line; edit.split("\n"))
    {
        line = line.strip.dup;
        if (line.empty)
        {
            continue;
        }
        auto pathCaptures = line.matchFirst(pathRegex);
        if (!pathCaptures.empty)
        {
            path = pathCaptures[1];
            continue;
        }
        auto branchCaptures = line.matchFirst(branchRegex);
        if (!branchCaptures.empty)
        {
            branch = Branch(Project(base, path), branchCaptures[1],
                    branchCaptures[2], branchCaptures[3]);
            foundCommit = true;
            continue;
        }

        if (foundCommit)
        {
            if (line[0] != '#')
            {
                auto commitCaptures = line.matchFirst(commitRegex);
                if (!commitCaptures.empty)
                {
                    auto commit = Commit(commitCaptures[1], commitCaptures[2]);
                    res ~= UploadInfo(branch, commit);
                    foundCommit = false;
                }
            }
        }
    }
    return res;
}

@("parseUpload") unittest
{
    import unit_threaded;

    auto res = parseUpload("thebase", q"[# PROJECT test
#   BRANCH default -> remote/master
     123456 - message
]");
    res.length.shouldEqual(1);
    res[0].branch.localBranch.shouldEqual("default");
    res[0].branch.remote.shouldEqual("remote");
    res[0].branch.remoteBranch.shouldEqual("master");
    res[0].commits.length.shouldEqual(1);
    res[0].commits[0].sha1.shouldEqual("123456");
}

void doUploads(T)(T uploads, bool dry, string topic)
{
    foreach (upload; uploads)
    {
        info(upload);
        auto topicParameter = topic == null ? "" : "%%topic=%s".format(topic);
        upload.branch.project.git("push", upload.branch.remote,
                "%s:refs/for/%s%s".format(upload.commits[0].sha1,
                    upload.branch.remoteBranch, topicParameter)).dry(dry)
            .message("PushingUpstream").run();
    }
}

auto uploadForRepo(Project project)
{
    UploadInfo[Branch] uploadInfos;
    auto branches = getTrackingBranches(project);
    foreach (branch; branches)
    {
        auto h = branch.getUploadInfo();
        if (h.isDefined)
        {
            uploadInfos[branch] = h.get;
        }
    }

    return calcUploadText(uploadInfos);
}

string calcUploadText(UploadInfo[Branch] uploadInfos)
{
    bool firstCommitForProject = true;
    string[] projects;
    foreach (b; uploadInfos.byKeyValue())
    {
        auto branch = b.key;
        auto uploadInfo = b.value;
        bool firstCommitForBranch = true;
        string project = "";
        foreach (commit; uploadInfo.commits)
        {
            if (firstCommitForProject)
            {
                project ~= "# PROJECT %s\n".format(branch.project.shortPath());
                firstCommitForProject = false;
            }
            if (firstCommitForBranch)
            {
                project ~= "#   BRANCH %s -> %s/%s\n".format(branch.localBranch,
                        branch.remote, branch.remoteBranch);
                firstCommitForBranch = false;
            }
            project ~= "#     %s - %s\n".format(commit.sha1, commit.comment);
        }
        if (uploadInfo.commits.length > 0)
        {
            projects ~= project;
        }
    }
    return projects.join("");
}

@("calc upload text") unittest
{
    import unit_threaded;

    UploadInfo[Branch] uploadInfos;
    auto b = Branch(Project("base", "test"), "default", "remote", "master");
    uploadInfos[b] = UploadInfo(b, Commit("123456", "message"));
    auto expected = q"[# PROJECT test
#   BRANCH default -> remote/master
#     123456 - message
]";
    uploadInfos.calcUploadText.shouldEqual(expected);
}

auto findGitsByWalking()
{
    string base = ".".asAbsolutePath.asNormalizedPath.array;
    return Work(base, dirEntries("", ".git", SpanMode.depth)
            .filter!(f => f.isDir && f.name.endsWith(".git")).map!(f => Project(base,
                "%s/..".format(f))).array);
}

auto findGitsFromManifest()
{
    auto manifestDir = findProjectList(".");
    if (manifestDir == null)
    {
        throw new Exception("cannot find .repo/project.list");
    }
    auto f = File("%s/.repo/project.list".format(manifestDir), "r");
    return Work(manifestDir, f.byLine().map!(line => Project(manifestDir,
            "%s/%s".format(manifestDir, line.dup))).chain([Project(manifestDir,
            "%s/%s".format(manifestDir, ".repo/manifests"))]).array);
}

void upload(T)(T work, bool dry, string topic)
{
    auto summary = work.projects.map!(i => uploadForRepo(i)).filter!(i => i.length > 0)
        .join(
                "# --------------------------------------------------------------------------------\n");
    if (summary.length == 0)
    {
        info("all clean");
        return;
    }
    auto topicMessage = topic == null ? "" : "\n# Topic: %s".format(topic);
    auto sep = "# ================================================================================";
    summary = "# Workspace: %s%s\n%s\n".format(work.base, topicMessage, sep) ~ summary;

    auto fileName = "/tmp/worker_upload.txt";
    auto file = File(fileName, "w");
    file.write(summary);
    file.close();
    scope (exit)
    {
        assert(exists(fileName));
        remove(fileName);
    }

    auto edit = [environment.get("EDITOR", "vi"), "/tmp/worker_upload.txt"].spawnProcess.wait;
    if (edit != 0) {
        return;
    }

    string editContent = readText(fileName);
    auto toUpload = parseUpload(work.base, editContent);
    doUploads(toUpload, dry, topic);
}

void executeCommand(T)(T work, string command)
{
    auto status = 0;
    foreach (project; work.projects.sort!("a.base < b.base"))
    {
        LogLevel.warning.log("Running %s in %s".format(command, project.path.asNormalizedPath));
        auto sw = StopWatch(AutoStart.yes);
        auto res = command.executeShell(null, Config.none, size_t.max, project.path);
        if (res.status != 0)
        {
            status = res.status;
        }
        auto duration = sw.peek();
        auto d = duration.total!("msecs");
        // dfmt off
        auto description = "Finished with %s in %s"
            .format(res.status,
                TIME
                    .transform(d)
                    .onlyRelevant
                    .map!(p => "%s%s".format(p.value, p.name))
                    .join(" "));
        // dfmt on
        auto output = std.string.strip(res.output);
        LogLevel.warning.log(description);
        if (output != null)
        {
            (res.status == 0 ? LogLevel.info : LogLevel.error).log(output);
        }
    }
}

void reviewChanges(T)(T work, string reviewCommand)
{
    int nrOfCheckers = std.parallelism.totalCPUs;

    auto scheduler = spawnLinked(&scheduler, nrOfCheckers);

    auto reviewer = spawnLinked(&review, reviewCommand);
    foreach (i; iota(nrOfCheckers))
    {
        spawnLinked(&checker, scheduler, reviewer);
    }

    foreach (project; work.projects)
    {
        scheduler.send(project);
    }

    scheduler.send(Shutdown());

    for (int i = 0; i < nrOfCheckers + 1; i++)
    {
        receiveOnly!LinkTerminated;
    }
    reviewer.send(Shutdown());
}

int worker_(string[] args)
{
    string reviewCommand = "magit %s";
    string executeCommand = "git status";
    bool walk = false;
    bool dry = false;
    bool withColors = true;
    string topic;
    LogLevel loglevel;
    // dfmt off
    auto help = getopt(args,
                       "walk|w", "Walk directories and search for .git repositories instead of using repo.", &walk,
                       "loglevel|l", "Output diagnostic information (%s).".format([EnumMembers!LogLevel].map!("a.to!string").join(", ")), &loglevel,
                       "topic|t", "add gerrit topic.", &topic,
                       "dry|d", "dry run.", &dry,
                       "colors|c", "colorful output.", &withColors,
                       "execute|e", "execute command on all repos.", &executeCommand,
                       "reviewCommand|r", q"[
    Command to run for reviewing changes. %s is replaced by the working directory.
    examples include:
        * gitk:     'env GIT_DIR=%s/.git GIT_WORK_TREE=%s gitk --all'
        * gitg:     'gitg --commit %s'
        * git-cola: 'git-cola -r %s'
        * giggle:   'giggle %s']", &reviewCommand,);
    // dfmt on
    if (help.helpWanted)
    {
        defaultGetoptPrinter("worker [options] review/upload/run\nWorks with trees of gits either by searching for git repositories, or using information in a https://code.google.com/p/git-repo manifest folder.\nOptions:",
                help.options);
        import asciitable;
        import packageversion;
        import colored;
        import std.conv;
        // dfmt off
        auto table = packageversion
            .getPackages
            .sort!("a.name < b.name")
            .fold!((table, p) => table.row.add(p.name.white).add(p.semVer.lightGray).add(p.license.lightGray).table)
            (new AsciiTable(3).header.add("Package".bold).add("Version".bold).add("License".bold).table);
        // dfmt on
        stderr.writeln("Packageinfo:\n", table.format.prefix("  | ").headerSeparator(true).columnSeparator(true).to!string);
        return 0;
    }

    sharedLog = new AndroidLogger(stderr, withColors, loglevel);

    if (args.length != 2)
    {
        throw new Exception("please specify action review/upload/run");
    }

    auto projects = walk ? findGitsByWalking() : findGitsFromManifest();

    auto command = args[1];
    switch (command)
    {
    case "upload":
        projects.upload(dry, topic);
        break;
    case "review":
        projects.reviewChanges(reviewCommand);
        break;
    case "run":
        projects.executeCommand(executeCommand);
        break;
    default:
        break;
    }
    return 0;
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
