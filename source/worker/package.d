/++
 + Copyright: Copyright 2016, Christian Koestlin
 + Authors: Christian Koestlin
 + License: MIT
 +/
module worker;

import std.conv : to;
import std.experimental.logger : LogLevel;
import std.experimental.logger.core : sharedLog;
import std.stdio : stderr;
import worker.arguments;
import worker.common;
import worker.execute;
import worker.history;
import worker.review;
import worker.traversal;
import worker.upload;

int worker_(Arguments arguments)
{
    import profiled : Profiler, theProfiler;

    theProfiler = new Profiler;
    scope (exit)
        theProfiler.dumpJson("trace.json");

    import androidlogger : AndroidLogger;

    sharedLog = cast(shared) new AndroidLogger(stderr, arguments.withColors
            ? true : false, arguments.logLevel);

    auto projects = arguments.traversalMode.findGits(arguments.baseDirectory);

    import argparse : match;

    // dfmt off
    arguments.subcommand.match!(
        (Review r)
        {
            projects.reviewChanges(r.command);
        },
        (Upload u)
        {
            projects.upload(arguments.dryRun, u.topic, u.hashtag, u.changeSetType, u.skipReview);
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
