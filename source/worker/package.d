/++
 + Copyright: Copyright 2016, Christian Koestlin
 + Authors: Christian Koestlin
 + License: MIT
 +/
module worker;

import androidlogger : AndroidLogger;
import argparse;
import profiled : Profiler, theProfiler;
import std.experimental.logger : LogLevel;
import std.experimental.logger.core : sharedLog;
import std.sumtype : SumType, match;
import std.stdio : stderr;
import std.algorithm : sort, fold;
import std.conv : to;

import worker.common;
import worker.traversal;
import worker.review;
import worker.history;
import worker.upload;
import worker.execute;
import worker.arguments;

int worker_(Arguments arguments)
{
    theProfiler = new Profiler;
    scope (exit)
        theProfiler.dumpJson("trace.json");

    sharedLog = cast(shared)new AndroidLogger(stderr,
            arguments.withColors == Config.StylingMode.on, arguments.logLevel);

    auto projects = arguments.traversalMode == TraversalMode.WALK ? findGitsByWalking(
            arguments.baseDirectory) : findGitsFromManifest(arguments.baseDirectory);

    // dfmt off
    arguments.subcommand.match!(
        (Review r)
        {
            projects.reviewChanges(r.command);
        },
        (Upload u)
        {
            projects.upload(arguments.dryRun, u.topic, u.hashtag, u.changeSetType);
        },
        (Execute e)
        {
            projects.executeCommand(e.command);
        },
        (Log l)
        {
            projects.history(l);
        },
    );
    // dfmt on
    return 0;
}
