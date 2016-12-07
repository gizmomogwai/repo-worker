import std.stdio;
import std.concurrency;
import std.file;
import std.algorithm;
import std.parallelism;
import std.process;
import std.string;
import std.stdio;
import std.functional;
import core.thread;

struct Shutdown{}

void review() {
  bool finished = false;
  while (!finished) {
    receive((string workTree) {
        execute(["magit", workTree]);
      },
      (Shutdown s) {
        finished = true;
      });
  }
}

void checkGit(string path, Tid review) {
  auto workTree = "%s/..".format(path);
  auto cmd = ["git", "--work-tree", workTree, "--git-dir", path, "status"];
  auto git = execute(cmd);
  if (git.status != 0) {
    return;
  }
  auto output = git.output;
  if (output.indexOf("modified") != -1
      || output.indexOf("deleted") != -1
      || output.indexOf("Untracked") != -1
      || output.indexOf("Changes") != -1) {
    review.send(workTree);
  }
}

void main() {
  auto reviewGit = spawnLinked(&review);

  auto gitProjects = dirEntries("", ".git", SpanMode.depth).filter!(f => f.isDir && f.name.endsWith(".git"));
  foreach (project; gitProjects) {
    auto task = task(&checkGit, project.name, reviewGit);
    taskPool.put(task);
  }

  taskPool.finish();
  reviewGit.send(Shutdown());
  receiveOnly!LinkTerminated;
}
