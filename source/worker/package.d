/++
 + Copyright: Copyright © 2016, Christian Köstlin
 + Authors: Christian Koestlin
 + License: MIT
 +/
module worker;

public import worker.packageversion;

import androidlogger;
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

// Commandline parsing
@(argparse.Command("review", "r").Description("Show changes of all subprojects."))
struct Review
{
    @NamedArgument
    string command = "magit %s";
}

@(argparse.Command("upload", "u").Description("Upload changes to review."))
struct Upload
{
    @NamedArgument
    string topic;
    @NamedArgument
    string hashtag;
    @NamedArgument
    ChangeSetType changeSetType = ChangeSetType.NORMAL;
}

@(argparse.Command("execute", "run", "e").Description("Run a command on all subprojects."))
struct Execute {
    @NamedArgument
    string command = "git status";
}

@(argparse.Command("version", "v").Description("Show version information."))
struct Version {
    @NamedArgument
    bool v;
}

@(argparse.Command("log", "l"))
struct Log {
    @(NamedArgument("durationSpec", "d").Description("A git duration spec (e.g. 10 days)"))
    string gitDurationSpec;
}

struct Arguments
{
    @ArgumentGroup("Common arguments")
    {
        @(NamedArgument.Description("Simulate commands."))
        bool dryRun = false;

        @(NamedArgument.Description("Use ANSI colors in output."))
        bool withColors = true;

        @(NamedArgument("traversalMode", "mode").Description("Find subprojects with repo or filesystem."))
        TraversalMode traversalMode = TraversalMode.REPO;

        @(NamedArgument("baseDirectory", "base", "dir").Description("Basedirectory."))
        string baseDirectory = ".";

        @(NamedArgument("logLevel", "l").Description("Set logging level."))
        LogLevel logLevel;
    }
    @SubCommands
    SumType!(Default!Review, Upload, Execute, Version, Log) subcommand;
}

int worker_(Arguments arguments)
{
    theProfiler = new Profiler;
    scope (exit)
        theProfiler.dumpJson("trace.json");

    sharedLog = new AndroidLogger(stderr, arguments.withColors, arguments.logLevel);

    // hack for version
    if (arguments.subcommand.match!((Version v) {
            import asciitable;
            import packageversion;
            import colored;

            // dfmt off
            auto table = packageversion
                .getPackages
                .sort!("a.name < b.name")
                .fold!((table, p) => table.row.add(p.name.white).add(p.semVer.lightGray).add(p.license.lightGray).table)
                    (new AsciiTable(3).header.add("Package".bold).add("Version".bold).add("License".bold).table);
            // dfmt on
            stderr.writeln("Packageinfo:\n", table.format.prefix("    ")
                           .headerSeparator(true).columnSeparator(true).to!string);
            return true;
        },
        _ => false
    )) return 0;

    auto projects = arguments.traversalMode == TraversalMode.WALK ? findGitsByWalking(arguments.baseDirectory) : findGitsFromManifest(arguments.baseDirectory);

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
          projects.history(l.gitDurationSpec);
      },
      (_) {}
    );
    return 0;
}
