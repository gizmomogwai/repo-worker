module worker.common;

import optional : Optional, no, some;
import std.experimental.logger : trace, error;
import std.string : format, join, replace, indexOf, strip;
import std.process : execute;
import std.path : asAbsolutePath, asNormalizedPath;
import std.array : array;
import std.range : chain;

struct Command
{
    // names end with _ because the fluid api needs methods with the same name
    string[] command_;
    bool dry_ = false;
    string message_;
    this(string[] cmd)
    {
        this.command_ = cmd;
    }

    this(string[] cmd, bool dry, string message)
    {
        command_ = cmd;
        dry_ = dry;
        message_ = message;
    }

    Command message(string message)
    {
        return Command(this.command_, this.dry_, message);
    }

    Command dry(bool dry = true)
    {
        return Command(this.command_, dry, this.message_);
    }

    Optional!string run()
    {
        "%s: executing %s (%s)".format(message_, command_, command_.join(" ")).trace;

        if (dry_)
        {
            return no!string;
        }
        auto res = execute(command_);
        if (res.status == 0)
        {
            return res.output.some;
        }
        else
        {
            "Problem working on: %s".format(command_).error;
            res.output.error;
            return no!string;
        }
    }
}


struct Project
{
    string base;
    string path;
    this(string base, string s)
    {
        this.base = base.asAbsolutePath.asNormalizedPath.array;
        if (s[0] == '/')
        {
            this.path = s.asAbsolutePath.asNormalizedPath.array;
        }
        else
        {
            this.path = (this.base ~ "/" ~ s).asAbsolutePath.asNormalizedPath.array;
        }
    }

    auto git(string[] args...)
    {
        auto workTree = this.path;
        auto gitDir = "%s/.git".format(workTree);
        auto cmd = ["git", "--work-tree", workTree, "--git-dir", gitDir].chain(args).array;
        return Command(cmd);
    }

    string shortPath()
    {
        return path.asAbsolutePath.asNormalizedPath.array.replace(base, "");
    }
}

struct Commit
{
    string sha1;
    string comment;
    this(string line)
    {
        auto idx = line.indexOf(' ');
        sha1 = line[0 .. idx];
        comment = line[idx + 1 .. $];
    }

    this(string sha1, string comment)
    {
        this.sha1 = sha1;
        this.comment = comment;
    }
}
