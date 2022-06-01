module worker.upload;

import worker.common : Project, Commit;
import std.algorithm : map, filter;
import std.string : format, split, strip, replace, join;
import std.regex : ctRegex, matchFirst;
import std.array : empty, front, popFront;
import std.experimental.logger : info;
import std.conv : to;
import std.array : array;
import std.file;
import std.process : environment, spawnProcess, wait;
import std.file : remove;
import std.stdio : File;

enum ChangeSetType
{
    NORMAL,
    WIP,
    PRIVATE,
    DRAFT,
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
        return project
            .git("log", "--pretty=oneline", "--abbrev-commit", "%s...%s/%s".format(localBranch, remote, remoteBranch))
            .message("GetUploadInfo")
            .run
            .map!(o => UploadInfo(this, o))
            ;
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
    auto pushRemoteRegex = ctRegex!("branch\\.(.+?)\\.(?:push)?remote (.+)");
    auto mergeRegex = ctRegex!("branch\\.(.+?)\\.merge (.+)");
    foreach (line; lines)
    {
        {
            auto remoteCaptures = line.matchFirst(remoteRegex);
            if (!remoteCaptures.empty)
            {
                branch = remoteCaptures[1];
                remote = remoteCaptures[2];
            }
        }
        if (branch == null || remote == null) {
            auto remoteCaptures = line.matchFirst(pushRemoteRegex);
            if (!remoteCaptures.empty) {
                branch = remoteCaptures[1];
                remote = remoteCaptures[2];
            }
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
    // dfmt off
    return project
        .git("config", "--get-regex", "branch")
        .message("getTrackingBranches")
        .run
        .map!((string t) => parseTrackingBranches(project, t))
        .front;
    // dfmt on
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

auto asGerritRequest(ChangeSetType changeSetType)
{
    switch (changeSetType)
    {
    case ChangeSetType.NORMAL:
        return "";
    case ChangeSetType.WIP:
        return "%wip";
    case ChangeSetType.PRIVATE:
        return "%private";
    case ChangeSetType.DRAFT:
        return "";
    default:
        throw new Exception("nyi for " ~ changeSetType.to!string);
    }
}

void doUploads(T)(T uploads, bool dry, string topic, string hashtag, ChangeSetType changeSetType)
{
    foreach (upload; uploads)
    {
        info(upload);
        auto args = [
            "push", upload.branch.remote,
            "%s:refs/%s/%s%s".format(upload.commits[0].sha1, changeSetType == ChangeSetType.DRAFT
                    ? "drafts" : "for", upload.branch.remoteBranch, changeSetType.asGerritRequest)
        ];
        if (topic != null)
        {
            args ~= "-o";
            args ~= "topic=%s".format(topic);
        }

        if (hashtag != null)
        {
            args ~= "-o";
            args ~= "t=%s".format(hashtag);
        }

        auto result = upload
            .branch
            .project
            .git(args)
            .dry(dry)
            .message("PushingUpstream")
            .run;
        info(result);
/+
        if (!result.empty)
        {
            info(result.front);
        }
+/
    }
}

auto uploadForRepo(Project project)
{
    UploadInfo[Branch] uploadInfos;
    auto branches = getTrackingBranches(project);
    foreach (branch; branches)
    {
        auto h = branch.getUploadInfo();
        if (!h.empty)
        {
            uploadInfos[branch] = h.front;
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

void upload(T)(T work, bool dry, string topic, string hashtag, ChangeSetType changeSetType)
{
    auto summary = work.projects
        .map!(i => uploadForRepo(i))
        .filter!(i => i.length > 0)
        .join(
                "# --------------------------------------------------------------------------------\n");
    if (summary.length == 0)
    {
        info("all clean");
        return;
    }
    auto topicMessage = topic == null ? "" : "\n# Topic: %s".format(topic);
    auto hashtagMessage = hashtag == null ? "" : "\n# Hashtag: %s".format(hashtag);
    auto sep = "# ================================================================================";
    summary = "# Workspace: %s%s%s\n# ChangeSetType: %s\n%s\n".format(work.base,
            topicMessage, hashtagMessage, changeSetType.to!string, sep) ~ summary;

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
    if (edit != 0)
    {
        return;
    }

    string editContent = readText(fileName);
    auto toUpload = parseUpload(work.base, editContent);
    doUploads(toUpload, dry, topic, hashtag, changeSetType);
}
