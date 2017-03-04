import colorize;
import option;
import std.algorithm.iteration;
import std.algorithm;
import std.concurrency;
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
import std.typecons;

struct Shutdown{}
struct Reschedule{}
alias Work = Tuple!(string, "base", Project[], "projects");

void review(string command, bool verbose) {
  bool finished = false;
  if (verbose) {
    trace("reviewer: started with command '", command, "'");
  }
  while (!finished) {
    receive(
      (Project project) {
        string h = command;
        if (command.indexOf("%s") != -1) {
          h = command.replace("%s", project.path);
        }
        if (verbose) {
          info("reviewer: running review: '", h, "'");
        }
        auto res = executeShell(h);
      },
      (Shutdown s) {
        finished = true;
      });
  }
}

void checker(Tid scheduler, Tid reviewer, bool verbose) {
  bool finished = false;

  scheduler.send(thisTid());
  while (!finished) {
    receive(
      (Project project) {
        auto cmd = project.git("status").verbose(verbose).message("GettingStatus").run();
        if (cmd.isDefined) {
          auto output = cmd.get;
          if (output.indexOf("modified") != -1
              || output.indexOf("deleted") != -1
              || output.indexOf("Untracked") != -1
              || output.indexOf("Changes") != -1) {
            reviewer.send(project);
          }
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

struct Command {
  string[] command_;
  bool verbose_ = false;
  bool dry_ = false;
  string message_;
  this(string[] cmd) {
    this.command_ = cmd;
  }
  this(string[] cmd, bool verbose, bool dry, string message) {
    command_ = cmd;
    verbose_ = verbose;
    dry_ = dry;
    message_ = message;
  }
  Command message(string message) {
    return Command(this.command_, this.verbose_, this.dry_, message);
  }
  Command verbose(bool verbose=true) {
    return Command(this.command_, verbose, this.dry_, this.message_);
  }
  Command dry(bool dry=true) {
    return Command(this.command_, this.verbose_, dry, this.message_);
  }

  auto run() {
    if (verbose_ || dry_) {
      trace("%s: executing %s".format(message_, command_));
    }
    if (dry_) {
      return None!string();
    }
    auto res = execute(command_);
    if (res.status == 0) {
      return Some(res.output);
    } else {
      error("Problem working on: ", command_);
      error(res.output);
      return None!string();
    }
  }
}
struct Project {
  string base;
  string path;
  this(string base, string s) {
    this.base = base.asAbsolutePath.asNormalizedPath.array;
    if (s[0] == '/') {
      this.path = s;
    } else {
      this.path = this.base ~ "/" ~ s;
    }
    if (this.path == "/home/gizmo/_projects/audicgw/nxp/android_user_build/esrlabs/gradle/someip-plugin/device/cgw") {
      throw new Exception("arghl");
    }
  }
  auto git(string[] args ...) {
    auto workTree = this.path;
    auto gitDir = "%s/.git".format(workTree);
    auto cmd = ["git", "--work-tree", workTree, "--git-dir", gitDir].chain(args).array;
    return Command(cmd);
  }
  string shortPath() {
    return path.replace(base, "")[1..$];
  }
}

struct Branch {
  Project project;
  string localBranch;
  string remote;
  string remoteBranch;

  this (Project project, string localBranch, string remote, string remoteBranch) {
    this.project = project;
    this.localBranch = localBranch;
    this.remote = remote;
    this.remoteBranch = remoteBranch;
  }

  auto getUploadInfo(bool verbose) {
    auto log = project.git("log", "--pretty=oneline", "--abbrev-commit", "%s...%s/%s".format(localBranch, remote, remoteBranch))
      .verbose(verbose)
      .message("GetUploadInfo")
      .run();
    return log.map!(o => UploadInfo(this, o));
  }
}

auto parseTrackingBranches(Project project, string s) {
  Branch[] res;
  auto lines = s.strip.split("\n");

  string branch = null;
  string remote = null;
  string remoteBranch = null;
  auto remoteRegex = ctRegex!("branch\\.(.+?)\\.remote (.+)");
  auto mergeRegex = ctRegex!("branch\\.(.+?)\\.merge (.+)");
  foreach (line; lines) {
    auto remoteCaptures = line.matchFirst(remoteRegex);
    if (!remoteCaptures.empty) {
      branch = remoteCaptures[1];
      remote = remoteCaptures[2];
    }

    auto mergeCapture = line.matchFirst(mergeRegex);
    if (!mergeCapture.empty) {
      remoteBranch = mergeCapture[2];
    }

    if (branch != null
        && remote != null
        && remoteBranch != null) {
      string cleanUpRemoteBranchName(string s) {
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

unittest {
  auto res = parseTrackingBranches(Project("base", "test"), "branch.default.remote gerrit\nbranch.default.merge refs/heads/master\n");
  assert(res.length == 1);
  assert(res[0].localBranch == "default");
  assert(res[0].remote == "gerrit");
  assert(res[0].remoteBranch == "master");

  res = parseTrackingBranches(Project("base", "test"), "branch.default.remote gerrit\nbranch.default.merge refs/heads/master\nbranch.default.rebase false\n");
  assert(res.length == 1);
  assert(res[0].localBranch == "default");
  assert(res[0].remote == "gerrit");
  assert(res[0].remoteBranch == "master");
}

auto getTrackingBranches(Project project, bool verbose) {
  writeln("getTrackingBranches");
  auto tracking = project.git("config", "--get-regex", "branch").message("GetTrackingBranches").verbose(verbose).run();
  if (tracking.isDefined) {
    return parseTrackingBranches(project, tracking.get);
  }
  Branch[] res;
  return res;
}

auto parseUpload(string base, string edit) {
  auto pathRegex = ctRegex!(".*?PROJECT (.*)");
  auto branchRegex = ctRegex!(".*?BRANCH (.+?) -> (.+?)/(.+)");
  auto commitRegex = ctRegex!(".*?(.*?) - (.*)");

  UploadInfo[] res;
  string path;

  Branch branch;
  bool foundCommit = false; // flag to search only for first commits in a branch
  foreach (line; edit.split("\n")) {
    line = line.strip.dup;
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
      branch = Branch(Project(base, path), branchCaptures[1], branchCaptures[2], branchCaptures[3]);
      foundCommit = true;
      continue;
    }

    if (foundCommit) {
      if (line[0] != '#') {
        auto commitCaptures = line.matchFirst(commitRegex);
        if (!commitCaptures.empty) {
          auto commit = Commit(commitCaptures[1], commitCaptures[2]);
          res ~= UploadInfo(branch, commit);
          foundCommit = false;
        }
      }
    }
  }
  return res;
}

unittest {
  auto res = parseUpload("thebase", q"[# PROJECT test
#   BRANCH default -> remote/master
     123456 - message
]");
  assert(res.length == 1);
  assert(res[0].branch.localBranch == "default");
  assert(res[0].branch.remote == "remote");
  assert(res[0].branch.remoteBranch == "master");
  assert(res[0].commits.length == 1);
  assert(res[0].commits[0].sha1 == "123456");
}
void doUploads(T)(T uploads, bool verbose, bool dry) {
  foreach (upload; uploads) {
    writeln(upload);
    upload.branch.project.git("push", upload.branch.remote, "%s:refs/for/%s".format(upload.commits[0].sha1, upload.branch.remoteBranch))
      .dry(dry)
      .verbose(verbose)
      .message("PushingUpstream")
      .run();
  }
}

auto uploadForRepo(Project project, bool verbose) {
  UploadInfo[Branch] uploadInfos;
  auto branches = getTrackingBranches(project, verbose);
  foreach (branch; branches) {
    auto h = branch.getUploadInfo(verbose);
    if (h.isDefined) {
      uploadInfos[branch] = h.get;
    }
  }

  return calcUploadText(uploadInfos);
}

string calcUploadText(UploadInfo[Branch] uploadInfos) {
  bool firstCommitForProject = true;
  string[] projects;
  foreach (b; uploadInfos.byKeyValue()) {
    auto branch = b.key;
    auto uploadInfo = b.value;
    bool firstCommitForBranch = true;
    string project = "";
    foreach (commit; uploadInfo.commits) {
      if (firstCommitForProject) {
        project ~= "# PROJECT %s\n".format(branch.project.shortPath());
        firstCommitForProject = false;
      }
      if (firstCommitForBranch) {
        project ~= "#   BRANCH %s -> %s/%s\n".format(branch.localBranch, branch.remote, branch.remoteBranch);
        firstCommitForBranch = false;
      }
      project ~= "#     %s - %s\n".format(commit.sha1, commit.comment);
    }
    if (uploadInfo.commits.length > 0) {
      projects ~= project;
    }
  }
  return projects.join("");
}

unittest {
  UploadInfo[Branch] uploadInfos;
  auto b = Branch(Project("base", "test"), "default", "remote", "master");
  uploadInfos[b] = UploadInfo(b, Commit("123456", "message"));
  auto res = calcUploadText(uploadInfos);
  auto expected = q"[# PROJECT Users/gizmo/Dropbox/Documents/_projects/d/repo-worker/test
#   BRANCH default -> remote/master
#     123456 - message
]";
  assert(res == expected);
}

auto findGitsByWalking() {
  string base = ".".asAbsolutePath.asNormalizedPath.array;
  return Work(base,
          dirEntries("", ".git", SpanMode.depth)
            .filter!(f => f.isDir && f.name.endsWith(".git"))
            .map!(f => Project(base, "%s/..".format(f)))
              .array);
}

auto findGitsFromManifest() {
  auto manifestDir = findProjectList(".");
  if (manifestDir == null) {
    throw new Exception("cannot find .repo/project.list");
  }
  auto f = File("%s/.repo/project.list".format(manifestDir), "r");
  return Work(manifestDir,
              f
              .byLine()
              .map!(line => Project(manifestDir, "%s/%s".format(manifestDir, line.dup)))
              .chain([Project(manifestDir, "%s/%s".format(manifestDir, ".repo/manifests"))])
              .array);
}

void upload(T)(string base, T projects, bool verbose, bool dry) {
  auto summary = projects
    .map!(i => uploadForRepo(i, verbose))
    .filter!(i => i.length > 0).join("# --------------------------------------------------------------------------------\n");
  if (summary.length == 0) {
    info("all clean");
    return;
  }
  auto sep = "# ================================================================================";
  summary = "# Workspace: %s\n%s\n".format(base, sep) ~ summary;

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
  auto toUpload = parseUpload(base, editContent);
  doUploads(toUpload, verbose, dry);
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

string tid2string(Tid id) @trusted {
  import std.conv : text;
  return text(id).replace("Tid(", "").replace(")", "");
}

class AndroidLogger : FileLogger {
  string[LogLevel] logLevel2String;
  fg[LogLevel] logLevel2Fg;
  bg[LogLevel] logLevel2Bg;

  this() @system {
    super(stdout, LogLevel.all);
    initLogLevel2String();
    initColors();
  }

  override void writeLogMsg(ref LogEntry payload) {
    with (payload) {
      // android logoutput looks lokes this:
      // 06-06 12:14:46.355 372 18641 D audio_hw_primary: disable_audio_route: reset and update
      // DATE  TIME         PID TID   LEVEL TAG           Message
      auto h = timestamp.fracSecs.split!("msecs");
      auto idx = msg.indexOf(':');
      string tag = ""; // "%s.%d".format(file, line),
      string text = "";
      if (idx == -1) {
        tag = "stdout";
        text = msg;
      } else {
        tag = msg[0..idx];
        text = msg[idx+1..$];
      }
      this.file.lockingTextWriter().put("%02d-%02d %02d:%02d:%02d.%03d %d %s %s %s: %s\n".format(
                                          timestamp.month, // DATE
                                          timestamp.day,
                                          timestamp.hour, // TIME
                                          timestamp.minute,
                                          timestamp.second,
                                          h.msecs,
                                          std.process.thisProcessID, // PID
                                          tid2string(threadId), // TID
                                          logLevel2String[logLevel],
                                          tag,
                                          text).color(logLevel2Fg[logLevel]));

    }
  }
  private void initLogLevel2String() {
    logLevel2String[LogLevel.trace] = "T";
    logLevel2String[LogLevel.info] = "I";
    logLevel2String[LogLevel.warning] = "W";
    logLevel2String[LogLevel.error] = "E";
    logLevel2String[LogLevel.critical] = "C";
    logLevel2String[LogLevel.fatal] = "F";
  }

  private void initColors() {
    logLevel2Fg[LogLevel.trace] = fg.light_black;
    logLevel2Fg[LogLevel.info] = fg.white;
    logLevel2Fg[LogLevel.warning] = fg.yellow;
    logLevel2Fg[LogLevel.error] = fg.red;
    logLevel2Fg[LogLevel.critical] = fg.magenta;
  }
}

int repoWorker(string[] args) {
  sharedLog = new AndroidLogger();

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

  auto command = args[1];
  if (command == "upload") {
    upload(projects.base, projects.projects, verbose, dry);
    return 0;
  }

  if (command == "review") {
    projects.projects.reviewChanges(reviewCommand, verbose);
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
