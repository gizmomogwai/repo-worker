/++
 + Copyright: Copyright 2016, Christian Koestlin
 + Authors: Christian Koestlin
 + License: MIT
 +/
module worker;

import argparse;
import androidlogger : AndroidLogger;
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

    sharedLog = new AndroidLogger(stderr, arguments.withColors, arguments.logLevel);

    // hack for version
    if (arguments.subcommand.match!((Version v) {
            import asciitable;
            import packageinfo;
            import colored;

            // dfmt off
            auto table = packageinfo
                .getPackages
                .sort!("a.name < b.name")
                .fold!((table, p) =>
                       table
                           .row
                               .add(p.name.white)
                               .add(p.semVer.lightGray)
                               .add(p.license.lightGray).table)
                    (new AsciiTable(3)
                         .header
                             .add("Package".bold)
                             .add("Version".bold)
                             .add("License".bold).table);
            // dfmt on
            stderr.writeln("Packageinfo:\n", table.format.prefix("    ")
            .headerSeparator(true).columnSeparator(true).to!string);
            return true;
        }, _ => false))
        return 0;

    auto projects = arguments.traversalMode == TraversalMode.WALK ? findGitsByWalking(
            arguments.baseDirectory) : findGitsFromManifest(arguments.baseDirectory);

    arguments.subcommand.match!((Review r) { projects.reviewChanges(r.command); }, (Upload u) {
        projects.upload(arguments.dryRun, u.topic, u.hashtag, u.changeSetType);
    }, (Execute e) { projects.executeCommand(e.command); }, (Log l) {
        projects.history(l);
    }, (_) {});
    return 0;
}
