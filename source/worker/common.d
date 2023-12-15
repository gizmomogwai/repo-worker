module worker.common;

import optional : Optional, no, some;
import std.experimental.logger : trace, error;
import std.string : format, join, replace, indexOf, strip;
import std.process : execute, Config, spawnProcess, Pid;
import std.path : asAbsolutePath, asNormalizedPath;
import std.array : array;
import std.range : chain;

enum ChangeSetType
{
    NORMAL,
    WIP,
    PRIVATE,
    DRAFT,
}

struct Command
{
    // names end with _ because the fluid api needs methods with the same name
    string[] command_;
    bool dry_ = false;
    string message_;
    string workdir_;
    this(string[] cmd)
    {
        this.command_ = cmd;
    }

    this(string[] cmd, bool dry, string message, string workdir)
    {
        command_ = cmd;
        dry_ = dry;
        message_ = message;
        workdir_ = workdir;
    }

    auto message(string message)
    {
        return Command(this.command_, this.dry_, message, workdir_);
    }

    auto dry(bool dry = true)
    {
        return Command(this.command_, dry, this.message_, workdir_);
    }

    auto workdir(string wd)
    {
        return Command(this.command_, dry_, this.message_, wd);
    }

    Optional!string run()
    {
        "%s: executing %s (%s)".format(message_, command_, command_.join(" ")).trace;

        if (dry_)
        {
            return no!string;
        }
        auto res = execute(command_, null, Config.none, size_t.max, workdir_);
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

    Pid spawn()
    {
        "%s: spawning process %s (%s)".format(message_, command_, command_.join(" ")).trace;
        return spawnProcess(command_);
    }
}

struct Project
{
    private string base;
    private string path;
    this(string base, string s)
    {
        this.base = base.asAbsolutePath.asNormalizedPath.array;
        if (s[0] == '/')
        {
            this.path = s.asAbsolutePath.asNormalizedPath.array;
            assert(0);
        }
        else
        {
            this.path = (this.base ~ "/" ~ s).asAbsolutePath.asNormalizedPath.array;
        }
    }

    string absolutePath()
    {
        return path;
    }
    auto git(string[] args...)
    {
        auto workTree = this.path;
        auto gitDir = "%s/.git".format(workTree);
        auto cmd = ["git", "--work-tree", workTree, "--git-dir", gitDir].chain(args).array;
        return Command(cmd);
    }

    string relativePath()
    {
        string result = path.asAbsolutePath.asNormalizedPath.array.replace(base, "");
        if (result[0] == '/')
        {
            result = result[1..$];
        }
        return result;
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
