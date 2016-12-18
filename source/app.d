import option;
import std.algorithm.iteration;
import std.algorithm;
import std.concurrency;
import std.file;
import std.getopt;
import std.parallelism;
import std.path;
import std.process;
import std.range;
import std.stdio;
import std.string;

struct Shutdown{}
struct Reschedule{}

void review(string command, bool verbose) {
  bool finished = false;
  if (verbose) {
    writeln("reviewer with command: ", command);
  }
  while (!finished) {
    receive(
      (Project project) {
        string h = command;
        if (command.indexOf("%s") != -1) {
          h = command.replace("%s", project.path);
        }
        if (verbose) {
          writeln("running review: ", h);
        }
        auto res = executeShell(h);
      },
      (Shutdown s) {
        finished = true;
      });
  }
}
auto gitForWorktree(Project project, string[] args ...) {
  auto workTree = project.path;
  auto gitDir = "%s/.git".format(workTree);
  return ["git", "--work-tree", workTree, "--git-dir", gitDir].chain(args).array;
}

void checker(Tid scheduler, Tid reviewer, bool verbose) {
  bool finished = false;

  scheduler.send(thisTid());
  while (!finished) {
    receive(
      (Project project) {
        auto cmd = gitForWorktree(project, "status");
        if (verbose) {
          writeln("running checker: ", cmd);
        }
        auto git = execute(cmd);

        if (git.status == 0) {
          auto output = git.output;
          if (output.indexOf("modified") != -1
              || output.indexOf("deleted") != -1
              || output.indexOf("Untracked") != -1
              || output.indexOf("Changes") != -1) {
            reviewer.send(project);
          }
        } else {
          stderr.writeln("command failed: ", cmd, git.output);
        }
        scheduler.send(thisTid());
      },
      (Shutdown s) {
        finished = true;
      }
    );
  }
}

void scheduler() {
  bool finished = false;
  bool shuttingDown = false;
  int nrOfCheckers = 0;
  Tid[] availableCheckers;
  Project[] availableWork;
  while (!finished) {
    receive(
      (int _nrOfCheckers) {
        nrOfCheckers = _nrOfCheckers;
      },
      (Project work) {
        availableWork ~= work;
        thisTid().send(Reschedule());
      },
      (Tid checker) {
        availableCheckers ~= checker;
        thisTid().send(Reschedule());
      },
      (Reschedule r) {
        if (availableWork.empty()) {
          if (shuttingDown) {
            foreach (checker; availableCheckers) {
              checker.send(Shutdown());
              nrOfCheckers--;
            }
            availableCheckers = [];
            if (nrOfCheckers == 0) {
              finished = true;
            }
          }
        } else {
          if (!availableCheckers.empty()) {
            auto work = availableWork.front;
            availableWork.popFront();

            auto checker = availableCheckers.front;
            availableCheckers.popFront();

            checker.send(work);

            thisTid().send(Reschedule());
          }
        }
      },
      (Shutdown s) {
        shuttingDown = true;
        thisTid().send(Reschedule());
      }
    );
  }
}

struct Commit {
  string sha1;
  string comment;
  this(string line) {
    auto idx = line.indexOf(' ');
    sha1 = line[0..idx];
    comment = line[idx+1..$];
  }
  this(string sha1, string comment) {
    this.sha1 = sha1;
    this.comment = comment;
  }
}
struct UploadInfo {
  Branch branch;
  Commit[] commits;
  this(Branch branch, string info) {
    this.branch = branch;
    this.commits = info.strip.split("\n").map!(s => Commit(s)).array;
  }
  this(Branch branch, Commit commit) {
    this.branch = branch;
    this.commits = [commit];
  }
}
struct Project {
  string path;
  this(string s) {
    path = s.asAbsolutePath.asNormalizedPath.array;
  }
}

struct Branch {
  Project project;
  string localBranch;
  string remote;
  string remoteBranch;

