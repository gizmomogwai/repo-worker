module worker.review;

import worker.common;
import std.string : format, replace, indexOf;
import std.experimental.logger : info, trace;
import std.typecons : Tuple;
import std.concurrency : Tid, thisTid, receive, send, spawnLinked, receiveOnly, LinkTerminated;
import std.process : executeShell;
import std.algorithm : each;
import std.array : empty, front, popFront;
import std.parallelism;
import std.range : iota;

// Worker
struct Shutdown
{
}

struct Reschedule
{
}

struct ReportForDuty
{
}

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
                project
                    .git("status")
                    .message("checker: getting status for '%s'".format(project.shortPath))
                    .run
                    .each!((string output) {
                            auto dirty = output.dirty;
                            "checker: '%s' is %s".format(project.shortPath,
                                                         dirty).info;
                            if (dirty == State.dirty)
                            {
                                reviewer.send(project);
                            }
                        })
                    ;
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

void reviewChanges(T)(T work, string reviewCommand)
{
    int nrOfCheckers = std.parallelism.totalCPUs;

    auto theScheduler = spawnLinked(&worker.review.scheduler, nrOfCheckers);

    auto reviewer = spawnLinked(&review, reviewCommand);
    foreach (i; iota(nrOfCheckers))
    {
        spawnLinked(&checker, theScheduler, reviewer);
    }

    foreach (project; work.projects)
    {
        theScheduler.send(project);
    }

    theScheduler.send(Shutdown());

    for (int i = 0; i < nrOfCheckers + 1; i++)
    {
        receiveOnly!LinkTerminated;
    }
    reviewer.send(Shutdown());
}
