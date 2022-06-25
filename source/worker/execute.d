module worker.execute;

import std.algorithm : sort, map;
import std.experimental.logger : warning, info, error;
import std.string : format, join, strip;
import std.process;
import std.path : asNormalizedPath;
import std.datetime.stopwatch : StopWatch, AutoStart;
import unit : TIME, onlyRelevant;

void executeCommand(T)(T work, string command)
{
    auto status = 0;
    foreach (project; work.projects.sort!("a.base < b.base"))
    {
        "Running %s in %s".format(command, project.path.asNormalizedPath).warning;
        auto sw = StopWatch(AutoStart.yes);
        auto res = command.executeShell(null, std.process.Config.none, size_t.max, project.path);
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
                    project.path.asNormalizedPath);
        // dfmt on
        auto output = res.output.strip;
        if (res.status == 0) {
            description.warning;
            output.info;
        } else {
            description.error;
            output.error;
        }
    }
}