  this (string path, string localBranch, string remote, string remoteBranch) {
    this.project = Project(path);
    this.localBranch = localBranch;
    this.remote = remote;
    this.remoteBranch = remoteBranch;
  }
  this(string path, string s1, string s2) {
    this.project = Project(path);
    localBranch = getLocalBranch(s1);
    remote = getRemote(s1);
    remoteBranch = getRemoteBranch(s2);
  }
  private string getLocalBranch(string s) {
    return s.split(".")[1];
  }
  private string getRemote(string s) {
    return s.split(" ")[1];
  }
  private string getRemoteBranch(string s) {
    return s.split(" ")[1].replace("refs/heads/", "");
  }
  auto getUploadInfo() {
    auto log = execute(gitForWorktree(project, "log", "--pretty=oneline", "--abbrev-commit", "%s...%s/%s".format(localBranch, remote, remoteBranch)));
    if (log.status == 0) {
      return Some(UploadInfo(this, log.output));
    }
    return None!UploadInfo();
  }
}


auto parseTrackingBranches(Project project, string s) {
  Branch[] res;
  auto lines = s.strip.split("\n");
  if (lines.length % 2 == 1) {
    return res;
  }
  for (int i=0; i<lines.length; i += 2) {
    res ~= Branch(project.path, lines[i], lines[i+1]);
  }
  return res;
}

auto getTrackingBranches(Project project) {
  auto tracking = execute(gitForWorktree(project, "config", "--get-regex", "branch"));
  writeln(tracking);

  if (tracking.status == 0) {
    return parseTrackingBranches(project, tracking.output);
  }
  Branch[] res;
  return res;
}
import std.regex;

auto parseUpload(string edit) {
  UploadInfo[] res;
  string path;
  auto pathRegex = ctRegex!(".*?PROJECT (.*)");
  Branch branch;
  auto branchRegex = ctRegex!(".*?BRANCH (.+?) -> (.+?)/(.+)");
  auto commitRegex = ctRegex!(".*?(.*?) - (.*)");
  bool findCommit = false; // flag to search only for first commits in a branch
  foreach (line; edit.split("\n")) {
    line = line.strip;
    if (line.empty) {
      continue;
    }
    auto pathCaptures = line.matchFirst(pathRegex);
    if (!pathCaptures.empty) {
      path = pathCaptures[1];
      continue;
    }
    auto branchCaptures = line.matchFirst(branchRegex);
    if (!branchCaptures.empty) {
      branch = Branch(path, branchCaptures[1], branchCaptures[2], branchCaptures[3]);
      findCommit = true;
      continue;
    }

    if (findCommit) {
      if (line[0] != '#') {
        auto commitCaptures = line.matchFirst(commitRegex);
        if (!commitCaptures.empty) {
          auto commit = Commit(commitCaptures[1], commitCaptures[2]);
          res ~= UploadInfo(branch, commit);
          writeln("something to upload: ", commit);
          findCommit = false;
        }
      }
    }
  }
  return res;
}

void doUploads(T)(T uploads, bool dry) {
  writeln("doing uploads %d:\n%s".format(uploads.length, uploads.map!("a.to!string").join("\n")));
  foreach (upload; uploads) {
    auto cmd = gitForWorktree(upload.branch.project, "push", upload.branch.remote, "%s:refs/for/%s".format(upload.commits[0].sha1, upload.branch.remoteBranch));
    if (dry) {
      writeln(cmd);
    } else {
      execute(cmd);
    }
  }
}

auto uploadForRepo(Project project) {
  UploadInfo[Branch] uploadInfos;
  auto branches = getTrackingBranches(project);
  foreach (branch; branches) {
    auto h = branch.getUploadInfo();
    if (h.isDefined) {
      uploadInfos[branch] = h.get;
    }
  }
  bool firstCommitForProject = true;
  string summary;
  foreach (b; uploadInfos.byKeyValue()) {
    auto branch = b.key;
    auto uploadInfo = b.value;
    bool firstCommitForBranch = true;
    foreach (commit; uploadInfo.commits) {
      if (firstCommitForProject) {
        summary ~= "# PROJECT %s\n".format(project.path);
        firstCommitForProject = false;
      }
      if (firstCommitForBranch) {
        summary ~= "#   BRANCH %s -> %s/%s\n".format(branch.localBranch, branch.remote, branch.remoteBranch);
        firstCommitForBranch = false;
      }
      summary ~= "#     %s - %s\n".format(commit.sha1, commit.comment);
    }
  }
  return summary;
}

auto findGitsByWalking() {
  return dirEntries("", ".git", SpanMode.depth)
    .filter!(f => f.isDir && f.name.endsWith(".git"))
    .map!(f => Project("%s/..".format(f)))
    .array;
}

