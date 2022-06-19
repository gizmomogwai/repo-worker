/++
 + Copyright: Copyright © 2016, Christian Köstlin
 + Authors: Christian Koestlin, Christian Köstlin
 + License: MIT
 +/

import argparse;
import worker;

/+
string calcPackageVersionTable() {
    import std;
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
    return "Packageinfo:\n" ~ table.format.prefix("    ")
        .headerSeparator(true).columnSeparator(true).to!string;
}
+/

mixin CLI!(worker.Arguments).main!((arguments) {
    import worker : worker_;

    return worker_(arguments);
});
