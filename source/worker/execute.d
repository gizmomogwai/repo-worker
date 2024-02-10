module worker.execute;

import std.algorithm : map, sort;
import std.datetime.stopwatch : AutoStart, StopWatch;
import std.experimental.logger : error, info, warning;
import std.path : asNormalizedPath;
import std.process : executeShell, Config;
import std.string : format, join, strip;
import unit : onlyRelevant, TIME;

void executeCommand(T)(T work, string command)
{
    auto status = 0;
    foreach (project; work.projects.sort!("a.relativePath < b.relativePath"))
    {
        "Running %s in %s".format(command, project.absolutePath).info;
        auto sw = StopWatch(AutoStart.yes);
        auto res = command.executeShell(workDir : project.absolutePath);
        if (res.status != 0)
        {
            status = res.status;
        }
        auto duration = sw.peek().total!("msecs");
        // dfmt off
        auto description = "Finished with %s in %s (%s)"
            .format(res.status,
                    TIME
                        .transform(duration)
                        .onlyRelevant
                        .map!(p => "%s%s".format(p.value, p.name))
                        .join(" "),
                    project.absolutePath);
        // dfmt on
        auto output = res.output.strip;
        if (res.status == 0)
        {
            description.info;
            output.info;
        }
        else
        {
            description.error;
            output.error;
        }
    }
}