auto findGitsFromManifest() {
  auto manifestDir = findProjectList(".");
  if (manifestDir == null) {
    writeln("ohje");
    throw new Exception("cannot find .repo/project.list");
  }
  auto f = File("%s/.repo/project.list".format(manifestDir), "r");
  return f
    .byLine()
    .map!(line => Project("%s/%s".format(manifestDir, line.dup)))
    .chain([Project("%s/%s".format(manifestDir, ".repo/manifests"))])
    .array;
}

void upload(T)(T projects, bool dry) {
  auto summary = projects.map!(i => uploadForRepo(i)).join("").strip;
  if (summary.length == 0) {
    stderr.writeln("nothing todo");
    return;
  }
  auto fileName = "/tmp/worker_upload.txt";
  auto file = File(fileName, "w");
  file.write(summary);
  file.close();
  scope(exit) {
    assert(exists(fileName));
    remove(fileName);
  }

  auto edit = execute([environment.get("EDITOR", "vi"), "/tmp/worker_upload.txt"]);
  string editContent = readText(fileName);
  auto toUpload = parseUpload(editContent);
  doUploads(toUpload, dry);
}

void reviewChanges(T)(T projects, string reviewCommand, bool verbose) {
  int nrOfCheckers = std.parallelism.totalCPUs;

  auto scheduler = spawnLinked(&scheduler);
  scheduler.send(nrOfCheckers);

  auto reviewer = spawnLinked(&review, reviewCommand, verbose);
  foreach (i; iota(nrOfCheckers)) {
    spawnLinked(&checker, scheduler, reviewer, verbose);
  }

  foreach (project; projects) {
    scheduler.send(project);
  }

  scheduler.send(Shutdown());

  for (int i=0; i<nrOfCheckers+1; i++) {
    receiveOnly!LinkTerminated;
  }
  reviewer.send(Shutdown());
}

/++
 + direntries -> queue -> scheduler ----> checker ----> queue -> review
 +                                   \--> checker --/
 +                                    \-> checker -/
 + checker -> git status
 + review -> magit
 +/
int main(string[] args) {
  string reviewCommand = "magit %s";
  bool verbose = false;
  bool walk = false;
  bool dry = false;
  auto help = getopt(
    args,
    "walk|w", "Walk directories instead of using repo.", &walk,
    "verbose|v", "Output diagnostic information.", &verbose,
    "dry|d", "dry run.", &dry,
    "reviewCommand|r", q"[
  Command to run for reviewing changes. %s is replaced by the working directory.
  examples include:
    - gitk: 'env GIT_DIR=%s/.git GIT_WORK_TREE=%s gitk --all'
    - gitg: 'gitg --commit %s'
    - git-cola: 'git-cola -r %s'
    - giggle: 'giggle %s']", &reviewCommand,
  );
  if (help.helpWanted) {
    defaultGetoptPrinter(
      "worker [options] review/upload\nWorks with trees of gits either by searching for git repositories, or using information in a https://code.google.com/p/git-repo manifest folder.\nOptions:",
      help.options);
    return 0;
  }

  if (args.length != 2) {
    throw new Exception("please specify action review/upload");
  }

  auto projects = walk ? findGitsByWalking() : findGitsFromManifest();
  writeln(projects.length);

  if (args[1] == "upload") {
    upload(projects, dry);
    return 0;
  }

  if (args[1] == "review") {
    projects.reviewChanges(reviewCommand, verbose);
  }

  return 0;
}

auto getRulingDirectories(string start) {
  import std.path;
  auto res = appender!(string[])();
  auto oldDir = "";
  string dir = start.asAbsolutePath.asNormalizedPath.array;
  while (true) {
    oldDir = dir;
    res.put(dir);
    dir = "%s/..".format(dir).asAbsolutePath.asNormalizedPath.array;
    if (dir == oldDir) {
      break;
    }
  }
  return res.data;
}
unittest {
  auto all = getRulingDirectories("test/without_repo/test");
  assert(all.length > 3);
}

string findProjectList(string start) {
  auto all = getRulingDirectories(start);
  auto existing = all.find!((string a, string b) => exists("%s/%s".format(a, b)))(".repo/project.list");

  if (existing.empty) {
    return null;
  }

  return existing.front;
}

unittest {
  auto res = findProjectList("test/without_repo/test");
  assert(res == null);
}

unittest {
  import std.path;
  auto res = findProjectList("test/with_repo/test");
  assert(res == "test/with_repo".asAbsolutePath.asNormalizedPath.array);
}
