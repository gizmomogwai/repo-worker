import std.concurrency;
import std.range;
import std.file;
import std.string;
import std.algorithm;
import std.parallelism;
import std.process;
import std.stdio;
import std.getopt;
import std.xml;

struct Shutdown{}
struct Reschedule{}

void review(string command, bool verbose) {
  bool finished = false;
  if (verbose) {
    writeln("reviewer with command: ", command);
  }
  while (!finished) {
    receive(
      (string workTree) {
        string h = command;
        if (command.indexOf("%s") != -1) {
          h = command.replace("%s", workTree);
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

void checker(Tid scheduler, Tid reviewer, bool verbose) {
  bool finished = false;

  scheduler.send(thisTid());
  while (!finished) {
    receive(
      (string path) {
        auto workTree = "%s/..".format(path);
        auto cmd = ["git", "--work-tree", workTree, "--git-dir", path, "status"];
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
            reviewer.send(workTree);
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
  string[] availableWork;
  while (!finished) {
    receive(
      (int _nrOfCheckers) {
        nrOfCheckers = _nrOfCheckers;
      },
      (string work) {
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

void elementsByName(Element parent, string name, void delegate(Element e) yieldElement) {
  if (parent.tag.name == name) {
    yieldElement(parent);
  }

  foreach (element; parent.elements) {
    elementsByName(element, name, yieldElement);
  }
}

/++
 + direntries -> queue -> scheduler ----> checker ----> queue -> review
 +                                   \--> checker --/
 +                                    \-> checker -/
 + checker -> git status
 + review -> magit
 +/
int main(string[] args) {
  int nrOfCheckers = std.parallelism.totalCPUs;

  string reviewCommand = "magit %s";
  bool verbose = false;
  bool walk = false;
  auto help = getopt(
    args,
   "review|r", q"[
Command to run for reviewing changes. %s is replaced by the working directory.
examples include:
  - gitk: 'env GIT_DIR=%s/.git GIT_WORK_TREE=%s gitk --all'
  - gitg: 'gitg --commit %s'
  - git-cola: 'git-cola -r %s'
  - giggle: 'giggle %s']", &reviewCommand,
    "verbose|v", "Output diagnostic information.", &verbose,
    "walk|w", "Walk directories instead of using repo.", &walk);
  if (help.helpWanted) {
    defaultGetoptPrinter(
      "run a review command on every dirty git in a repo workspace.",
      help.options);
    return 0;
  }

  int res = 0;
  auto scheduler = spawnLinked(&scheduler);
  scheduler.send(nrOfCheckers);

  auto reviewer = spawnLinked(&review, reviewCommand, verbose);
  foreach (i; iota(nrOfCheckers)) {
    spawnLinked(&checker, scheduler, reviewer, verbose);
  }

  if (walk) {
    auto gitProjects = dirEntries("", ".git", SpanMode.depth)
      .filter!(f => f.isDir && f.name.endsWith(".git"));
    foreach (project; gitProjects) {
      scheduler.send(project.name);
    }
  } else {
    auto manifestDir = findProjectList(".");
    if (manifestDir == null) {
      stderr.writeln("cannot find .repo/manifest.xml anywhere");
      res = 1;
    } else {
      auto f = File("%s/.repo/project.list".format(manifestDir), "r");
      foreach (line; f.byLine()) {
        auto project = "%s/%s/.git".format(manifestDir, line.dup);
        scheduler.send(project);
      }
      scheduler.send("%s/%s/.git".format(manifestDir, ".repo/manifests"));
    }
  }
  scheduler.send(Shutdown());
  
  for (int i=0; i<nrOfCheckers+1; i++) {
    receiveOnly!LinkTerminated;
  }
  reviewer.send(Shutdown());
  return res;
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
  auto all = getRulingDirectories(start);//.map!(i => "%s/.repo/manifest.xml".format(i));
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
