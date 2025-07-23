module worker.arguments;

import argparse : ArgumentGroup, Command, Config, Default, Description, Epilog,
    NamedArgument, ansiStylingArgument, SubCommand;
import asciitable : AsciiTable;
import colored : bold, lightGray, white;
import core.runtime : Runtime;
import packageinfo : packages;
import std.algorithm : fold, sort;
import std.conv : to;
import std.experimental.logger : LogLevel;
import std.sumtype : SumType;
import worker.common : ChangeSetType;
import worker.traversal : TraversalMode;

// Commandline parsing
@(Command("review", "r").Description("Show changes of all subprojects"))
struct Review
{
    @(NamedArgument.Description("Command to run in dirty git repositories"))
    string command = "magit %s";
}

@(Command("upload", "u").Description("Upload changes to review"))
struct Upload
{
    @NamedArgument string topic;
    @NamedArgument string hashtag;
    @NamedArgument ChangeSetType changeSetType = ChangeSetType.NORMAL;
    @NamedArgument bool skipReview = false;
}

@(Command("execute", "run", "e").Description("Run a command on all subprojects"))
struct Execute
{
    @NamedArgument string command = "git status";
}

@(Command("log", "l"))
struct Log
{
    @(NamedArgument("durationSpec", "d").Description("A git duration spec (e.g. 10 days)"))
    string gitDurationSpec = "1w";

    @(NamedArgument("author")
            .Description("Filter by author (e.g. john.doe@foobar.com or foobar.com)"))
    string author;
}

auto color(T)(string s, T color)
{
    return Arguments.withColors ? color(s).to!string : s;
}

//dfmt off
@(Command(null)
  .Epilog(() => "PackageInfo:\n" ~ packages
                        .sort!("a.name < b.name")
                        .fold!((table, p) =>
                               table
                               .row
                                   .add(p.name.color(&white))
                                   .add(p.semVer.color(&lightGray))
                                   .add(p.license.color(&lightGray)).table)
                            (new AsciiTable(3)
                                .header
                                    .add("Package".color(&bold))
                                    .add("Version".color(&bold))
                                    .add("License".color(&bold)).table)
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
        @(NamedArgument.Description("Simulate commands"))
        bool dryRun = false;

        @(NamedArgument.Description("Use ANSI colors in output"))
        static auto withColors = ansiStylingArgument;

        @(NamedArgument("traversalMode", "mode")
                .Description("Find subprojects with repo, filesystem walk or just here"))
        TraversalMode traversalMode = TraversalMode.REPO;

        @(NamedArgument("baseDirectory", "base", "dir").Description("Basedirectory"))
        string baseDirectory = ".";

        @(NamedArgument("logLevel", "l").Description("Set logging level"))
        LogLevel logLevel;
    }
    SubCommand!(Default!Review, Upload, Execute, Log) subcommand;
}
