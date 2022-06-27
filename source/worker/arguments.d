module worker.arguments;

import worker.traversal : TraversalMode;
import worker.common : ChangeSetType;
import std.sumtype : SumType;

import argparse;
import std.experimental.logger : LogLevel;

// Commandline parsing
@(Command("review", "r").Description("Show changes of all subprojects."))
struct Review
{
    @NamedArgument string command = "magit %s";
}

@(Command("upload", "u").Description("Upload changes to review."))
struct Upload
{
    @NamedArgument string topic;
    @NamedArgument string hashtag;
    @NamedArgument ChangeSetType changeSetType = ChangeSetType.NORMAL;
}

@(Command("execute", "run", "e").Description("Run a command on all subprojects."))
struct Execute
{
    @NamedArgument string command = "git status";
}

@(Command("log", "l"))
struct Log
{
    @(NamedArgument("durationSpec", "d").Description("A git duration spec (e.g. 10 days)"))
    string gitDurationSpec;

    @(NamedArgument("author")
            .Description("Filter by author (e.g. john.doe@foobar.com or foobar.com)"))
    string author;
}

import packageinfo;
import asciitable : AsciiTable;
import std.algorithm : sort, fold;
import colored : bold, white, lightGray;
import std.conv : to;
static foreach (p; packageinfo.packages)
{
    pragma(msg, p);
}
//dfmt off
@(Command("Works on a set of git projects")
  .Epilog(() => "PackageInfo:\n" ~ packageinfo
                        .packages
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
                             .add("License".bold).table)
                        .format
                            .prefix("    ")
                            .headerSeparator(true)
                            .columnSeparator(true)
                        .to!string))
// dfmt on
struct Arguments
{
    @ArgumentGroup("Common arguments")
    {
        @(NamedArgument.Description("Simulate commands."))
        bool dryRun = false;

        @(NamedArgument.Description("Use ANSI colors in output."))
        bool withColors = true;

        @(NamedArgument("traversalMode", "mode")
                .Description("Find subprojects with repo or filesystem."))
        TraversalMode traversalMode = TraversalMode.REPO;

        @(NamedArgument("baseDirectory", "base", "dir").Description("Basedirectory."))
        string baseDirectory = ".";

        @(NamedArgument("logLevel", "l").Description("Set logging level."))
        LogLevel logLevel;
    }
    @SubCommands SumType!(Default!Review, Upload, Execute, Log) subcommand;
}
