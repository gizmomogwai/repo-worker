import std.concurrency;
import std.range;
import std.file;
import std.string;
import std.algorithm;
import std.parallelism;
import std.process;

struct Shutdown{}
struct Reschedule{}

void review() {
  bool finished = false;

  while (!finished) {
    receive(
      (string workTree) {
        execute(["magit", workTree]);
      },
      (Shutdown s) {
        finished = true;
      });
  }
}

void checker(Tid scheduler, Tid reviewer) {
  bool finished = false;

  scheduler.send(thisTid());
  while (!finished) {
    receive(
      (string path) {
        auto workTree = "%s/..".format(path);
        auto cmd = ["git", "--work-tree", workTree, "--git-dir", path, "status"];
        auto git = execute(cmd);
        if (git.status == 0) {
          auto output = git.output;
          if (output.indexOf("modified") != -1
              || output.indexOf("deleted") != -1
              || output.indexOf("Untracked") != -1
              || output.indexOf("Changes") != -1) {
            reviewer.send(workTree);
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
        if (shuttingDown) {
          checker.send(Shutdown());
          nrOfCheckers--;
          if (nrOfCheckers == 0) {
            finished = true;
          }
        } else {
          availableCheckers ~= checker;
          thisTid().send(Reschedule());
        }
      },
      (Reschedule r) {
        if (!availableWork.empty() && !availableCheckers.empty()) {
          auto work = availableWork.front; availableWork.popFront();
          auto checker = availableCheckers.front; availableCheckers.popFront();
          checker.send(work);
        }
      },
      (Shutdown s) {
        shuttingDown = true;

        // no work todo and some checkers might already be in wait
        if (availableWork.empty()) {
          foreach (checker; availableCheckers) {
            checker.send(Shutdown());
            nrOfCheckers--;
          }
          availableCheckers = [];
          if (nrOfCheckers == 0) {
            finished = true;
          }
        }
      }
    );
  }
}

/++
 + direntries -> queue -> scheduler ----> checker ----> queue -> review
 +                                   \--> checker --/
 +                                    \-> checker -/
 + checker -> git status
 + review -> magit
 +/
void main() {
  int nrOfCheckers = std.parallelism.totalCPUs;
  // writeln("using ", nrOfCheckers);
  auto scheduler = spawnLinked(&scheduler);
  auto reviewer = spawnLinked(&review);
  foreach (i; iota(nrOfCheckers)) {
    spawnLinked(&checker, scheduler, reviewer);
  }
  scheduler.send(nrOfCheckers);

  auto gitProjects = dirEntries("", ".git", SpanMode.depth)
    .filter!(f => f.isDir && f.name.endsWith(".git"));
  foreach (project; gitProjects) {
    scheduler.send(project.name);
  }
  scheduler.send(Shutdown());

  for (int i=0; i<nrOfCheckers+1; i++) {
    receiveOnly!LinkTerminated;
  }
  reviewer.send(Shutdown());
}
